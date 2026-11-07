import CryptoKit
import Foundation
import XCTest
@testable import ALog

@MainActor
final class TranscriptionModelStoreTests: XCTestCase {
    func testVerifiedInstallSurvivesRelaunchAndCannotBeRemovedWhileInUse() async throws {
        let fixture = try ModelStoreFixture()
        defer { fixture.removeFiles() }
        let store = fixture.store()
        store.download()
        await store.waitForPendingDownload()

        XCTAssertEqual(store.state, .installed)
        let files = try store.beginUse()
        XCTAssertEqual(try Data(contentsOf: files.modelURL), fixture.modelData)
        XCTAssertEqual(try Data(contentsOf: files.tokensURL), fixture.tokensData)
        XCTAssertEqual(store.activeTranscriptions, 1)
        XCTAssertThrowsError(try store.remove())
        XCTAssertEqual(store.state, .installed)
        store.endUse()

        let reopened = fixture.store()
        XCTAssertEqual(reopened.state, .installed)
        try reopened.remove()
        XCTAssertEqual(reopened.state, .notDownloaded)
        XCTAssertThrowsError(try reopened.installedFiles())
    }

    func testSameSizeCorruptionFailsChecksumAndCanBeRetried() async throws {
        let fixture = try ModelStoreFixture(behavior: .corruptModel)
        defer { fixture.removeFiles() }
        let store = fixture.store()
        store.download()
        await store.waitForPendingDownload()

        assertFailed(store)
        XCTAssertThrowsError(try store.installedFiles())
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.installDirectory.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path), [])

        await fixture.downloader.setBehavior(.valid)
        store.download()
        await store.waitForPendingDownload()
        XCTAssertEqual(store.state, .installed)
    }

    func testUnexpectedSizeIsRejected() async throws {
        let fixture = try ModelStoreFixture(behavior: .truncateModel)
        defer { fixture.removeFiles() }
        let store = fixture.store()
        store.download()
        await store.waitForPendingDownload()

        assertFailed(store)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.installDirectory.path))
    }

    func testSecondFileFailureDoesNotPublishPartialInstallation() async throws {
        let fixture = try ModelStoreFixture(behavior: .failTokens)
        defer { fixture.removeFiles() }
        let store = fixture.store()
        store.download()
        await store.waitForPendingDownload()

        assertFailed(store)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.installDirectory.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path), [])
        XCTAssertThrowsError(try store.beginUse())
        XCTAssertEqual(store.activeTranscriptions, 0)
    }

    func testCancellationCleansUpAndDoesNotInstall() async throws {
        let started = expectation(description: "The download has started")
        let fixture = try ModelStoreFixture(behavior: .waitForCancellation, started: started)
        defer { fixture.removeFiles() }
        let store = fixture.store()
        store.download()
        await fulfillment(of: [started], timeout: 2)
        store.cancelDownload()
        XCTAssertEqual(store.state, .notDownloaded)
        await store.waitForPendingDownload()

        XCTAssertEqual(store.state, .notDownloaded)
        XCTAssertThrowsError(try store.installedFiles())
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.installDirectory.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path), [])

        await fixture.downloader.setBehavior(.valid)
        store.download()
        await store.waitForPendingDownload()
        XCTAssertEqual(store.state, .installed)
    }

    func testMissingInstalledFileInvalidatesInstallation() async throws {
        let fixture = try ModelStoreFixture()
        defer { fixture.removeFiles() }
        let store = fixture.store()
        store.download()
        await store.waitForPendingDownload()
        let files = try store.installedFiles()
        try FileManager.default.removeItem(at: files.tokensURL)

        XCTAssertThrowsError(try store.installedFiles())
        assertFailed(store)
        assertFailed(fixture.store())
    }

    func testDamagedInstallationCannotBeReplacedWhileModelIsInUse() async throws {
        let fixture = try ModelStoreFixture()
        defer { fixture.removeFiles() }
        let store = fixture.store()
        store.download()
        await store.waitForPendingDownload()
        let files = try store.beginUse()
        try FileManager.default.removeItem(at: files.tokensURL)
        XCTAssertThrowsError(try store.installedFiles())

        store.download()
        await store.waitForPendingDownload()
        assertFailed(store)
        XCTAssertEqual(store.activeTranscriptions, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: files.tokensURL.path))

        store.endUse()
        store.download()
        await store.waitForPendingDownload()
        XCTAssertEqual(store.state, .installed)
    }

    func testConcurrentModelDownloadsKeepSeparateInstallations() async throws {
        let int8 = try ModelStoreFixture(model: .senseVoiceSmall)
        defer { int8.removeFiles() }
        let fp32 = try ModelStoreFixture(model: .senseVoiceSmallFP32, rootDirectory: int8.root)
        let int8Store = int8.store()
        let fp32Store = fp32.store()

        int8Store.download()
        fp32Store.download()
        await int8Store.waitForPendingDownload()
        await fp32Store.waitForPendingDownload()

        XCTAssertEqual(int8Store.state, .installed)
        XCTAssertEqual(fp32Store.state, .installed)
        let int8Files = try int8Store.installedFiles()
        let fp32Files = try fp32Store.installedFiles()
        XCTAssertNotEqual(int8Files.modelURL, fp32Files.modelURL)
        XCTAssertNotEqual(int8Files.tokensURL, fp32Files.tokensURL)
        XCTAssertEqual(try Data(contentsOf: int8Files.modelURL), int8.modelData)
        XCTAssertEqual(try Data(contentsOf: fp32Files.modelURL), fp32.modelData)
        XCTAssertEqual(int8.store().state, .installed)
        XCTAssertEqual(fp32.store().state, .installed)
    }

    func testCancellationAndFailedRetryDoNotAffectOtherModel() async throws {
        let started = expectation(description: "INT8 download has started")
        let int8 = try ModelStoreFixture(behavior: .waitForCancellation, started: started, model: .senseVoiceSmall)
        defer { int8.removeFiles() }
        let fp32 = try ModelStoreFixture(model: .senseVoiceSmallFP32, rootDirectory: int8.root)
        let int8Store = int8.store()
        let fp32Store = fp32.store()
        int8Store.download()
        await fulfillment(of: [started], timeout: 2)
        fp32Store.download()
        await fp32Store.waitForPendingDownload()
        XCTAssertEqual(fp32Store.state, .installed)
        guard case .downloading = int8Store.state else {
            return XCTFail("Installing FP32 must leave the INT8 download running")
        }

        int8Store.cancelDownload()
        await int8Store.waitForPendingDownload()
        XCTAssertEqual(int8Store.state, .notDownloaded)
        let fp32Files = try fp32Store.installedFiles()
        XCTAssertEqual(try Data(contentsOf: fp32Files.modelURL), fp32.modelData)

        await int8.downloader.setBehavior(.corruptModel)
        int8Store.download()
        await int8Store.waitForPendingDownload()
        assertFailed(int8Store)
        XCTAssertFalse(FileManager.default.fileExists(atPath: int8.installDirectory.path))
        XCTAssertEqual(fp32Store.state, .installed)
        XCTAssertEqual(try Data(contentsOf: fp32Files.modelURL), fp32.modelData)
        XCTAssertEqual(try Data(contentsOf: fp32Files.tokensURL), fp32.tokensData)

        await int8.downloader.setBehavior(.valid)
        int8Store.download()
        await int8Store.waitForPendingDownload()
        XCTAssertEqual(int8Store.state, .installed)
        XCTAssertEqual(fp32Store.state, .installed)
    }

    func testModelLeasesOnlyBlockTheirOwnRemoval() async throws {
        let int8 = try ModelStoreFixture(model: .senseVoiceSmall)
        defer { int8.removeFiles() }
        let fp32 = try ModelStoreFixture(model: .senseVoiceSmallFP32, rootDirectory: int8.root)
        let int8Store = int8.store()
        let fp32Store = fp32.store()
        int8Store.download()
        fp32Store.download()
        await int8Store.waitForPendingDownload()
        await fp32Store.waitForPendingDownload()

        let int8Files = try int8Store.beginUse()
        XCTAssertEqual(int8Store.activeTranscriptions, 1)
        XCTAssertEqual(fp32Store.activeTranscriptions, 0)
        XCTAssertThrowsError(try int8Store.remove())
        try fp32Store.remove()
        XCTAssertEqual(fp32Store.state, .notDownloaded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fp32.installDirectory.path))
        XCTAssertEqual(int8Store.state, .installed)
        XCTAssertEqual(try Data(contentsOf: int8Files.modelURL), int8.modelData)

        fp32Store.download()
        await fp32Store.waitForPendingDownload()
        let fp32Files = try fp32Store.beginUse()
        XCTAssertEqual(int8Store.activeTranscriptions, 1)
        XCTAssertEqual(fp32Store.activeTranscriptions, 1)
        int8Store.endUse()
        try int8Store.remove()
        XCTAssertEqual(int8Store.state, .notDownloaded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: int8.installDirectory.path))
        XCTAssertEqual(fp32Store.activeTranscriptions, 1)
        XCTAssertThrowsError(try fp32Store.remove())
        XCTAssertEqual(fp32Store.state, .installed)
        XCTAssertEqual(try Data(contentsOf: fp32Files.modelURL), fp32.modelData)
        fp32Store.endUse()
        try fp32Store.remove()
        XCTAssertEqual(fp32Store.state, .notDownloaded)
    }

    func testOrphanCleanupKeepsCurrentProcessAndUnrecognizedDirectories() throws {
        let fixture = try ModelStoreFixture()
        defer { fixture.removeFiles() }
        let manager = FileManager.default
        try manager.createDirectory(at: fixture.root, withIntermediateDirectories: true)
        let active = try ModelInstallation.createStagingDirectory(root: fixture.root)
        let legacyOrphan = fixture.root.appendingPathComponent(".staging-" + UUID().uuidString)
        let ownedOrphan = fixture.root.appendingPathComponent(".staging-" + UUID().uuidString + "-" + UUID().uuidString)
        let unknown = fixture.root.appendingPathComponent(".staging-user-files")
        for directory in [legacyOrphan, ownedOrphan, unknown, fixture.installDirectory] {
            try manager.createDirectory(at: directory, withIntermediateDirectories: false)
            try fixture.modelData.write(to: directory.appendingPathComponent("fixture.bin"))
        }
        let activeFile = active.appendingPathComponent("in-progress.bin")
        try fixture.modelData.write(to: activeFile)
        let symlink = fixture.root.appendingPathComponent(".staging-" + UUID().uuidString)
        try manager.createSymbolicLink(at: symlink, withDestinationURL: unknown)

        try ModelInstallation.removeAbandonedStagingDirectories(root: fixture.root)

        XCTAssertFalse(manager.fileExists(atPath: legacyOrphan.path))
        XCTAssertFalse(manager.fileExists(atPath: ownedOrphan.path))
        XCTAssertEqual(try Data(contentsOf: activeFile), fixture.modelData)
        XCTAssertTrue(manager.fileExists(atPath: unknown.path))
        XCTAssertTrue(manager.fileExists(atPath: fixture.installDirectory.path))
        XCTAssertEqual(try symlink.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink, true)
    }

    func testNewDownloadRemovesAbandonedStagingBeforeInstalling() async throws {
        let fixture = try ModelStoreFixture()
        defer { fixture.removeFiles() }
        let orphan = fixture.root.appendingPathComponent(".staging-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
        try fixture.modelData.write(to: orphan.appendingPathComponent("model.int8.onnx"))
        let store = fixture.store()
        store.download()
        await store.waitForPendingDownload()

        XCTAssertEqual(store.state, .installed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path), [fixture.manifest.directoryName])
    }

    private func assertFailed(_ store: TranscriptionModelStore, file: StaticString = #filePath, line: UInt = #line) {
        guard case .failed(let message) = store.state else {
            XCTFail("Expected a failed installation", file: file, line: line)
            return
        }
        XCTAssertFalse(message.isEmpty, file: file, line: line)
    }
}

private struct ModelStoreFixture {
    let root: URL
    let manifest: LocalModelManifest
    let modelData: Data
    let tokensData = Data("test-only-token 0\n".utf8)
    let downloader: FixtureModelDownloader

    var installDirectory: URL { root.appendingPathComponent(manifest.directoryName) }

    init(
        behavior: FixtureModelDownloader.Behavior = .valid,
        started: XCTestExpectation? = nil,
        model: LocalTranscriptionModel = .senseVoiceSmall,
        rootDirectory: URL? = nil
    ) throws {
        root = rootDirectory ?? FileManager.default.temporaryDirectory.appendingPathComponent("ALog-model-test-" + UUID().uuidString)
        modelData = Data("test-only-onnx-bytes-\(model.rawValue)".utf8)
        guard let origin = URL(string: "https://model-test.invalid/") else {
            throw URLError(.badURL)
        }
        func artifact(_ name: String, _ data: Data) -> ModelArtifact {
            ModelArtifact(filename: name, remoteURL: origin.appendingPathComponent(name), byteCount: Int64(data.count),
                          sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
        }
        manifest = LocalModelManifest(directoryName: model.manifest.directoryName, revision: "test-revision",
                                      model: artifact(model.manifest.model.filename, modelData),
                                      tokens: artifact("tokens.txt", tokensData))
        downloader = FixtureModelDownloader(model: modelData, tokens: tokensData, behavior: behavior, started: started)
    }

    @MainActor func store() -> TranscriptionModelStore {
        TranscriptionModelStore(rootDirectory: root, manifest: manifest, downloader: downloader)
    }

    func removeFiles() {
        try? FileManager.default.removeItem(at: root)
    }
}

private actor FixtureModelDownloader: ModelArtifactDownloading {
    enum Behavior {
        case valid, corruptModel, truncateModel, failTokens, waitForCancellation
    }

    private let model: Data
    private let tokens: Data
    private var behavior: Behavior
    private let started: XCTestExpectation?

    init(model: Data, tokens: Data, behavior: Behavior, started: XCTestExpectation?) {
        self.model = model
        self.tokens = tokens
        self.behavior = behavior
        self.started = started
    }

    func setBehavior(_ behavior: Behavior) { self.behavior = behavior }

    func download(_ artifact: ModelArtifact, from sourceURL: URL, to destination: URL,
                  progress: @escaping @Sendable (ModelDownloadProgress) -> Void) async throws {
        if behavior == .waitForCancellation {
            started?.fulfill()
            try await Task.sleep(for: .seconds(60))
        }
        let isModel = artifact.filename != "tokens.txt"
        if behavior == .failTokens && !isModel {
            throw URLError(.networkConnectionLost)
        }
        var bytes = isModel ? model : tokens
        if isModel && behavior == .corruptModel {
            bytes[0] ^= 0xff
        } else if isModel && behavior == .truncateModel {
            bytes.removeLast()
        }
        try bytes.write(to: destination)
        progress(ModelDownloadProgress(phase: .downloading, receivedBytes: Int64(bytes.count),
                                       totalBytes: artifact.byteCount, bytesPerSecond: 1,
                                       sourceHost: sourceURL.host ?? ""))
    }
}
