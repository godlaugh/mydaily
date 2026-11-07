import Combine
import Foundation

@MainActor
final class TranscriptionModelStore: ObservableObject {
    private static let int8Store = TranscriptionModelStore(manifest: LocalTranscriptionModel.senseVoiceSmall.manifest)
    private static let fp32Store = TranscriptionModelStore(manifest: LocalTranscriptionModel.senseVoiceSmallFP32.manifest)

    // Retain the original entry point for callers that specifically use INT8.
    static var shared: TranscriptionModelStore { store(for: .senseVoiceSmall) }

    static func store(for model: LocalTranscriptionModel) -> TranscriptionModelStore {
        switch model {
        case .senseVoiceSmall: return int8Store
        case .senseVoiceSmallFP32: return fp32Store
        }
    }

    @Published private(set) var state: ModelInstallState
    @Published private(set) var downloadProgress: ModelDownloadProgress?
    @Published private(set) var activeTranscriptions = 0

    private let rootDirectory: URL
    private let manifest: LocalModelManifest
    private let downloader: any ModelArtifactDownloading
    private var downloadTask: Task<Void, Never>?
    private var downloadID: UUID?
    private var lastProgressPublication: TimeInterval = 0

    init(
        rootDirectory: URL = URL.applicationSupportDirectory.appendingPathComponent("TranscriptionModels", isDirectory: true),
        manifest: LocalModelManifest = LocalTranscriptionModel.senseVoiceSmall.manifest,
        downloader: any ModelArtifactDownloading = ModelArtifactDownloader()
    ) {
        self.rootDirectory = rootDirectory
        self.manifest = manifest
        self.downloader = downloader
        do {
            _ = try ModelInstallation.installedFiles(root: rootDirectory, manifest: manifest)
            state = .installed
        } catch ModelInstallError.notInstalled {
            state = .notDownloaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func download() {
        if case .downloading = state { return }
        if state == .installed { return }
        guard activeTranscriptions == 0 else {
            state = .failed(ModelInstallError.modelInUse.localizedDescription)
            return
        }
        let id = UUID()
        downloadID = id
        state = .downloading(progress: 0)
        downloadProgress = ModelDownloadProgress(
            phase: .connecting, receivedBytes: 0,
            totalBytes: manifest.artifacts.reduce(0) { $0 + $1.byteCount },
            bytesPerSecond: 0, sourceHost: manifest.model.remoteURL.host ?? ""
        )
        lastProgressPublication = ProcessInfo.processInfo.systemUptime
        downloadTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.downloadID == id {
                    self.downloadTask = nil
                    self.downloadID = nil
                }
            }
            do {
                let staging = try await ModelInstallation.prepare(
                    root: self.rootDirectory, manifest: self.manifest, downloader: self.downloader
                ) { [weak self] progress in
                    Task { @MainActor in self?.updateProgress(progress, id: id) }
                }
                defer { try? FileManager.default.removeItem(at: staging) }
                try Task.checkCancellation()
                guard self.downloadID == id else { return }
                // No suspension between the cancellation check, atomic publish,
                // and state update, so a cancel/remove cannot race the commit.
                try ModelInstallation.commit(staging: staging, root: self.rootDirectory, manifest: self.manifest)
                self.state = .installed
                self.downloadProgress = nil
            } catch {
                guard self.downloadID == id else { return }
                // cancelDownload already publishes its state. Do not overwrite a
                // subsequent removal error when the cancelled network call unwinds.
                if !Task.isCancelled {
                    self.state = .failed(error.localizedDescription)
                    self.downloadProgress = nil
                }
            }
        }
    }

    func cancelDownload() {
        guard case .downloading = state else { return }
        downloadTask?.cancel()
        state = .notDownloaded
        downloadProgress = nil
    }

    func installedFiles() throws -> LocalModelFiles {
        guard state == .installed else { throw ModelInstallError.notInstalled }
        do {
            return try ModelInstallation.installedFiles(root: rootDirectory, manifest: manifest)
        } catch {
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    func beginUse() throws -> LocalModelFiles {
        let files = try installedFiles()
        activeTranscriptions += 1
        return files
    }

    func endUse() {
        activeTranscriptions = max(0, activeTranscriptions - 1)
    }

    func remove() throws {
        guard activeTranscriptions == 0 else { throw ModelInstallError.modelInUse }
        cancelDownload()
        let directory = ModelInstallation.directory(root: rootDirectory, manifest: manifest)
        do {
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
            state = .notDownloaded
        } catch {
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    // Allows deterministic tests to await cleanup without sleeps or polling.
    func waitForPendingDownload() async {
        await downloadTask?.value
    }

    private func updateProgress(_ progress: ModelDownloadProgress, id: UUID) {
        guard downloadID == id, case .downloading = state else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let previous = downloadProgress
        let importantChange = previous?.phase != progress.phase
            || previous?.sourceHost != progress.sourceHost
            || (previous?.receivedBytes == 0 && progress.receivedBytes > 0)
            || progress.receivedBytes < (previous?.receivedBytes ?? 0)
        if importantChange || now - lastProgressPublication >= 0.25 {
            lastProgressPublication = now
            downloadProgress = progress
            let fraction = Double(progress.receivedBytes) / Double(max(progress.totalBytes, 1))
            state = .downloading(progress: min(1, max(0, fraction)))
        }
    }
}
