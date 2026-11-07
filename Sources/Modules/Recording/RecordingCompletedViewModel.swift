//
//  RecordingCompletedViewModel.swift
//  ALog
//
//  Created by Xin Du on 2023/07/15.
//

import Foundation
import CoreData
import XLog

class RecordingCompletedViewModel: ObservableObject {
    var voiceURL: URL
    let container = DataContainer.shared
    let moc: NSManagedObjectContext
    let config = Config.shared
    let trans = Transcription()
    private let parentID: NSManagedObjectID?
    private var transcriptionTask: Task<Void, Never>?
    
    @Published var hasTranscribed = false
    @Published var isTranscribing = false
    @Published var transcribedText: String? {
        didSet {
            hasTranscribed = true
            content = transcribedText ?? ""
        }
    }
    
    @Published var transcriptionError: String?
    @Published var saved = false
    @Published var saveError: String?
    @Published var content = ""
    @Published var duration: Double = 0
    @Published var canBeSaved: Bool = false
    
    init(voicePath: URL, parentID: NSManagedObjectID? = nil) {
        self.voiceURL = voicePath
        self.parentID = parentID
        moc = container.context

    }
    
    deinit {
        transcriptionTask?.cancel()
        #if DEBUG
            XLog.debug("✖︎ RecordingCompletedViewModel", source: "Recording")
        #endif
    }
    
    @MainActor func prepare() async {
        duration = await FileHelper.getAudioDuration(voiceURL)
        canBeSaved = true
    }

    func transcribe() {
        guard config.transEnabled else { return }
        guard isTranscribing == false else { return }
        
        isTranscribing = true
        transcriptionError = nil
        transcriptionTask = Task { @MainActor in
            defer {
                isTranscribing = false
                transcriptionTask = nil
            }
            do {
                let txt = try await trans.transcribe(
                    voiceURL: voiceURL, provider: config.transProvider, lang: config.transLang,
                    localModel: config.localTranscriptionModel
                )
                try Task.checkCancellation()
                transcribedText = txt
            } catch is CancellationError {
                // Closing or discarding a recording is not a transcription failure.
            } catch {
                if !Task.isCancelled {
                    transcriptionError = ErrorHelper.desc(error)
                }
            }
        }
    }

    func cancelTranscription() {
        transcriptionTask?.cancel()
    }
    
    func save() {
        guard !isTranscribing, !saved else { return }
        saveError = nil
        do {
            let destination = FileHelper.fullAudioURL(for: voiceURL.lastPathComponent)
            if voiceURL.standardizedFileURL != destination.standardizedFileURL {
                voiceURL = try FileHelper.moveAudioFile(voiceURL)
            }
            try JournalStore.add(content: content, file: voiceURL.lastPathComponent,
                                 duration: duration, transcribed: hasTranscribed,
                                 parentID: parentID, in: moc)
            saved = true
        } catch {
            saveError = error.localizedDescription
            XLog.error(error, source: "recording")
        }
    }
    
    func delete() {
        cancelTranscription()
        do {
            XLog.debug("Deleting temporary audio file at \(voiceURL.absoluteString)", source: "recording")
            try FileManager.default.removeItem(at: voiceURL)
        } catch {
            XLog.error(error, source: "recording")
        }
    }
}
