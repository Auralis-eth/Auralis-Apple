import Foundation
import UIKit

/// Notification payload contract:
/// - .audioDownloadProgress userInfo keys:
///   - "taskIdentifier": Int
///   - "url": URL (canonicalized)
///   - "bytesReceived": Int64
///   - "totalBytes": Int64
///   - "fractionCompleted": Double (present only when totalBytes > 0)
/// - .audioDownloadCompleted userInfo keys:
///   - "taskIdentifier": Int
///   - "url": URL (canonicalized)
///   - "temporaryFileURL": URL
///   - "response": URLResponse
///   - "finalURL": URL? (optional; post-redirect effective URL if different from original)
/// - .audioDownloadFailed userInfo keys:
///   - "taskIdentifier": Int
///   - "url": URL (canonicalized)
///   - "error": Error (AudioDownloadError)
///   - "statusCode": Int (present only for HTTP errors)
public extension Notification.Name {
    static let audioDownloadProgress = Notification.Name("AudioDownloadManager.audioDownloadProgress")
    static let audioDownloadCompleted = Notification.Name("AudioDownloadManager.audioDownloadCompleted")
    static let audioDownloadFailed = Notification.Name("AudioDownloadManager.audioDownloadFailed")
}

/// Handlers passed via await/coalesced completion are invoked on the main queue.
/// Policy: .userInitiated downloads continue in background using a non-discretionary background session.
public class AudioDownloadManager: NSObject, URLSessionDownloadDelegate {
    public enum AudioDownloadError: LocalizedError {
        case cancelled(underlying: Error?)
        case timeout(underlying: Error?)
        case httpStatus(Int)
        case other(underlying: Error)

        public var errorDescription: String? {
            switch self {
            case .cancelled: return "Download was cancelled."
            case .timeout: return "The download timed out."
            case .httpStatus(let code): return "Server returned status code \(code)."
            case .other: return "An unexpected network error occurred."
            }
        }

        public var underlyingError: Error? {
            switch self {
            case .cancelled(let u): return u
            case .timeout(let u): return u
            case .httpStatus: return nil
            case .other(let u): return u
            }
        }

        public var isCancelled: Bool {
            if case .cancelled = self { return true }
            return false
        }

        public var isTimeout: Bool {
            if case .timeout = self { return true }
            return false
        }

        public var statusCode: Int? {
            if case .httpStatus(let code) = self { return code }
            return nil
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

    // Rebind state flag
    private var isRebinding: Bool = false

    // Canonicalize URLs to a stable, round-trip-safe string key to prevent duplicates
    private func canonicalKey(for url: URL) -> String {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        // Lowercase scheme and host
        comps.scheme = comps.scheme?.lowercased()
        comps.host = comps.host?.lowercased()

        // Remove default ports
        if let port = comps.port {
            if (comps.scheme == "http" && port == 80) || (comps.scheme == "https" && port == 443) {
                comps.port = nil
            }
        }

        // Normalize path without losing percent-encoding: operate on percentEncodedPath directly
        var p = comps.percentEncodedPath
        if !p.isEmpty {
            if p.count > 1 && p.hasSuffix("/") { p.removeLast() }
            comps.percentEncodedPath = p
        }

        // Sort query items by name+value for stability (preserving percent-encoding via URLComponents)
        if let items = comps.queryItems, !items.isEmpty {
            let sorted = items.sorted { (a, b) -> Bool in
                if a.name == b.name { return (a.value ?? "") < (b.value ?? "") }
                return a.name < b.name
            }
            comps.queryItems = sorted
        }

        // Use the composed absolute string as stable key; enforce absolute URL invariant
        let key = comps.string ?? url.absoluteString
        if URL(string: key) == nil {
            #if DEBUG
            print("[AudioDownloadManager] canonicalKey produced non-URL string; falling back to original: \(key)")
            #endif
            return url.absoluteString
        }
        return key
    }

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

    // MARK: - Rebinding existing background tasks
    private func rebindInFlightTasks() {
        isRebinding = true
        let group = DispatchGroup()
        let sessions: [URLSession] = [backgroundSession, userInitiatedSession]
        for s in sessions {
            group.enter()
            s.getAllTasks { tasks in
                let downloadTasks = tasks.compactMap { $0 as? URLSessionDownloadTask }
                #if DEBUG
                self.withState {
                    self.debugDiscoveredTasksOnInit += downloadTasks.count
                }
                #endif

                for task in downloadTasks {
                    guard let rawURL = task.originalRequest?.url ?? task.currentRequest?.url else { continue }
                    let key = self.canonicalKey(for: rawURL)
                    self.withState {
                        if let existing = self.keyToTask[key], existing.taskIdentifier != task.taskIdentifier {
                            // Prefer system-discovered task; cancel app-created duplicate
                            #if DEBUG
                            self.debugDuplicateTaskPreventionCount += 1
                            #endif
                            // Purge state for the losing task
                            let losingId = existing.taskIdentifier
                            self.taskIdToProgress[losingId]?.scheduledWorkItem?.cancel()
                            self.taskIdToProgress[losingId] = nil
                            self.taskIdentifierToKey[losingId] = nil
                            existing.cancel()
                        }
                        // Bind the system task as the authoritative owner
                        self.taskIdentifierToKey[task.taskIdentifier] = key
                        self.keyToTask[key] = task
                        if self.keyToCompletionHandlers[key] == nil { self.keyToCompletionHandlers[key] = [] }
                    }
                }
                group.leave()
            }
        }
        group.notify(queue: stateQueue) {
            self.isRebinding = false

            // Drain pending listeners/starts now that authoritative tasks are bound
            for (key, listeners) in self.pendingListenersByKey {
                if let task = self.keyToTask[key] {
                    // Route listeners to authoritative existing task
                    self.keyToCompletionHandlers[key, default: []].append(contentsOf: listeners)
                } else {
                    // No authoritative task discovered; prefer resuming a pending task if any
                    if let pending = self.pendingTaskByKey[key] {
                        self.keyToCompletionHandlers[key] = listeners
                        pending.resume()
                        self.pendingTaskByKey[key] = nil
                    } else {
                        // Start one now using recorded policy (default to background)
                        let policy = self.pendingStartPolicyByKey[key] ?? self.defaultPolicy
                        guard let url = URL(string: key) else { continue }
                        let request = self.makeRequest(for: url, policy: policy)
                        let sessionToUse = policy == .userInitiated ? self.userInitiatedSession : self.backgroundSession
                        let task = sessionToUse.downloadTask(with: request)
                        self.taskIdentifierToKey[task.taskIdentifier] = key
                        self.keyToTask[key] = task
                        self.keyToCompletionHandlers[key] = listeners
                        task.resume()
                    }
                }
            }
            // Cleanup: cancel any pending tasks that lost to authoritative tasks
            for (key, pending) in self.pendingTaskByKey {
                if self.keyToTask[key] !== pending { pending.cancel() }
            }
            self.pendingTaskByKey.removeAll()

            self.pendingListenersByKey.removeAll()
            self.pendingStartPolicyByKey.removeAll()
        }
    }

    private lazy var backgroundSession: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "com.auralis.audio.background")
        // .background policy: discretionary, respect Low Data Mode; avoid expensive networks
        config.waitsForConnectivity = true
        config.isDiscretionary = true
        config.allowsExpensiveNetworkAccess = false
        config.allowsConstrainedNetworkAccess = false
        config.timeoutIntervalForRequest = 30 // seconds
        config.timeoutIntervalForResource = 15 * 60 // 15 minutes
        return URLSession(configuration: config, delegate: self, delegateQueue: delegateQueue)
    }()

    private lazy var userInitiatedSession: URLSession = {
        // Non-discretionary background session so user-initiated transfers continue in background
        let config = URLSessionConfiguration.background(withIdentifier: "com.auralis.audio.userInitiated")
        config.waitsForConnectivity = true
        config.isDiscretionary = false
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = true
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 15 * 60
        return URLSession(configuration: config, delegate: self, delegateQueue: delegateQueue)
    }()

    // Maps taskIdentifier -> original key (canonicalized string)
    private var taskIdentifierToKey: [Int: String] = [:]

    // Maps key (canonicalized string) -> array of completion handlers
    private var keyToCompletionHandlers: [String: [(Result<(URL, URLResponse), Error>) -> Void]] = [:]

    // Maps key (canonicalized string) -> URLSessionDownloadTask
    private var keyToTask: [String: URLSessionDownloadTask] = [:]

    // While a rebind is in progress, queue listeners and optional start intents to avoid races
    private var pendingListenersByKey: [String: [(Result<(URL, URLResponse), Error>) -> Void]] = [:]
    private var pendingStartPolicyByKey: [String: NetworkPolicy] = [:]

    // Pending tasks created during rebind, waiting for resume or cancellation
    private var pendingTaskByKey: [String: URLSessionDownloadTask] = [:]

    // Background completion exactly-once guard
    private struct BackgroundWake {
        var invoked: Bool
        var handler: () -> Void
    }
    private var backgroundWakeByIdentifier: [String: BackgroundWake] = [:]

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
            let key = canonicalKey(for: url)
            if let existingTask = keyToTask[key] {
                task = existingTask
                return
            }
            // If rebind is in progress and no authoritative task exists, create a suspended task and defer starting
            if isRebinding {
                let request = makeRequest(for: url, policy: policy ?? defaultPolicy)
                let sessionToUse = (policy ?? defaultPolicy) == .userInitiated ? userInitiatedSession : backgroundSession
                let newTask = sessionToUse.downloadTask(with: request)
                // Do NOT resume yet; allow rebind to decide
                taskIdentifierToKey[newTask.taskIdentifier] = key
                keyToTask[key] = newTask
                keyToCompletionHandlers[key] = []
                pendingStartPolicyByKey[key] = policy ?? defaultPolicy
                pendingTaskByKey[key] = newTask
                task = newTask
                return
            }
            // Normal path: create and start immediately
            let request = makeRequest(for: url, policy: policy ?? defaultPolicy)
            let sessionToUse = (policy ?? defaultPolicy) == .userInitiated ? userInitiatedSession : backgroundSession
            let newTask = sessionToUse.downloadTask(with: request)
            taskIdentifierToKey[newTask.taskIdentifier] = key
            keyToTask[key] = newTask
            keyToCompletionHandlers[key] = [] // Initialize empty handlers list
            task = newTask
            newTask.resume()
        }

        return task
    }

    /// Awaits the download completion and returns the temporary file URL and URLResponse.
    /// If a download for the URL is already in progress, the continuation will be appended.
    public func awaitDownload(from url: URL, policy: NetworkPolicy? = nil) async throws -> (URL, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let key = self.canonicalKey(for: url)
            if let _ = self.keyToTask[key] {
                #if DEBUG
                self.debugCoalescedListenerCount += 1
                #endif
                // Download in progress, append completion handler
                self.keyToCompletionHandlers[key, default: []].append { result in
                    switch result {
                    case let .success(value):
                        continuation.resume(returning: value)
                    case let .failure(error):
                        continuation.resume(throwing: error)
                    }
                }
            } else {
                if self.keyToTask[key] == nil && self.isRebinding {
                    // Rebind in progress: queue listener and defer task creation to rebind drain
                    self.pendingListenersByKey[key, default: []].append { result in
                        switch result {
                        case let .success(value):
                            continuation.resume(returning: value)
                        case let .failure(error):
                            continuation.resume(throwing: error)
                        }
                    }
                    // Record the most-permissive policy requested (prefer userInitiated if any)
                    let requested = policy ?? self.defaultPolicy
                    if let existing = self.pendingStartPolicyByKey[key] {
                        if existing == .background && requested == .userInitiated { self.pendingStartPolicyByKey[key] = .userInitiated }
                    } else {
                        self.pendingStartPolicyByKey[key] = requested
                    }
                    return
                }
                // No download in progress, start new download
                let request = self.makeRequest(for: url, policy: policy ?? self.defaultPolicy)
                let sessionToUse = (policy ?? self.defaultPolicy) == .userInitiated ? self.userInitiatedSession : self.backgroundSession
                let task = sessionToUse.downloadTask(with: request)
                self.taskIdentifierToKey[task.taskIdentifier] = key
                self.keyToTask[key] = task
                self.keyToCompletionHandlers[key] = [{
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

    /// Cancels an in-flight download for the given URL, cleans up state, and notifies listeners with a cancellation error.
    public func cancelDownload(for url: URL) {
        let key = canonicalKey(for: url)
        var taskToCancel: URLSessionDownloadTask?
        var handlers: [(Result<(URL, URLResponse), Error>) -> Void] = []
        var taskId: Int?

        withState {
            if let task = keyToTask[key] {
                taskToCancel = task
                taskId = task.taskIdentifier
                // Post final progress before terminal event
                flushFinalProgressIfNeeded(for: task, url: url)
                // Capture and clear handlers atomically
                handlers = keyToCompletionHandlers[key] ?? []
                keyToCompletionHandlers[key] = nil
                keyToTask[key] = nil
                taskIdentifierToKey[task.taskIdentifier] = nil
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

        // Notify listeners with a unified cancellation error
        let unified = AudioDownloadError.cancelled(underlying: URLError(.cancelled))
        if let originalURL = URL(string: key) {
            for handler in handlers {
                DispatchQueue.main.async { handler(.failure(unified)) }
            }
            let userInfo: [String: Any] = [
                "taskIdentifier": taskId as Any,
                "url": originalURL,
                "error": unified
            ]
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .audioDownloadFailed, object: nil, userInfo: userInfo)
            }
        } else {
            #if DEBUG
            print("[AudioDownloadManager] Suppressing cancellation notification due to invalid URL key: \(key)")
            #endif
            for handler in handlers {
                DispatchQueue.main.async { handler(.failure(unified)) }
            }
        }
    }

    /// To be called from AppDelegate when the system wakes the app for background events
    /// Stores the completion handler and calls it when background events are finished.
    public func resume(with identifier: String, completionHandler: @escaping () -> Void) {
        rebindInFlightTasks()
        withStateAsync {
            self.backgroundWakeByIdentifier[identifier] = BackgroundWake(invoked: false, handler: {
                DispatchQueue.main.async {
                    completionHandler()
                }
            })
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
        guard let url = withState({ self.taskIdentifierToKey[downloadTask.taskIdentifier] }).flatMap({ URL(string: $0) }) else {
            #if DEBUG
            let badKey = withState({ self.taskIdentifierToKey[downloadTask.taskIdentifier] }) ?? "<nil>"
            print("[AudioDownloadManager] Progress callback missing/invalid URL for key: \(badKey)")
            #endif
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
            if let key = taskIdentifierToKey[downloadTask.taskIdentifier] {
                url = URL(string: key)
            } else {
                url = nil
            }
            response = downloadTask.response
            guard let foundURL = url else { return }
            flushFinalProgressIfNeeded(for: downloadTask, url: foundURL)
            // Capture handlers atomically, then clear state
            handlers = keyToCompletionHandlers[foundURL.absoluteString] ?? []
            keyToCompletionHandlers[foundURL.absoluteString] = nil
            keyToTask[foundURL.absoluteString] = nil
            taskIdentifierToKey[downloadTask.taskIdentifier] = nil
        }

        guard let originalURL = url else {
            return
        }

        // Evaluate HTTP status for success/failure
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            // Non-success HTTP status: treat as failure
            let statusCode = httpResponse.statusCode
            let error = AudioDownloadError.httpStatus(statusCode)

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

        let finalURL = downloadTask.currentRequest?.url

        let userInfo: [String: Any] = [
            "taskIdentifier": downloadTask.taskIdentifier,
            "url": originalURL,
            "temporaryFileURL": location,
            "response": response as Any,
            "finalURL": finalURL as Any,
        ]

        // Call handlers on main queue
        for handler in handlers {
            DispatchQueue.main.async { handler(.success((location, response ?? URLResponse()))) }
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
            if let key = taskIdentifierToKey[task.taskIdentifier] {
                url = URL(string: key)
            } else {
                url = nil
            }
            guard let foundURL = url else { return }
            flushFinalProgressIfNeeded(for: task, url: foundURL)
            // Capture handlers atomically, then clear state
            handlers = keyToCompletionHandlers[foundURL.absoluteString] ?? []
            keyToCompletionHandlers[foundURL.absoluteString] = nil
            keyToTask[foundURL.absoluteString] = nil
            taskIdentifierToKey[task.taskIdentifier] = nil
        }

        guard let originalURL = url else {
            return
        }

        // Map to unified error
        let unified: AudioDownloadError
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut: unified = .timeout(underlying: urlError)
            case .cancelled: unified = .cancelled(underlying: urlError)
            default: unified = .other(underlying: urlError)
            }
        } else {
            unified = .other(underlying: error)
        }

        let userInfo: [String: Any] = [
            "taskIdentifier": task.taskIdentifier,
            "url": originalURL,
            "error": unified
        ]

        for handler in handlers { DispatchQueue.main.async { handler(.failure(unified)) } }

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
            if var wake = backgroundWakeByIdentifier[identifier] {
                if wake.invoked { completionHandler = nil } else {
                    wake.invoked = true
                    completionHandler = wake.handler
                    backgroundWakeByIdentifier[identifier] = wake
                }
            } else {
                completionHandler = nil
            }
        }

        if let completionHandler = completionHandler {
            DispatchQueue.main.async {
                completionHandler()
            }
        }
    }
}
