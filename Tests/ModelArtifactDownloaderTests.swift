import Combine
import CryptoKit
import Foundation
import XCTest
@testable import ALog

@MainActor
final class ModelArtifactDownloaderTests: XCTestCase {
    func testSessionDelegatePublishesBytesToStoreBeforeCompletion() async throws {
        let fixture = try NetworkModelFixture()
        defer { fixture.removeFiles() }
        ModelDownloadTestProtocol.register(fixture.model.remoteURL, data: fixture.modelData)
        ModelDownloadTestProtocol.register(fixture.tokens.remoteURL, data: fixture.tokensData)
        let store = fixture.store()
        let firstBytes = expectation(description: "URLSession delegate reaches the observed store before completion")
        var observed: [ModelDownloadProgress] = []
        var receivedFirstBytes = false
        let observation = store.$downloadProgress.compactMap { $0 }.sink { update in
            observed.append(update)
            if !receivedFirstBytes && update.phase == .downloading && update.receivedBytes > 0 {
                receivedFirstBytes = true
                firstBytes.fulfill()
            }
        }
        defer { observation.cancel() }

        store.download()
        await fulfillment(of: [firstBytes], timeout: 3)
        guard let first = observed.first(where: { $0.phase == .downloading && $0.receivedBytes > 0 }) else {
            return XCTFail("No intermediate delegate progress was published")
        }
        XCTAssertLessThan(first.receivedBytes, first.totalBytes / 200, "Even the first <0.5% must reach the UI")
        XCTAssertGreaterThan(first.bytesPerSecond, 0)
        XCTAssertEqual(first.sourceHost, fixture.model.remoteURL.host)
        await store.waitForPendingDownload()

        XCTAssertEqual(store.state, .installed)
        XCTAssertNil(store.downloadProgress)
        XCTAssertTrue(observed.contains(where: { $0.phase == .verifying }))
        XCTAssertEqual(try Data(contentsOf: store.installedFiles().modelURL), fixture.modelData)
    }

    func testHTTPFailureFallsBackAndInstallsVerifiedFiles() async throws {
        let fixture = try NetworkModelFixture(hasFallback: true)
        defer { fixture.removeFiles() }
        ModelDownloadTestProtocol.register(fixture.model.remoteURL, data: Data(), status: 503)
        ModelDownloadTestProtocol.register(fixture.fallbackURL, data: fixture.modelData)
        ModelDownloadTestProtocol.register(fixture.tokens.remoteURL, data: fixture.tokensData)
        let store = fixture.store()
        store.download()
        await store.waitForPendingDownload()

        XCTAssertEqual(store.state, .installed)
        XCTAssertEqual(ModelDownloadTestProtocol.requestCount(fixture.model.remoteURL), 1)
        XCTAssertEqual(ModelDownloadTestProtocol.requestCount(fixture.fallbackURL), 1)
        XCTAssertEqual(try Data(contentsOf: store.installedFiles().modelURL), fixture.modelData)
    }

    func testStalledTransferTimesOutAndFallbackResetsProgress() async throws {
        let fixture = try NetworkModelFixture(hasFallback: true)
        defer { fixture.removeFiles() }
        ModelDownloadTestProtocol.register(fixture.model.remoteURL, data: fixture.modelData, stallAfterBytes: 4096)
        ModelDownloadTestProtocol.register(fixture.fallbackURL, data: fixture.modelData)
        ModelDownloadTestProtocol.register(fixture.tokens.remoteURL, data: fixture.tokensData)
        let store = fixture.store(timeout: 0.3)
        var observed: [ModelDownloadProgress] = []
        let observation = store.$downloadProgress.compactMap { $0 }.sink { observed.append($0) }
        defer { observation.cancel() }
        store.download()
        await store.waitForPendingDownload()

        XCTAssertEqual(store.state, .installed)
        XCTAssertTrue(observed.contains(where: {
            $0.sourceHost == fixture.model.remoteURL.host && $0.receivedBytes > 0
        }))
        XCTAssertTrue(observed.contains(where: {
            $0.sourceHost == fixture.fallbackURL.host && $0.phase == .connecting
                && $0.receivedBytes == 0 && $0.bytesPerSecond == 0
        }))
        XCTAssertEqual(ModelDownloadTestProtocol.requestCount(fixture.fallbackURL), 1)
    }

    func testCancelStopsTransferWithoutFallbackAndClearsStaging() async throws {
        let fixture = try NetworkModelFixture(hasFallback: true)
        defer { fixture.removeFiles() }
        ModelDownloadTestProtocol.register(fixture.model.remoteURL, data: fixture.modelData, stallAfterBytes: 4096)
        ModelDownloadTestProtocol.register(fixture.fallbackURL, data: fixture.modelData)
        let store = fixture.store(timeout: 5)
        let idle = expectation(description: "A stalled transfer stops displaying a stale positive speed")
        var sawBytes = false
        var sawIdle = false
        let observation = store.$downloadProgress.compactMap { $0 }.sink { update in
            if update.phase == .downloading && update.receivedBytes > 0 {
                sawBytes = true
                if update.bytesPerSecond == 0 && !sawIdle {
                    sawIdle = true
                    idle.fulfill()
                }
            }
        }
        defer { observation.cancel() }
        store.download()
        await fulfillment(of: [idle], timeout: 3)
        XCTAssertTrue(sawBytes)
        store.cancelDownload()
        await store.waitForPendingDownload()

        XCTAssertEqual(store.state, .notDownloaded)
        XCTAssertNil(store.downloadProgress)
        XCTAssertEqual(ModelDownloadTestProtocol.requestCount(fixture.fallbackURL), 0)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path), [])
    }

    func testNoResponseTimesOutWithoutPublishingInstallation() async throws {
        let fixture = try NetworkModelFixture()
        defer { fixture.removeFiles() }
        ModelDownloadTestProtocol.register(fixture.model.remoteURL, data: fixture.modelData, stallAfterBytes: 0)
        let store = fixture.store(timeout: 0.2)
        store.download()
        await store.waitForPendingDownload()

        guard case .failed = store.state else { return XCTFail("Expected the no-data request to time out") }
        XCTAssertNil(store.downloadProgress)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path), [])
    }

    func testActualDownloadMustPassChecksumBeforeInstallation() async throws {
        let fixture = try NetworkModelFixture()
        defer { fixture.removeFiles() }
        var corrupted = fixture.modelData
        corrupted[0] ^= 0xff
        ModelDownloadTestProtocol.register(fixture.model.remoteURL, data: corrupted)
        let store = fixture.store()
        store.download()
        await store.waitForPendingDownload()

        guard case .failed = store.state else { return XCTFail("Downloaded bytes with a wrong hash must fail") }
        XCTAssertNil(store.downloadProgress)
        XCTAssertThrowsError(try store.installedFiles())
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path), [])
    }

    func testFilesystemFailureDoesNotRetryAnotherSource() async throws {
        let fixture = try NetworkModelFixture(hasFallback: true)
        defer { fixture.removeFiles() }
        let downloader = FilesystemFailureDownloader()
        let store = TranscriptionModelStore(
            rootDirectory: fixture.root,
            manifest: LocalModelManifest(directoryName: "fixture", revision: "test", model: fixture.model, tokens: fixture.tokens),
            downloader: downloader
        )
        store.download()
        await store.waitForPendingDownload()

        guard case .failed = store.state else { return XCTFail("Expected the disk error to fail installation") }
        let attempts = await downloader.attempts
        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path), [])
    }
}

private actor FilesystemFailureDownloader: ModelArtifactDownloading {
    private(set) var attempts = 0

    func download(_ artifact: ModelArtifact, from sourceURL: URL, to destination: URL,
                  progress: @escaping @Sendable (ModelDownloadProgress) -> Void) async throws {
        attempts += 1
        throw CocoaError(.fileWriteOutOfSpace)
    }
}

private struct NetworkModelFixture {
    let root: URL
    let model: ModelArtifact
    let tokens: ModelArtifact
    let fallbackURL: URL
    let modelData = Data(repeating: 0x41, count: 1_048_576)
    let tokensData = Data("test-token 0\n".utf8)

    init(hasFallback: Bool = false) throws {
        let id = UUID().uuidString.lowercased()
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ALog-network-model-test-" + id)
        let primaryURL = try XCTUnwrap(URL(string: "https://primary-\(id).model-download-test.invalid/model.onnx"))
        fallbackURL = try XCTUnwrap(URL(string: "https://fallback-\(id).model-download-test.invalid/model.onnx"))
        let tokensURL = try XCTUnwrap(URL(string: "https://tokens-\(id).model-download-test.invalid/tokens.txt"))
        func checksum(_ data: Data) -> String {
            SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
        model = ModelArtifact(filename: "model.onnx", remoteURL: primaryURL, byteCount: Int64(modelData.count),
                              sha256: checksum(modelData), fallbackURLs: hasFallback ? [fallbackURL] : [])
        tokens = ModelArtifact(filename: "tokens.txt", remoteURL: tokensURL, byteCount: Int64(tokensData.count),
                               sha256: checksum(tokensData))
    }

    @MainActor func store(timeout: TimeInterval = 5) -> TranscriptionModelStore {
        let downloader = ModelArtifactDownloader(inactivityTimeout: timeout) {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [ModelDownloadTestProtocol.self]
            return configuration
        }
        return TranscriptionModelStore(
            rootDirectory: root,
            manifest: LocalModelManifest(directoryName: "fixture", revision: "test", model: model, tokens: tokens),
            downloader: downloader
        )
    }

    func removeFiles() {
        ModelDownloadTestProtocol.remove([model.remoteURL, fallbackURL, tokens.remoteURL])
        try? FileManager.default.removeItem(at: root)
    }
}

// The bytes are controlled, but URLSession and URLSessionDownloadDelegate are
// real. Replacing the production downloadTask with download(from:) makes the
// intermediate-progress test fail, reproducing the original regression.
private final class ModelDownloadTestProtocol: URLProtocol, @unchecked Sendable {
    private struct Response: Sendable {
        let data: Data
        let status: Int
        let stallAfterBytes: Int?
    }

    private final class Registry: @unchecked Sendable {
        let lock = NSLock()
        var responses: [URL: Response] = [:]
        var requests: [URL: Int] = [:]
    }

    private static let registry = Registry()
    private let workerLock = NSLock()
    private var worker: Task<Void, Never>?

    static func register(_ url: URL, data: Data, status: Int = 200, stallAfterBytes: Int? = nil) {
        registry.lock.lock()
        defer { registry.lock.unlock() }
        registry.responses[url] = Response(data: data, status: status, stallAfterBytes: stallAfterBytes)
    }

    static func requestCount(_ url: URL) -> Int {
        registry.lock.lock()
        defer { registry.lock.unlock() }
        return registry.requests[url, default: 0]
    }

    static func remove(_ urls: [URL]) {
        registry.lock.lock()
        defer { registry.lock.unlock() }
        for url in urls {
            registry.responses[url] = nil
            registry.requests[url] = nil
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host?.hasSuffix(".model-download-test.invalid") == true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        Self.registry.lock.lock()
        let response = Self.registry.responses[url]
        Self.registry.requests[url, default: 0] += 1
        Self.registry.lock.unlock()
        guard let response else {
            client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist))
            return
        }
        workerLock.lock()
        worker = Task { [self] in
            guard let headers = HTTPURLResponse(url: url, statusCode: response.status, httpVersion: "HTTP/1.1",
                                                headerFields: ["Content-Length": String(response.data.count)]) else { return }
            if response.stallAfterBytes == 0 { return }
            client?.urlProtocol(self, didReceive: headers, cacheStoragePolicy: .notAllowed)
            var offset = 0
            let end = min(response.stallAfterBytes ?? response.data.count, response.data.count)
            while offset < end {
                if Task.isCancelled { return }
                let next = min(offset + 4096, end)
                client?.urlProtocol(self, didLoad: response.data.subdata(in: offset..<next))
                offset = next
                do { try await Task.sleep(for: .milliseconds(5)) } catch { return }
            }
            if response.stallAfterBytes == nil && !Task.isCancelled {
                client?.urlProtocolDidFinishLoading(self)
            }
        }
        workerLock.unlock()
    }

    override func stopLoading() {
        workerLock.lock()
        worker?.cancel()
        worker = nil
        workerLock.unlock()
    }
}
