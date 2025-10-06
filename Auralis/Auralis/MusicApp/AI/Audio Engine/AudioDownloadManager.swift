import Foundation
import UIKit

public extension Notification.Name {
    static let audioDownloadProgress = Notification.Name("AudioDownloadManager.audioDownloadProgress")
    static let audioDownloadCompleted = Notification.Name("AudioDownloadManager.audioDownloadCompleted")
    static let audioDownloadFailed = Notification.Name("AudioDownloadManager.audioDownloadFailed")
}

public class AudioDownloadManager: NSObject, URLSessionDownloadDelegate {
    public enum AudioDownloadError: LocalizedError {
        case cancelled
        case timeout
        case httpStatus(Int)

        public var errorDescription: String? {
            switch self {
            case .cancelled: return "Download was cancelled."
            case .timeout: return "The download timed out."
            case .httpStatus(let code): return "Server returned status code \(code)."
            }
        }
    }

    public enum NetworkPolicy {
        case userInitiated
        case background
    }

    public static let shared = AudioDownloadManager()

    // Default network policy for new downloads
    public var defaultPolicy: NetworkPolicy = .background

    // Dedicated delegate queue to avoid running delegate callbacks on the state queue
    private let delegateQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.auralis.audioDownloadManager.delegateQueue"
        q.qualityOfService = .utility
        // Keep serialization of delegate callbacks predictable
        q.maxConcurrentOperationCount = 1
        return q
    }()

    // Serial queue for synchronizing access to shared state (not used as delegate queue)
    private let stateQueue = DispatchQueue(label: "com.auralis.audioDownloadManager.stateQueue")
    private let stateQueueSpecificKey = DispatchSpecificKey<Bool>()

    #if DEBUG
    // Debug telemetry: count occurrences where a synchronous state access was requested from stateQueue context
    private var debugReentrySyncCalls: Int = 0
    #endif

    // MARK: - State access helpers
    // Rule: If already on stateQueue, access state directly; otherwise marshal to stateQueue.
    private func onStateQueue() -> Bool {
        return DispatchQueue.getSpecific(key: stateQueueSpecificKey) == true
    }

    @discardableResult
    private func withState<T>(_ block: () -> T) -> T {
        if onStateQueue() {
            #if DEBUG
            debugReentrySyncCalls += 1
            #endif
            return block()
        } else {
            return stateQueue.sync(execute: block)
        }
    }

    private func withStateAsync(_ block: @escaping () -> Void) {
        if onStateQueue() {
            block()
        } else {
            stateQueue.async(execute: block)
        }
    }

    // MARK: - Progress Throttling
    private let minProgressInterval: TimeInterval = 0.2 // 200 ms
    private let minProgressFractionDelta: Double = 0.01  // 1% for determinate
    private let minProgressByteDelta: Int64 = 64 * 1024  // 64 KB for indeterminate

    private final class ProgressCoalescer {
        var lastPostedTime: TimeInterval = 0
        var lastPostedBytes: Int64 = 0
        var pendingBytes: Int64? = nil
        var pendingTotal: Int64? = nil
        var scheduledWorkItem: DispatchWorkItem? = nil
    }

    // Maps taskIdentifier -> progress coalescer
    private var taskIdToProgress: [Int: ProgressCoalescer] = [:]

    private func postProgressNow(taskId: Int, url: URL, bytesWritten: Int64, totalBytesExpected: Int64) {
        // Build userInfo; omit fractionCompleted if indeterminate
        var userInfo: [String: Any] = [
            "taskIdentifier": taskId,
            "url": url,
            "bytesReceived": bytesWritten,
            "totalBytes": totalBytesExpected
        ]
        if totalBytesExpected > 0 {
            let fractionCompleted = max(0, min(1, Double(bytesWritten) / Double(totalBytesExpected)))
            userInfo["fractionCompleted"] = fractionCompleted
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .audioDownloadProgress, object: nil, userInfo: userInfo)
        }
    }

    private func handleProgressCoalescing(for downloadTask: URLSessionDownloadTask, url: URL, totalBytesWritten: Int64, totalBytesExpected: Int64) {
        let taskId = downloadTask.taskIdentifier
        let now = Date().timeIntervalSinceReferenceDate

        let coalescer = taskIdToProgress[taskId] ?? {
            let c = ProgressCoalescer()
            taskIdToProgress[taskId] = c
            return c
        }()

        let elapsed = now - coalescer.lastPostedTime
        let deltaBytes = totalBytesWritten - coalescer.lastPostedBytes

        var shouldPostNow = false
        if totalBytesExpected > 0 {
            let fractionDelta = totalBytesExpected > 0 ? Double(deltaBytes) / Double(totalBytesExpected) : 0
            if totalBytesWritten == totalBytesExpected { // final progress
                shouldPostNow = true
            } else if elapsed >= minProgressInterval || fractionDelta >= minProgressFractionDelta {
                shouldPostNow = true
            }
        } else {
            if elapsed >= minProgressInterval || deltaBytes >= minProgressByteDelta {
                shouldPostNow = true
            }
        }

        if shouldPostNow {
            coalescer.scheduledWorkItem?.cancel()
            coalescer.scheduledWorkItem = nil
            coalescer.lastPostedTime = now
            coalescer.lastPostedBytes = totalBytesWritten
            postProgressNow(taskId: taskId, url: url, bytesWritten: totalBytesWritten, totalBytesExpected: totalBytesExpected)
        } else {
            // Store the freshest sample and schedule a post if none pending
            coalescer.pendingBytes = totalBytesWritten
            coalescer.pendingTotal = totalBytesExpected
            if coalescer.scheduledWorkItem == nil {
                let delay = max(0, minProgressInterval - elapsed)
                let work = DispatchWorkItem { [weak self] in
                    guard let self = self else { return }
                    self.withState {
                        guard let latestBytes = coalescer.pendingBytes, let latestTotal = coalescer.pendingTotal else { return }
                        coalescer.pendingBytes = nil
                        coalescer.pendingTotal = nil
                        coalescer.scheduledWorkItem = nil
                        coalescer.lastPostedTime = Date().timeIntervalSinceReferenceDate
                        coalescer.lastPostedBytes = latestBytes
                        self.postProgressNow(taskId: taskId, url: url, bytesWritten: latestBytes, totalBytesExpected: latestTotal)
                    }
                }
                coalescer.scheduledWorkItem = work
                stateQueue.asyncAfter(deadline: .now() + delay, execute: work)
            }
        }
    }

    private func flushFinalProgressIfNeeded(for downloadTask: URLSessionTask, url: URL) {
        let taskId = downloadTask.taskIdentifier
        let bytes = downloadTask.countOfBytesReceived
        let expected = downloadTask.countOfBytesExpectedToReceive
        if let coalescer = taskIdToProgress[taskId] {
            coalescer.scheduledWorkItem?.cancel()
            coalescer.scheduledWorkItem = nil
            coalescer.lastPostedTime = Date().timeIntervalSinceReferenceDate
            coalescer.lastPostedBytes = bytes
        }
        postProgressNow(taskId: taskId, url: url, bytesWritten: bytes, totalBytesExpected: expected)
        taskIdToProgress[taskId] = nil
    }

    #if DEBUG
    private func debugLogDelegate(_ function: String) {
        let label = String(cString: __dispatch_queue_get_label(nil))
        print("[AudioDownloadManager] Delegate callback: \(function) on queue: \(label)")
    }

    // MARK: - Telemetry Counters
    private var debugSuccessCount: Int = 0
    private var debugFailureCount: Int = 0
    private var debugFailureStatusCounts: [Int: Int] = [:]
    private var debugFailureHosts: [String: Int] = [:]
    private var debugDiscoveredTasksOnInit: Int = 0
    private var debugDuplicateTaskPreventionCount: Int = 0
    private var debugCoalescedListenerCount: Int = 0
    #endif

    // MARK: - Error Types
    private struct HTTPStatusError: LocalizedError {
        let statusCode: Int
        let url: URL
        let response: HTTPURLResponse

        var errorDescription: String? {
            return "Server returned status code \(statusCode) for URL: \(url.absoluteString)"
        }
    }

    // MARK: - Rebinding existing background tasks
    private func rebindInFlightTasks() {
        session.getAllTasks { tasks in
            let downloadTasks = tasks.compactMap { $0 as? URLSessionDownloadTask }
            #if DEBUG
            self.withState {
                self.debugDiscoveredTasksOnInit += downloadTasks.count
            }
            #endif

            for task in downloadTasks {
                guard let originalURL = task.originalRequest?.url ?? task.currentRequest?.url else { continue }
                self.withState {
                    if let existing = self.urlToTask[originalURL], existing.taskIdentifier != task.taskIdentifier {
                        // Duplicate for same URL detected; cancel the extra to enforce single-task policy per URL
                        #if DEBUG
                        self.debugDuplicateTaskPreventionCount += 1
                        #endif
                        // Ensure no residual state for the duplicate task
                        self.taskIdToProgress[task.taskIdentifier]?.scheduledWorkItem?.cancel()
                        self.taskIdToProgress[task.taskIdentifier] = nil
                        self.taskIdentifierToURL[task.taskIdentifier] = nil
                        // Cancel without ever recording this duplicate in our maps
                        task.cancel()
                    } else {
                        self.taskIdentifierToURL[task.taskIdentifier] = originalURL
                        self.urlToTask[originalURL] = task
                        if self.urlToCompletionHandlers[originalURL] == nil {
                            self.urlToCompletionHandlers[originalURL] = []
                        }
                    }
                }
            }
        }
    }

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "com.auralis.audio.background")
        config.waitsForConnectivity = true
        config.isDiscretionary = true
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = true
        // Ticket 3: Explicit timeouts to avoid indefinite hangs
        // Handshake/request timeout (e.g., DNS/TLS/connect) kept short; resource timeout generous for audio assets
        config.timeoutIntervalForRequest = 30 // seconds
        config.timeoutIntervalForResource = 15 * 60 // 15 minutes
        return URLSession(configuration: config, delegate: self, delegateQueue: delegateQueue)
    }()

    // Maps taskIdentifier -> original URL
    private var taskIdentifierToURL: [Int: URL] = [:]

    // Maps URL -> array of completion handlers
    private var urlToCompletionHandlers: [URL: [(Result<(URL, URLResponse), Error>) -> Void]] = [:]

    // Maps URL -> URLSessionDownloadTask
    private var urlToTask: [URL: URLSessionDownloadTask] = [:]

    // Maps background session identifier -> completionHandler to call when all background events are handled
    private var backgroundSessionCompletionHandlers: [String: () -> Void] = [:]

    private override init() {
        super.init()
        // Mark this queue so we can detect re-entry safely
        stateQueue.setSpecific(key: stateQueueSpecificKey, value: true)
        rebindInFlightTasks()
    }

    private func makeRequest(for url: URL, policy: NetworkPolicy) -> URLRequest {
        var request = URLRequest(url: url)
        switch policy {
        case .userInitiated:
            // Proceed over cellular/expensive networks; not constrained by Low Data Mode
            if #available(iOS 13.0, *) {
                request.allowsExpensiveNetworkAccess = true
                request.allowsConstrainedNetworkAccess = true
            }
            request.networkServiceType = .responsiveData
        case .background:
            // Respect Low Data Mode; allow system discretion for prefetching
            if #available(iOS 13.0, *) {
                request.allowsExpensiveNetworkAccess = false
                request.allowsConstrainedNetworkAccess = false
            }
            request.networkServiceType = .background
        }
        return request
    }

    /// Starts a download for the given URL. Returns the URLSessionDownloadTask immediately.
    /// If a download for this URL is already in progress, returns the existing task.
    @discardableResult
    public func startDownload(from url: URL, policy: NetworkPolicy? = nil) -> URLSessionDownloadTask {
        var task: URLSessionDownloadTask!

        withState {
            if let existingTask = urlToTask[url] {
                task = existingTask
                return
            }
            let request = makeRequest(for: url, policy: policy ?? defaultPolicy)
            let newTask = session.downloadTask(with: request)
            taskIdentifierToURL[newTask.taskIdentifier] = url
            urlToTask[url] = newTask
            urlToCompletionHandlers[url] = [] // Initialize empty handlers list
            task = newTask
            newTask.resume()
        }

        return task
    }

    /// Awaits the download completion and returns the temporary file URL and URLResponse.
    /// If a download for the URL is already in progress, the continuation will be appended.
    public func awaitDownload(from url: URL, policy: NetworkPolicy? = nil) async throws -> (URL, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            self.withStateAsync {
                if let _ = self.urlToTask[url] {
                    #if DEBUG
                    self.debugCoalescedListenerCount += 1
                    #endif
                    // Download in progress, append completion handler
                    self.urlToCompletionHandlers[url, default: []].append { result in
                        switch result {
                        case let .success(value):
                            continuation.resume(returning: value)
                        case let .failure(error):
                            continuation.resume(throwing: error)
                        }
                    }
                } else {
                    // No download in progress, start new download
                    let request = self.makeRequest(for: url, policy: policy ?? self.defaultPolicy)
                    let task = self.session.downloadTask(with: request)
                    self.taskIdentifierToURL[task.taskIdentifier] = url
                    self.urlToTask[url] = task
                    self.urlToCompletionHandlers[url] = [{
                        result in
                        switch result {
                        case let .success(value):
                            continuation.resume(returning: value)
                        case let .failure(error):
                            continuation.resume(throwing: error)
                        }
                    }]
                    task.resume()
                }
            }
        }
    }

    /// Cancels an in-flight download for the given URL, cleans up state, and notifies listeners with a cancellation error.
    public func cancelDownload(for url: URL) {
        var taskToCancel: URLSessionDownloadTask?
        var handlers: [(Result<(URL, URLResponse), Error>) -> Void] = []
        var taskId: Int?

        withState {
            if let task = urlToTask[url] {
                taskToCancel = task
                taskId = task.taskIdentifier
                // Capture and clear handlers atomically
                handlers = urlToCompletionHandlers[url] ?? []
                urlToCompletionHandlers[url] = nil
                urlToTask[url] = nil
                taskIdentifierToURL[task.taskIdentifier] = nil
                // Tear down any progress coalescer
                if let tid = taskId {
                    taskIdToProgress[tid]?.scheduledWorkItem?.cancel()
                    taskIdToProgress[tid] = nil
                }
            }
        }

        // Perform the cancellation outside the state queue
        taskToCancel?.cancel()

        guard !handlers.isEmpty else { return }

        // Notify listeners with a standardized cancellation error
        let cancelError = URLError(.cancelled)
        let userInfo: [String: Any] = [
            "taskIdentifier": taskId as Any,
            "url": url,
            "error": cancelError
        ]

        for handler in handlers {
            handler(.failure(cancelError))
        }

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .audioDownloadFailed, object: nil, userInfo: userInfo)
        }
    }

    /// To be called from AppDelegate when the system wakes the app for background events
    /// Stores the completion handler and calls it when background events are finished.
    public func resume(with identifier: String, completionHandler: @escaping () -> Void) {
        rebindInFlightTasks()
        withStateAsync {
            self.backgroundSessionCompletionHandlers[identifier] = {
                DispatchQueue.main.async {
                    completionHandler()
                }
            }
        }
    }

    // MARK: - URLSessionDownloadDelegate

    public func urlSession(_ session: URLSession,
                           downloadTask: URLSessionDownloadTask,
                           didWriteData bytesWritten: Int64,
                           totalBytesWritten: Int64,
                           totalBytesExpectedToWrite: Int64) {
        #if DEBUG
        debugLogDelegate(#function)
        #endif
        guard let url = withState({ taskIdentifierToURL[downloadTask.taskIdentifier] }) else {
            return
        }

        withState {
            handleProgressCoalescing(for: downloadTask, url: url, totalBytesWritten: totalBytesWritten, totalBytesExpected: totalBytesExpectedToWrite)
        }
    }

    public func urlSession(_ session: URLSession,
                           downloadTask: URLSessionDownloadTask,
                           didFinishDownloadingTo location: URL) {
        var url: URL?
        var handlers: [(Result<(URL, URLResponse), Error>) -> Void] = []
        var response: URLResponse?

        #if DEBUG
        debugLogDelegate(#function)
        #endif

        withState {
            url = taskIdentifierToURL[downloadTask.taskIdentifier]
            response = downloadTask.response
            guard let foundURL = url else { return }
            flushFinalProgressIfNeeded(for: downloadTask, url: foundURL)
            // Capture handlers atomically, then clear state
            handlers = urlToCompletionHandlers[foundURL] ?? []
            urlToCompletionHandlers[foundURL] = nil
            urlToTask[foundURL] = nil
            taskIdentifierToURL[downloadTask.taskIdentifier] = nil
        }

        guard let originalURL = url else {
            return
        }

        // Evaluate HTTP status for success/failure
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            // Non-success HTTP status: treat as failure
            let statusCode = httpResponse.statusCode
            let error = HTTPStatusError(statusCode: statusCode, url: originalURL, response: httpResponse)

            // Clean up temporary file to avoid leaks
            try? FileManager.default.removeItem(at: location)

            #if DEBUG
            debugFailureCount += 1
            debugFailureStatusCounts[statusCode, default: 0] += 1
            if let host = originalURL.host {
                debugFailureHosts[host, default: 0] += 1
            }
            #endif

            let failureUserInfo: [String: Any] = [
                "taskIdentifier": downloadTask.taskIdentifier,
                "url": originalURL,
                "statusCode": statusCode,
                "error": error
            ]

            // Notify continuations/handlers of failure
            for handler in handlers {
                handler(.failure(error))
            }

            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .audioDownloadFailed, object: nil, userInfo: failureUserInfo)
            }

            return
        }

        #if DEBUG
        debugSuccessCount += 1
        #endif

        let userInfo: [String: Any] = [
            "taskIdentifier": downloadTask.taskIdentifier,
            "url": originalURL,
            "temporaryFileURL": location,
            "response": response as Any
        ]

        // Call handlers
        for handler in handlers {
            handler(.success((location, response ?? URLResponse())))
        }

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .audioDownloadCompleted, object: nil, userInfo: userInfo)
        }
    }

    public func urlSession(_ session: URLSession,
                           task: URLSessionTask,
                           didCompleteWithError error: Error?) {
        guard let error = error else {
            // No error, nothing to do here
            return
        }

        #if DEBUG
        debugLogDelegate(#function)
        #endif

        var url: URL?
        var handlers: [(Result<(URL, URLResponse), Error>) -> Void] = []

        withState {
            url = taskIdentifierToURL[task.taskIdentifier]
            guard let foundURL = url else { return }
            flushFinalProgressIfNeeded(for: task, url: foundURL)
            // Capture handlers atomically, then clear state
            handlers = urlToCompletionHandlers[foundURL] ?? []
            urlToCompletionHandlers[foundURL] = nil
            urlToTask[foundURL] = nil
            taskIdentifierToURL[task.taskIdentifier] = nil
        }

        guard let originalURL = url else {
            return
        }

        let userInfo: [String: Any] = [
            "taskIdentifier": task.taskIdentifier,
            "url": originalURL,
            "error": error
        ]

        for handler in handlers {
            handler(.failure(error))
        }

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .audioDownloadFailed, object: nil, userInfo: userInfo)
        }
    }

    // MARK: - URLSessionDelegate for background session completion

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let identifier = session.configuration.identifier ?? ""
        var completionHandler: (() -> Void)?

        #if DEBUG
        debugLogDelegate(#function)
        #endif

        withState {
            completionHandler = backgroundSessionCompletionHandlers[identifier]
            backgroundSessionCompletionHandlers[identifier] = nil
        }

        if let completionHandler = completionHandler {
            #if DEBUG
            // Telemetry: count invocations; should be exactly once per identifier
            self.debugSuccessCount += 0 // placeholder to keep compiler using self in DEBUG
            #endif
            DispatchQueue.main.async {
                completionHandler()
            }
        }
    }
}

