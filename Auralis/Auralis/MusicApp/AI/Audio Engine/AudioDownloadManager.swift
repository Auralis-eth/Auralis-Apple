import Foundation
import UIKit

public extension Notification.Name {
    static let audioDownloadProgress = Notification.Name("AudioDownloadManager.audioDownloadProgress")
    static let audioDownloadCompleted = Notification.Name("AudioDownloadManager.audioDownloadCompleted")
    static let audioDownloadFailed = Notification.Name("AudioDownloadManager.audioDownloadFailed")
}

public class AudioDownloadManager: NSObject, URLSessionDownloadDelegate {
    public static let shared = AudioDownloadManager()

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

    #if DEBUG
    private func debugLogDelegate(_ function: String) {
        let label = String(cString: __dispatch_queue_get_label(nil))
        print("[AudioDownloadManager] Delegate callback: \(function) on queue: \(label)")
    }
    #endif

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "com.auralis.audio.background")
        config.waitsForConnectivity = true
        config.isDiscretionary = true
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = true
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
    }

    /// Starts a download for the given URL. Returns the URLSessionDownloadTask immediately.
    /// If a download for this URL is already in progress, returns the existing task.
    @discardableResult
    public func startDownload(from url: URL) -> URLSessionDownloadTask {
        var task: URLSessionDownloadTask!

        withState {
            if let existingTask = urlToTask[url] {
                task = existingTask
                return
            }
            let newTask = session.downloadTask(with: url)
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
    public func awaitDownload(from url: URL) async throws -> (URL, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            self.withStateAsync {
                if let _ = self.urlToTask[url] {
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
                    let task = self.session.downloadTask(with: url)
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

    /// To be called from AppDelegate when the system wakes the app for background events
    /// Stores the completion handler and calls it when background events are finished.
    public func resume(with identifier: String, completionHandler: @escaping () -> Void) {
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

        let fractionCompleted: Double
        if totalBytesExpectedToWrite > 0 {
            fractionCompleted = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        } else {
            fractionCompleted = 0
        }

        let userInfo: [String: Any] = [
            "taskIdentifier": downloadTask.taskIdentifier,
            "url": url,
            "bytesReceived": totalBytesWritten,
            "totalBytes": totalBytesExpectedToWrite,
            "fractionCompleted": fractionCompleted
        ]

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .audioDownloadProgress, object: nil, userInfo: userInfo)
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
            guard let url = url else { return }
            handlers = urlToCompletionHandlers[url] ?? []
            // Clear state for finished download
            urlToCompletionHandlers[url] = nil
            urlToTask[url] = nil
            taskIdentifierToURL[downloadTask.taskIdentifier] = nil
        }

        guard let originalURL = url, !handlers.isEmpty else {
            return
        }

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
            guard let url = url else { return }
            handlers = urlToCompletionHandlers[url] ?? []
            // Clear state for failed download
            urlToCompletionHandlers[url] = nil
            urlToTask[url] = nil
            taskIdentifierToURL[task.taskIdentifier] = nil
        }

        guard let originalURL = url, !handlers.isEmpty else {
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
            DispatchQueue.main.async {
                completionHandler()
            }
        }
    }
}
