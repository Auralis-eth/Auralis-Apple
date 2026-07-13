import Foundation

public protocol MediaDownloading: Sendable {
    /// Downloads the full resource to a temporary file.
    ///
    /// `progress` reporting may be coarse: implementations backed by
    /// `URLSession.download(from:)` invoke it exactly once, after the transfer
    /// completes. For incremental progress suitable for UI, use
    /// `ProgressiveMediaDownloading.downloadUntilPlayable(from:to:minimumPlayableBytes:progress:)`.
    func download(from url: URL, progress: (@Sendable (Int64, Int64?) -> Void)?) async throws -> (URL, URLResponse)
}

public extension MediaDownloading {
    func download(from url: URL) async throws -> (URL, URLResponse) {
        try await download(from: url, progress: nil)
    }
}

public final class ProgressiveMediaDownloadHandle: @unchecked Sendable {
    public let playableURL: URL
    public let response: URLResponse
    public let completion: Task<URL, Error>

    public init(playableURL: URL, response: URLResponse, completion: Task<URL, Error>) {
        self.playableURL = playableURL
        self.response = response
        self.completion = completion
    }
}

public protocol ProgressiveMediaDownloading: MediaDownloading {
    func downloadUntilPlayable(
        from url: URL,
        to destinationURL: URL,
        minimumPlayableBytes: Int64,
        progress: (@Sendable (Int64, Int64?) -> Void)?
    ) async throws -> ProgressiveMediaDownloadHandle
}

public protocol ResumableMediaDownloading: MediaDownloading {
    func resumeDownload(
        from url: URL,
        to partialFileURL: URL,
        startingAt byteOffset: Int64,
        eTag: String?,
        progress: (@Sendable (Int64, Int64?) -> Void)?
    ) async throws -> (URL, URLResponse)
}

public struct URLSessionMediaDownloader: ProgressiveMediaDownloading, ResumableMediaDownloading {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func download(
        from url: URL,
        progress: (@Sendable (Int64, Int64?) -> Void)? = nil
    ) async throws -> (URL, URLResponse) {
        let (temporaryURL, response) = try await session.download(from: url)
        do {
            try Self.validateHTTPStatus(of: response, for: url)
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }
        let byteCount = (try? FileManager.default.attributesOfItem(atPath: temporaryURL.path)[.size] as? Int64) ?? 0
        progress?(byteCount, response.expectedContentLength > 0 ? response.expectedContentLength : nil)
        return (temporaryURL, response)
    }

    public func resumeDownload(
        from url: URL,
        to partialFileURL: URL,
        startingAt byteOffset: Int64,
        eTag: String? = nil,
        progress: (@Sendable (Int64, Int64?) -> Void)? = nil
    ) async throws -> (URL, URLResponse) {
        var request = URLRequest(url: url)
        request.setValue("bytes=\(byteOffset)-", forHTTPHeaderField: "Range")
        if let eTag {
            request.setValue(eTag, forHTTPHeaderField: "If-Range")
        }

        let (temporaryURL, response) = try await session.download(for: request)
        do {
            try Self.validateHTTPStatus(of: response, for: url)
        } catch {
            // Leave the partial file intact so the caller can retry the resume.
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }

        let httpResponse = response as? HTTPURLResponse
        if let httpResponse, httpResponse.statusCode == 206 {
            // A 206 body is only appendable if it really starts at the resume
            // offset; a stale If-Range match or a buggy server would otherwise
            // silently corrupt the partial file.
            guard Self.contentRangeStart(of: httpResponse) == byteOffset else {
                try? FileManager.default.removeItem(at: temporaryURL)
                throw AuraPlayError.downloadFailed(
                    "Partial content did not start at byte \(byteOffset) for \(url.absoluteString)"
                )
            }
            try Self.appendFileContents(from: temporaryURL, to: partialFileURL)
            let byteCount = (try? FileManager.default.attributesOfItem(atPath: partialFileURL.path)[.size] as? Int64) ?? byteOffset
            progress?(byteCount, response.expectedContentLength > 0 ? byteOffset + response.expectedContentLength : nil)
            return (partialFileURL, response)
        }

        try? FileManager.default.removeItem(at: partialFileURL)
        try FileManager.default.moveItem(at: temporaryURL, to: partialFileURL)
        let byteCount = (try? FileManager.default.attributesOfItem(atPath: partialFileURL.path)[.size] as? Int64) ?? 0
        progress?(byteCount, response.expectedContentLength > 0 ? response.expectedContentLength : nil)
        return (partialFileURL, response)
    }

    public static func appendFileContents(
        from sourceURL: URL,
        to destinationURL: URL,
        bufferSize: Int = 64 * 1_024
    ) throws {
        let chunkSize = max(1, bufferSize)
        let reader = try FileHandle(forReadingFrom: sourceURL)
        defer { try? reader.close() }

        let writer = try FileHandle(forWritingTo: destinationURL)
        defer { try? writer.close() }
        try writer.seekToEnd()

        while true {
            let chunk = try reader.read(upToCount: chunkSize) ?? Data()
            guard !chunk.isEmpty else {
                break
            }
            try writer.write(contentsOf: chunk)
        }
    }

    public func downloadUntilPlayable(
        from url: URL,
        to destinationURL: URL,
        minimumPlayableBytes: Int64,
        progress: (@Sendable (Int64, Int64?) -> Void)? = nil
    ) async throws -> ProgressiveMediaDownloadHandle {
        let state = ProgressiveDownloadState()
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: destinationURL)
        fileManager.createFile(atPath: destinationURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destinationURL)
        let session = self.session

        let completion = Task<URL, Error> {
            defer { try? handle.close() }
            var bytesWritten: Int64 = 0
            do {
                let (response, chunks, consume) = try await Self.chunkedByteStream(from: url, session: session)
                try Self.validateHTTPStatus(of: response, for: url)
                let expectedBytes = response.expectedContentLength > 0 ? response.expectedContentLength : nil
                await state.setResponse(response)

                var reportedPlayable = false

                for try await chunk in chunks {
                    try handle.write(contentsOf: chunk)
                    consume(chunk.count)
                    bytesWritten += Int64(chunk.count)
                    progress?(bytesWritten, expectedBytes)
                    if !reportedPlayable, bytesWritten >= minimumPlayableBytes || expectedBytes == bytesWritten {
                        reportedPlayable = true
                        await state.markPlayable()
                    }
                }
                // Stream iteration ends without throwing when the task is cancelled.
                try Task.checkCancellation()
                await state.markPlayable()
                return destinationURL
            } catch {
                // Discard an empty destination file so failed transfers don't
                // leave litter that looks cached; keep partial bytes for resume.
                if bytesWritten == 0 {
                    try? fileManager.removeItem(at: destinationURL)
                }
                throw error
            }
        }

        let response = try await state.waitUntilPlayableOrFailed(completion: completion)
        return ProgressiveMediaDownloadHandle(playableURL: destinationURL, response: response, completion: completion)
    }

    /// Parses the first byte position from a `Content-Range` header of the form
    /// `bytes <start>-<end>/<total|*>`. Returns nil when the header is missing
    /// or malformed, which callers must treat as an unverifiable range.
    static func contentRangeStart(of response: HTTPURLResponse) -> Int64? {
        guard let header = response.value(forHTTPHeaderField: "Content-Range") else {
            return nil
        }
        let trimmed = header.trimmingCharacters(in: .whitespaces)
        guard trimmed.lowercased().hasPrefix("bytes") else {
            return nil
        }
        let rangeSpec = trimmed.dropFirst("bytes".count).trimmingCharacters(in: .whitespaces)
        guard let dashIndex = rangeSpec.firstIndex(of: "-") else {
            return nil
        }
        return Int64(rangeSpec[..<dashIndex])
    }

    static func validateHTTPStatus(of response: URLResponse, for url: URL) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AuraPlayError.downloadFailed("HTTP \(httpResponse.statusCode) for \(url.absoluteString)")
        }
    }

    /// Streams the response body as `Data` chunks so large media files are never
    /// iterated byte-by-byte on the hot download path.
    ///
    /// The returned `consume` closure must be called with each chunk's byte count
    /// once it has been persisted; it drives the backpressure that suspends the
    /// transfer when the consumer falls behind.
    private static func chunkedByteStream(
        from url: URL,
        session: URLSession
    ) async throws -> (URLResponse, AsyncThrowingStream<Data, Error>, consume: @Sendable (Int) -> Void) {
        let (chunks, continuation) = AsyncThrowingStream.makeStream(of: Data.self)
        let delegate = ChunkStreamingTaskDelegate(chunks: continuation)
        let task = session.dataTask(with: URLRequest(url: url))
        task.delegate = delegate
        delegate.attach(to: task)
        continuation.onTermination = { termination in
            if case .cancelled = termination {
                task.cancel()
            }
        }
        task.resume()
        do {
            let response = try await withTaskCancellationHandler {
                try await delegate.response()
            } onCancel: {
                task.cancel()
            }
            return (response, chunks, { delegate.consume(byteCount: $0) })
        } catch {
            task.cancel()
            throw error
        }
    }
}

// Internal (not private) so the backpressure watermarks stay unit-testable.
final class ChunkStreamingTaskDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    /// Unconsumed buffered bytes above which the transfer is suspended, and the
    /// drain level at which it resumes. Bounds memory when disk writes lag the
    /// network without ever dropping chunks.
    ///
    /// `URLSessionTask.suspend()` semantics are only loosely documented for
    /// data tasks: chunks the session has already buffered may still be
    /// delivered after suspension, so `unconsumedByteCount` can overshoot the
    /// high-water mark. That is fine — the overshoot is bounded by URLSession's
    /// own buffering, and every delivered byte is still counted and drained
    /// through `consume(byteCount:)` before the transfer resumes.
    static let bufferHighWaterMark: Int64 = 8 * 1_024 * 1_024
    static let bufferLowWaterMark: Int64 = 2 * 1_024 * 1_024

    private let chunks: AsyncThrowingStream<Data, Error>.Continuation
    private let lock = NSLock()
    private var receivedResponse: URLResponse?
    private var completionError: Error?
    private var isFinished = false
    private var responseContinuation: CheckedContinuation<URLResponse, Error>?
    // The task retains its delegate, so this back-reference must stay weak.
    private weak var task: URLSessionDataTask?
    private var unconsumedByteCount: Int64 = 0
    private var isTransferSuspended = false

    init(chunks: AsyncThrowingStream<Data, Error>.Continuation) {
        self.chunks = chunks
    }

    func attach(to task: URLSessionDataTask) {
        lock.withLock { self.task = task }
    }

    func consume(byteCount: Int) {
        let taskToResume: URLSessionDataTask? = lock.withLock {
            unconsumedByteCount -= Int64(byteCount)
            guard isTransferSuspended, unconsumedByteCount <= Self.bufferLowWaterMark else {
                return nil
            }
            isTransferSuspended = false
            return task
        }
        taskToResume?.resume()
    }

    func response() async throws -> URLResponse {
        try await withCheckedThrowingContinuation { continuation in
            let immediateResult: Result<URLResponse, Error>? = lock.withLock {
                if let receivedResponse {
                    return .success(receivedResponse)
                }
                if isFinished {
                    return .failure(completionError ?? URLError(.badServerResponse))
                }
                responseContinuation = continuation
                return nil
            }
            if let immediateResult {
                continuation.resume(with: immediateResult)
            }
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse
    ) async -> URLSession.ResponseDisposition {
        let continuation = lock.withLock {
            receivedResponse = response
            let pending = responseContinuation
            responseContinuation = nil
            return pending
        }
        continuation?.resume(returning: response)
        return .allow
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        chunks.yield(data)
        let taskToSuspend: URLSessionDataTask? = lock.withLock {
            unconsumedByteCount += Int64(data.count)
            guard !isTransferSuspended, !isFinished, unconsumedByteCount >= Self.bufferHighWaterMark else {
                return nil
            }
            isTransferSuspended = true
            return task
        }
        taskToSuspend?.suspend()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let continuation = lock.withLock {
            isFinished = true
            completionError = error
            let pending = responseContinuation
            responseContinuation = nil
            return pending
        }
        continuation?.resume(throwing: error ?? URLError(.badServerResponse))
        if let error {
            chunks.finish(throwing: error)
        } else {
            chunks.finish()
        }
    }
}

private actor ProgressiveDownloadState {
    private var response: URLResponse?
    private var isPlayable = false
    private var waiters: [CheckedContinuation<URLResponse, Error>] = []

    func setResponse(_ response: URLResponse) {
        self.response = response
        resumeIfReady()
    }

    func markPlayable() {
        isPlayable = true
        resumeIfReady()
    }

    func waitUntilPlayableOrFailed(completion: Task<URL, Error>) async throws -> URLResponse {
        if isPlayable, let response {
            return response
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiters.append(continuation)
                resumeIfReady()
                Task {
                    do {
                        _ = try await completion.value
                        markPlayable()
                    } catch {
                        fail(error)
                    }
                }
            }
        } onCancel: {
            completion.cancel()
        }
    }

    private func resumeIfReady() {
        guard isPlayable, let response else {
            return
        }
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume(returning: response) }
    }

    private func fail(_ error: Error) {
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume(throwing: error) }
    }
}
