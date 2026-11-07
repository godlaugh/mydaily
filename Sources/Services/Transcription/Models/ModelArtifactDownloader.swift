import Foundation

protocol ModelArtifactDownloading: Sendable {
    func download(
        _ artifact: ModelArtifact,
        from sourceURL: URL,
        to destination: URL,
        progress: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws
}

struct ModelArtifactDownloader: ModelArtifactDownloading {
    var inactivityTimeout: TimeInterval = 20
    var makeConfiguration: @Sendable () -> URLSessionConfiguration = { .ephemeral }

    func download(
        _ artifact: ModelArtifact,
        from sourceURL: URL,
        to destination: URL,
        progress: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws {
        guard sourceURL.scheme == "https" else {
            throw ModelInstallError.invalidResponse
        }
        try Task.checkCancellation()
        let configuration = makeConfiguration()
        configuration.timeoutIntervalForRequest = inactivityTimeout
        configuration.timeoutIntervalForResource = 60 * 60
        configuration.waitsForConnectivity = false
        let operation = ModelDownloadOperation(
            artifact: artifact, sourceURL: sourceURL, destination: destination,
            configuration: configuration, inactivityTimeout: inactivityTimeout, progress: progress
        )
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                operation.start(continuation)
            }
        } onCancel: {
            operation.cancel()
        }
    }
}

// URLSession owns this session-level delegate until completion. State shared
// with task cancellation and the inactivity timer is protected by the lock.
private final class ModelDownloadOperation: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let artifact: ModelArtifact
    private let sourceURL: URL
    private let destination: URL
    private let configuration: URLSessionConfiguration
    private let inactivityTimeout: TimeInterval
    private let progress: @Sendable (ModelDownloadProgress) -> Void
    private let lock = NSLock()
    private var session: URLSession?
    private var timer: DispatchSourceTimer?
    private var continuation: CheckedContinuation<Void, Error>?
    private var result: Result<Void, Error>?
    private var startedAt: TimeInterval = 0
    private var lastDataAt: TimeInterval = 0
    private var receivedBytes: Int64 = 0
    private var speedSamples: [(time: TimeInterval, bytes: Int64)] = []
    private var sourceHost = ""
    private var reportedIdleSpeed = false

    init(artifact: ModelArtifact, sourceURL: URL, destination: URL,
         configuration: URLSessionConfiguration, inactivityTimeout: TimeInterval,
         progress: @escaping @Sendable (ModelDownloadProgress) -> Void) {
        self.artifact = artifact
        self.sourceURL = sourceURL
        self.destination = destination
        self.configuration = configuration
        self.inactivityTimeout = inactivityTimeout
        self.progress = progress
    }

    func start(_ continuation: CheckedContinuation<Void, Error>) {
        lock.lock()
        if let result {
            lock.unlock()
            continuation.resume(with: result)
            return
        }
        self.continuation = continuation
        startedAt = ProcessInfo.processInfo.systemUptime
        lastDataAt = startedAt
        speedSamples = [(startedAt, 0)]
        sourceHost = sourceURL.host ?? ""
        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: delegateQueue)
        self.session = session
        let task = session.downloadTask(with: sourceURL)
        let timer = DispatchSource.makeTimerSource()
        timer.schedule(deadline: .now() + min(1, inactivityTimeout), repeating: min(0.5, inactivityTimeout / 4))
        timer.setEventHandler { [weak self] in self?.checkForInactivity() }
        self.timer = timer
        timer.resume()
        lock.unlock()
        progress(ModelDownloadProgress(phase: .connecting, receivedBytes: 0, totalBytes: artifact.byteCount,
                                       bytesPerSecond: 0, sourceHost: sourceURL.host ?? ""))
        task.resume()
    }

    func cancel() {
        finish(.failure(CancellationError()))
    }

    private func checkForInactivity() {
        finish(.failure(URLError(.timedOut)), onlyIfInactive: true)
        lock.lock()
        guard result == nil, receivedBytes > 0, !reportedIdleSpeed,
              ProcessInfo.processInfo.systemUptime - lastDataAt >= 1 else {
            lock.unlock()
            return
        }
        reportedIdleSpeed = true
        let update = ModelDownloadProgress(phase: .downloading, receivedBytes: receivedBytes,
                                           totalBytes: artifact.byteCount, bytesPerSecond: 0, sourceHost: sourceHost)
        lock.unlock()
        progress(update)
    }

    private func finish(_ result: Result<Void, Error>, onlyIfInactive: Bool = false) {
        lock.lock()
        guard self.result == nil,
              !onlyIfInactive || ProcessInfo.processInfo.systemUptime - lastDataAt >= inactivityTimeout else {
            lock.unlock()
            return
        }
        self.result = result
        let continuation = self.continuation
        self.continuation = nil
        let session = self.session
        self.session = nil
        let timer = self.timer
        self.timer = nil
        lock.unlock()
        timer?.cancel()
        session?.invalidateAndCancel()
        continuation?.resume(with: result)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard request.url?.scheme == "https" else {
            completionHandler(nil)
            finish(.failure(ModelInstallError.invalidResponse))
            return
        }
        progress(ModelDownloadProgress(phase: .connecting, receivedBytes: 0, totalBytes: artifact.byteCount,
                                       bytesPerSecond: 0, sourceHost: request.url?.host ?? ""))
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard let response = downloadTask.response as? HTTPURLResponse, response.statusCode == 200 else {
            finish(.failure(ModelInstallError.invalidResponse))
            return
        }
        guard totalBytesWritten <= artifact.byteCount else {
            finish(.failure(ModelInstallError.invalidSize(artifact.filename)))
            return
        }
        lock.lock()
        guard result == nil else { lock.unlock(); return }
        let now = ProcessInfo.processInfo.systemUptime
        if totalBytesWritten > receivedBytes { lastDataAt = now }
        receivedBytes = totalBytesWritten
        sourceHost = response.url?.host ?? sourceURL.host ?? ""
        reportedIdleSpeed = false
        speedSamples.append((now, totalBytesWritten))
        while speedSamples.count > 2 && speedSamples[1].time < now - 2 {
            speedSamples.removeFirst()
        }
        let baseline = speedSamples[0]
        let speed = Double(totalBytesWritten - baseline.bytes) / max(now - baseline.time, 0.001)
        lock.unlock()
        progress(ModelDownloadProgress(phase: .downloading, receivedBytes: totalBytesWritten,
                                       totalBytes: artifact.byteCount, bytesPerSecond: speed,
                                       sourceHost: response.url?.host ?? sourceURL.host ?? ""))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        lock.lock()
        guard result == nil else { lock.unlock(); return }
        let completion: Result<Void, Error>
        do {
            guard let response = downloadTask.response as? HTTPURLResponse,
                  response.statusCode == 200, response.url?.scheme == "https" else {
                throw ModelInstallError.invalidResponse
            }
            // URLSession removes this temporary file after the callback returns.
            try FileManager.default.moveItem(at: location, to: destination)
            completion = .success(())
        } catch {
            completion = .failure(error)
        }
        lock.unlock()
        finish(completion)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
    }
}
