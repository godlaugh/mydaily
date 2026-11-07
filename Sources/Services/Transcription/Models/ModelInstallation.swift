import CryptoKit
import Foundation

enum ModelInstallation {
    private static let receiptName = "installation.json"
    // A fresh identifier on every process launch distinguishes abandoned work
    // from a cancelled download that is still unwinding in this process.
    private static let stagingPrefix = ".staging-"
    private static let currentProcessStagingPrefix = stagingPrefix + UUID().uuidString + "-"

    private struct Receipt: Codable, Equatable {
        struct File: Codable, Equatable {
            let name: String
            let bytes: Int64
            let sha256: String
        }
        let revision: String
        let files: [File]

        init(manifest: LocalModelManifest) {
            revision = manifest.revision
            files = manifest.artifacts.map { File(name: $0.filename, bytes: $0.byteCount, sha256: $0.sha256) }
        }
    }

    static func directory(root: URL, manifest: LocalModelManifest) -> URL {
        root.appendingPathComponent(manifest.directoryName, isDirectory: true)
    }

    static func createStagingDirectory(root: URL) throws -> URL {
        let staging = root.appendingPathComponent(currentProcessStagingPrefix + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        return staging
    }

    static func removeAbandonedStagingDirectories(root: URL) throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: root.path) else { return }
        let children = try manager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        for child in children {
            let name = child.lastPathComponent
            guard name.hasPrefix(stagingPrefix), !name.hasPrefix(currentProcessStagingPrefix) else { continue }
            let suffix = String(name.dropFirst(stagingPrefix.count))
            let legacyName = UUID(uuidString: suffix) != nil
            let owner = String(suffix.prefix(36))
            let remainder = suffix.dropFirst(36)
            let ownedName = UUID(uuidString: owner) != nil
                && remainder.first == "-"
                && UUID(uuidString: String(remainder.dropFirst())) != nil
            guard legacyName || ownedName else { continue }
            do {
                let values = try child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values.isDirectory == true, values.isSymbolicLink != true else { continue }
                try manager.removeItem(at: child)
            } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
                // A rapid retry can overlap a cancelled prepare's cleanup.
                // Another operation already removed this orphan successfully.
                continue
            }
        }
    }

    // Checks the receipt and file sizes cheaply when opening the model. Content
    // hashes are verified before the installation is published atomically.
    static func installedFiles(root: URL, manifest: LocalModelManifest) throws -> LocalModelFiles {
        let directory = directory(root: root, manifest: manifest)
        guard FileManager.default.fileExists(atPath: directory.path) else {
            throw ModelInstallError.notInstalled
        }
        do {
            let data = try Data(contentsOf: directory.appendingPathComponent(receiptName))
            let receipt = try JSONDecoder().decode(Receipt.self, from: data)
            guard receipt == Receipt(manifest: manifest) else {
                throw ModelInstallError.invalidInstallation
            }
            for artifact in manifest.artifacts {
                try validateSize(directory.appendingPathComponent(artifact.filename), artifact: artifact)
            }
        } catch {
            throw ModelInstallError.invalidInstallation
        }
        return LocalModelFiles(
            modelURL: directory.appendingPathComponent(manifest.model.filename),
            tokensURL: directory.appendingPathComponent(manifest.tokens.filename)
        )
    }

    // Runs on the cooperative executor, away from the main actor. The directory
    // remains private until both files pass verification and the receipt exists.
    static func prepare(
        root: URL,
        manifest: LocalModelManifest,
        downloader: any ModelArtifactDownloading,
        progress: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws -> URL {
        try Task.checkCancellation()
        let manager = FileManager.default
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        try removeAbandonedStagingDirectories(root: root)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var rootURL = root
        try rootURL.setResourceValues(resourceValues)
        let staging = try createStagingDirectory(root: root)
        var prepared = false
        defer {
            if !prepared { try? manager.removeItem(at: staging) }
        }

        let total = manifest.artifacts.reduce(Int64(0)) { $0 + $1.byteCount }
        var completed: Int64 = 0
        for artifact in manifest.artifacts {
            try Task.checkCancellation()
            let baseline = completed
            let destination = staging.appendingPathComponent(artifact.filename)
            var lastError: Error?
            for sourceURL in artifact.downloadURLs {
                try Task.checkCancellation()
                progress(ModelDownloadProgress(phase: .connecting, receivedBytes: baseline, totalBytes: total,
                                               bytesPerSecond: 0, sourceHost: sourceURL.host ?? ""))
                do {
                    try await downloader.download(artifact, from: sourceURL, to: destination) { update in
                        let current = baseline + min(max(update.receivedBytes, 0), artifact.byteCount)
                        progress(ModelDownloadProgress(phase: update.phase, receivedBytes: current, totalBytes: total,
                                                       bytesPerSecond: update.bytesPerSecond, sourceHost: update.sourceHost))
                    }
                    try Task.checkCancellation()
                    progress(ModelDownloadProgress(phase: .verifying, receivedBytes: baseline + artifact.byteCount,
                                                   totalBytes: total, bytesPerSecond: 0, sourceHost: sourceURL.host ?? ""))
                    try validateSize(destination, artifact: artifact)
                    try validateChecksum(destination, artifact: artifact)
                    lastError = nil
                    break
                } catch {
                    try? manager.removeItem(at: destination)
                    // A user's cancel must never start another source.
                    if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                        throw CancellationError()
                    }
                    guard canTryAnotherSource(after: error) else { throw error }
                    lastError = error
                }
            }
            if let lastError { throw lastError }
            completed += artifact.byteCount
        }
        try Task.checkCancellation()
        let receipt = try JSONEncoder().encode(Receipt(manifest: manifest))
        try receipt.write(to: staging.appendingPathComponent(receiptName), options: .atomic)
        prepared = true
        return staging
    }

    static func commit(staging: URL, root: URL, manifest: LocalModelManifest) throws {
        let destination = directory(root: root, manifest: manifest)
        // A previous failed/incomplete installation may exist. Only discard it
        // after its replacement has been fully downloaded and verified.
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: staging, to: destination)
    }

    private static func canTryAnotherSource(after error: Error) -> Bool {
        if let error = error as? URLError {
            switch error.code {
            case .cannotCreateFile, .cannotOpenFile, .cannotCloseFile,
                 .cannotWriteToFile, .cannotRemoveFile, .cannotMoveFile:
                return false
            default:
                return true
            }
        }
        if let error = error as? ModelInstallError {
            switch error {
            case .invalidResponse, .invalidSize, .invalidChecksum:
                return true
            default:
                return false
            }
        }
        // Disk permissions/full-disk and other installation errors cannot be
        // repaired by downloading the same bytes again from another server.
        return false
    }

    private static func validateSize(_ url: URL, artifact: ModelArtifact) throws {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              let size = values.fileSize,
              Int64(size) == artifact.byteCount else {
            throw ModelInstallError.invalidSize(artifact.filename)
        }
    }

    private static func validateChecksum(_ url: URL, artifact: ModelArtifact) throws {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        while let data = try file.read(upToCount: 1_048_576), !data.isEmpty {
            try Task.checkCancellation()
            hash.update(data: data)
        }
        let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == artifact.sha256.lowercased() else {
            throw ModelInstallError.invalidChecksum(artifact.filename)
        }
    }
}
