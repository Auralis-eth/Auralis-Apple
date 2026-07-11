import Foundation

public protocol MediaDownloading: Sendable {
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

public typealias ProgressiveDownloadHandle = ProgressiveMediaDownloadHandle

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
        let httpResponse = response as? HTTPURLResponse
        if httpResponse?.statusCode == 206 {
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

        let completion = Task<URL, Error> {
            defer { try? handle.close() }
            let (bytes, response) = try await session.bytes(from: url)
            let expectedBytes = response.expectedContentLength > 0 ? response.expectedContentLength : nil
            await state.setResponse(response)

            var buffer = Data()
            buffer.reserveCapacity(32_768)
            var bytesWritten: Int64 = 0

            func flushBuffer() throws {
                guard !buffer.isEmpty else { return }
                try handle.write(contentsOf: buffer)
                bytesWritten += Int64(buffer.count)
                progress?(bytesWritten, expectedBytes)
                buffer.removeAll(keepingCapacity: true)
                if bytesWritten >= minimumPlayableBytes || expectedBytes == bytesWritten {
                    Task { await state.markPlayable() }
                }
            }

            for try await byte in bytes {
                buffer.append(byte)
                if buffer.count >= 32_768 {
                    try flushBuffer()
                }
            }
            try flushBuffer()
            await state.markPlayable()
            return destinationURL
        }

        let response = try await state.waitUntilPlayableOrFailed(completion: completion)
        return ProgressiveMediaDownloadHandle(playableURL: destinationURL, response: response, completion: completion)
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
