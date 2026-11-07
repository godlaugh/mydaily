//
//  Transcription.swift
//  ALog
//
//  Created by Xin Du on 2023/07/15.
//

import Foundation
import XLog
import Combine

enum TranscriptionError: LocalizedError {
    case invalidCustomServer
    var errorDescription: String? {
        switch self {
        case .invalidCustomServer: return L(.error_invalid_custom_server)
        }
    }
}

class Transcription {
    
    static let shared = Transcription()
    
    private let TAG = "Trans"

    struct QueueSettings {
        let provider: TranscriptionProvider
        let language: TranscriptionLang
        let usesAppServer: Bool
        var localModel: LocalTranscriptionModel = .senseVoiceSmall
    }
    typealias QueueExecution = (URL, TranscriptionProvider, TranscriptionLang, LocalTranscriptionModel) async throws -> String

    private let queueSettings: () -> QueueSettings
    private let queueExecution: QueueExecution?
    
    private struct Job {
        let memo: MemoEntity
        let provider: TranscriptionProvider
        let language: TranscriptionLang
        let localModel: LocalTranscriptionModel
        let concurrencyLimit: Int
        let delay: UInt64
        let completion: (Result<String, Error>) -> Void
    }
    private var memoQueue: [Job] = []
    private var activeTask = 0
    private var exclusiveTaskActive = false

    init(
        queueSettings: @escaping () -> QueueSettings = {
            QueueSettings(provider: Config.shared.transProvider,
                          language: Config.shared.transLang,
                          usesAppServer: Config.shared.serverType == .app,
                          localModel: Config.shared.localTranscriptionModel)
        },
        queueExecution: QueueExecution? = nil
    ) {
        self.queueSettings = queueSettings
        self.queueExecution = queueExecution
    }
    
    let hallucinationList: Set<String> = [
        "请不吝点赞 订阅 转发 打赏支持明镜与点点栏目",
        "請不吝點贊訂閱轉發打賞支持明鏡與點點欄目",
        "字幕由Amara.org社区提供",
        "字幕由Amara.org社区提供 字幕由Amara.org社区提供",
        "小編字幕由Amara.org社區提供",
        "字幕by索兰娅",
        "由 Amara.org 社群提供的字幕"
    ]
    
    func transcribe(voiceURL: URL, provider: TranscriptionProvider, lang: TranscriptionLang,
                    localModel: LocalTranscriptionModel? = nil) async throws -> String {
        XLog.info("Transcribe \(voiceURL.lastPathComponent) using \(provider). lang = \(lang.rawValue)", source: TAG)
        if provider == .apple {
            let text = try await SpeechRecognizer.shared.transcribe(voiceURL, lang: lang)
            return text
        } else if provider == .senseVoice {
            let (store, files) = try await MainActor.run {
                let store = TranscriptionModelStore.store(for: localModel ?? Config.shared.localTranscriptionModel)
                return (store, try store.beginUse())
            }
            do {
                let text = try await SenseVoiceTranscriber.shared.transcribe(
                    voiceURL: voiceURL,
                    modelURL: files.modelURL,
                    tokensURL: files.tokensURL,
                    language: lang.senseVoiceLanguage
                )
                await MainActor.run { store.endUse() }
                return text
            } catch {
                await MainActor.run { store.endUse() }
                throw error
            }
        } else if provider == .openai {
            if Config.shared.serverType == .custom && !Config.shared.isServerSet {
                throw TranscriptionError.invalidCustomServer
            }
            
            let model = Config.shared.transModel
            let text = try await OpenAIClient.shared.transcribe(voiceURL, lang: lang, model: model.name).text
            if hallucinationList.contains(text) {
                XLog.info("😵‍💫 skip '\(text)'", source: TAG)
                return ""
            }
            return text
        }
        return ""
    }

    /// Called when the selected engine changes and when the app opens.
    /// Holding a model lease also protects a preload from concurrent deletion.
    @MainActor
    func prepareSelectedModel() async {
        guard Config.shared.transProvider == .senseVoice else {
            await SenseVoiceTranscriber.shared.unload()
            return
        }
        let store = TranscriptionModelStore.store(for: Config.shared.localTranscriptionModel)
        guard let files = try? store.beginUse() else { return }
        defer { store.endUse() }
        do {
            try await SenseVoiceTranscriber.shared.prepare(
                modelURL: files.modelURL, tokensURL: files.tokensURL,
                language: Config.shared.transLang.senseVoiceLanguage
            )
        } catch is CancellationError {
            // Changing engines cancels the view task that requested preloading.
        } catch {
            XLog.error(error, source: "Local transcription preload")
        }
    }
    
    func transcribe(_ memo: MemoEntity, completion: @escaping (Result<String, Error>) -> Void) {
        // Capture the user's engine choice when submitting. Switching settings must
        // never turn an already queued local recording into a cloud upload.
        let settings = queueSettings()
        let provider = settings.provider
        let usesAppServer = settings.usesAppServer
        memoQueue.append(Job(
            memo: memo, provider: provider, language: settings.language,
            localModel: settings.localModel,
            concurrencyLimit: provider == .openai ? (usesAppServer ? 2 : 4) : 1,
            delay: provider == .senseVoice ? 0 : (provider == .apple || usesAppServer ? 1 : 0),
            completion: completion
        ))
        processNext()
    }
    
    private func processNext() {
        while let job = memoQueue.first,
              !exclusiveTaskActive, activeTask < job.concurrencyLimit {
            activeTask += 1
            exclusiveTaskActive = job.concurrencyLimit == 1
            memoQueue.removeFirst()
            
            Task { @MainActor in
                defer {
                    activeTask -= 1
                    if job.concurrencyLimit == 1 { exclusiveTaskActive = false }
                    processNext()
                }
                do {
                    try await Task.sleep(nanoseconds: job.delay * 1_000_000_000)
                    guard !job.memo.isDeleted, job.memo.managedObjectContext != nil,
                          let file = job.memo.file else { throw CancellationError() }
                    let voiceURL = FileHelper.fullAudioURL(for: file)
                    let text: String
                    if let queueExecution {
                        text = try await queueExecution(voiceURL, job.provider, job.language, job.localModel)
                    } else {
                        text = try await transcribe(voiceURL: voiceURL, provider: job.provider, lang: job.language,
                                                    localModel: job.localModel)
                    }
                    job.completion(.success(text))
                } catch {
                    job.completion(.failure(error))
                }
            }
        }
    }
}
