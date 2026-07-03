import AVFoundation
import Foundation

public protocol VideoResourceLoading: Sendable {
    func shouldWaitForLoading(of request: AVAssetResourceLoadingRequest) async -> Bool
    func didCancelLoading(_ request: AVAssetResourceLoadingRequest) async
}

public actor NoOpVideoResourceLoader: VideoResourceLoading {
    public init() {}

    public func shouldWaitForLoading(of request: AVAssetResourceLoadingRequest) async -> Bool {
        false
    }

    public func didCancelLoading(_ request: AVAssetResourceLoadingRequest) async {}
}

public final class VideoResourceLoaderCoordinator: NSObject, VideoAssetResourceLoaderDelegate, @unchecked Sendable {
    private let loader: any VideoResourceLoading

    public init(loader: any VideoResourceLoading) {
        self.loader = loader
    }

    public func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        Task {
            let isHandled = await loader.shouldWaitForLoading(of: loadingRequest)
            if !isHandled {
                loadingRequest.finishLoading(with: VideoPlaybackError.resourceLoadingUnsupported)
            }
        }
        return true
    }

    public func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        didCancel loadingRequest: AVAssetResourceLoadingRequest
    ) {
        Task {
            await loader.didCancelLoading(loadingRequest)
        }
    }
}

public struct ProgressiveVideoCacheConfiguration: Equatable, Sendable {
    public let customScheme: String
    public let cacheDirectory: URL

    public init(
        customScheme: String = "auraplay-video-cache",
        cacheDirectory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AuraPlayVideoEngine/ProgressiveCache", isDirectory: true)
    ) {
        self.customScheme = customScheme
        self.cacheDirectory = cacheDirectory
    }
}

public struct ProgressiveVideoCacheURLMapper: Sendable {
    public let configuration: ProgressiveVideoCacheConfiguration

    public init(configuration: ProgressiveVideoCacheConfiguration = ProgressiveVideoCacheConfiguration()) {
        self.configuration = configuration
    }

    public func assetURL(for remoteURL: URL) -> URL {
        guard isProgressiveRemoteURL(remoteURL), var components = URLComponents(url: remoteURL, resolvingAgainstBaseURL: false) else {
            return remoteURL
        }
        components.scheme = configuration.customScheme
        return components.url ?? remoteURL
    }

    public func originalURL(for assetURL: URL) -> URL? {
        guard assetURL.scheme == configuration.customScheme,
              var components = URLComponents(url: assetURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.scheme = "https"
        return components.url
    }

    public func isProgressiveRemoteURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https" else { return false }
        return url.pathExtension.lowercased() != "m3u8"
    }
}

public protocol VideoAssetURLMapping: Sendable {
    func assetURL(for remoteURL: URL) -> URL
    var resourceLoaderDelegate: VideoAssetResourceLoaderDelegate? { get }
    var resourceLoaderQueue: DispatchQueue { get }
}

public struct DirectVideoAssetURLMapper: VideoAssetURLMapping {
    public init() {}

    public var resourceLoaderDelegate: VideoAssetResourceLoaderDelegate? { nil }
    public var resourceLoaderQueue: DispatchQueue { .main }

    public func assetURL(for remoteURL: URL) -> URL {
        remoteURL
    }
}

public final class ProgressiveVideoCachingPipeline: VideoAssetURLMapping, @unchecked Sendable {
    public let store: ProgressiveVideoCacheStore
    public let loader: ProgressiveVideoResourceLoader
    public let mapper: ProgressiveVideoCacheURLMapper
    public let resourceLoaderQueue: DispatchQueue

    public init(
        configuration: ProgressiveVideoCacheConfiguration = ProgressiveVideoCacheConfiguration(),
        session: URLSession = .shared,
        resourceLoaderQueue: DispatchQueue = DispatchQueue(label: "com.auraplay.video.progressive-resource-loader")
    ) {
        self.store = ProgressiveVideoCacheStore(configuration: configuration)
        self.mapper = ProgressiveVideoCacheURLMapper(configuration: configuration)
        self.loader = ProgressiveVideoResourceLoader(store: store, mapper: mapper, session: session)
        self.resourceLoaderQueue = resourceLoaderQueue
    }

    public var resourceLoaderDelegate: VideoAssetResourceLoaderDelegate? { loader }

    public func assetURL(for remoteURL: URL) -> URL {
        mapper.assetURL(for: remoteURL)
    }
}

public struct ProgressiveVideoCacheRecord: Codable, Equatable, Sendable {
    public let sourceURL: URL
    public var contentLength: Int64?
    public var contentType: String?
    public var cachedRanges: [CachedByteRange]
    public var isComplete: Bool

    public init(
        sourceURL: URL,
        contentLength: Int64? = nil,
        contentType: String? = nil,
        cachedRanges: [CachedByteRange] = [],
        isComplete: Bool = false
    ) {
        self.sourceURL = sourceURL
        self.contentLength = contentLength
        self.contentType = contentType
        self.cachedRanges = cachedRanges
        self.isComplete = isComplete
    }
}

public struct CachedByteRange: Codable, Equatable, Sendable {
    public let offset: Int64
    public let length: Int

    public init(offset: Int64, length: Int) {
        self.offset = offset
        self.length = length
    }

    public var endOffset: Int64 {
        offset + Int64(length)
    }

    public func contains(offset requestedOffset: Int64, length requestedLength: Int) -> Bool {
        offset <= requestedOffset && endOffset >= requestedOffset + Int64(requestedLength)
    }
}

public actor ProgressiveVideoCacheStore {
    private let configuration: ProgressiveVideoCacheConfiguration
    private let fileManager: FileManager
    private var records: [URL: ProgressiveVideoCacheRecord] = [:]

    public init(
        configuration: ProgressiveVideoCacheConfiguration = ProgressiveVideoCacheConfiguration(),
        fileManager: FileManager = .default
    ) {
        self.configuration = configuration
        self.fileManager = fileManager
        try? fileManager.createDirectory(at: configuration.cacheDirectory, withIntermediateDirectories: true)
        self.records = Self.loadRecordsFromDisk(configuration: configuration, fileManager: fileManager)
    }

    public func record(for sourceURL: URL) -> ProgressiveVideoCacheRecord? {
        records[sourceURL]
    }

    public func localFileURL(for sourceURL: URL) -> URL? {
        guard records[sourceURL]?.isComplete == true else { return nil }
        return dataFileURL(for: sourceURL)
    }

    public func cachedData(for sourceURL: URL, offset: Int64, length: Int) throws -> Data? {
        guard let record = records[sourceURL], record.cachedRanges.contains(where: { $0.contains(offset: offset, length: length) }) else {
            return nil
        }
        let handle = try FileHandle(forReadingFrom: dataFileURL(for: sourceURL))
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(offset))
        return try handle.read(upToCount: length)
    }

    public func store(
        data: Data,
        for sourceURL: URL,
        offset: Int64,
        contentLength: Int64?,
        contentType: String?
    ) throws -> ProgressiveVideoCacheRecord {
        try fileManager.createDirectory(at: configuration.cacheDirectory, withIntermediateDirectories: true)
        let fileURL = dataFileURL(for: sourceURL)
        if !fileManager.fileExists(atPath: fileURL.path) {
            fileManager.createFile(atPath: fileURL.path, contents: nil)
        }

        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(offset))
        try handle.write(contentsOf: data)

        var record = records[sourceURL] ?? ProgressiveVideoCacheRecord(sourceURL: sourceURL)
        record.contentLength = contentLength ?? record.contentLength
        record.contentType = contentType ?? record.contentType
        record.cachedRanges = Self.merge(record.cachedRanges + [CachedByteRange(offset: offset, length: data.count)])
        if let contentLength = record.contentLength, record.cachedRanges.contains(where: { $0.offset == 0 && $0.endOffset >= contentLength }) {
            record.isComplete = true
        }
        records[sourceURL] = record
        try persist(record)
        return record
    }

    private nonisolated static func merge(_ ranges: [CachedByteRange]) -> [CachedByteRange] {
        let sorted = ranges.sorted { $0.offset < $1.offset }
        var merged: [CachedByteRange] = []
        for range in sorted {
            guard let last = merged.last else {
                merged.append(range)
                continue
            }
            if last.endOffset >= range.offset {
                merged.removeLast()
                let end = max(last.endOffset, range.endOffset)
                merged.append(CachedByteRange(offset: last.offset, length: Int(end - last.offset)))
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    private nonisolated static func loadRecordsFromDisk(
        configuration: ProgressiveVideoCacheConfiguration,
        fileManager: FileManager
    ) -> [URL: ProgressiveVideoCacheRecord] {
        guard let files = try? fileManager.contentsOfDirectory(at: configuration.cacheDirectory, includingPropertiesForKeys: nil) else {
            return [:]
        }
        var records: [URL: ProgressiveVideoCacheRecord] = [:]
        for url in files where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let record = try? JSONDecoder().decode(ProgressiveVideoCacheRecord.self, from: data) else {
                continue
            }
            records[record.sourceURL] = record
        }
        return records
    }

    private func persist(_ record: ProgressiveVideoCacheRecord) throws {
        let data = try JSONEncoder().encode(record)
        try data.write(to: metadataFileURL(for: record.sourceURL), options: [.atomic])
    }

    private func dataFileURL(for sourceURL: URL) -> URL {
        configuration.cacheDirectory.appendingPathComponent(cacheKey(for: sourceURL)).appendingPathExtension("media")
    }

    private func metadataFileURL(for sourceURL: URL) -> URL {
        configuration.cacheDirectory.appendingPathComponent(cacheKey(for: sourceURL)).appendingPathExtension("json")
    }

    private func cacheKey(for sourceURL: URL) -> String {
        Data(sourceURL.absoluteString.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
    }
}

public final class ProgressiveVideoResourceLoader: NSObject, VideoAssetResourceLoaderDelegate, @unchecked Sendable {
    private let store: ProgressiveVideoCacheStore
    private let mapper: ProgressiveVideoCacheURLMapper
    private let session: URLSession
    private let lock = NSLock()
    private var activeTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    private let streamChunkSize = 64 * 1024

    public init(store: ProgressiveVideoCacheStore, mapper: ProgressiveVideoCacheURLMapper, session: URLSession = .shared) {
        self.store = store
        self.mapper = mapper
        self.session = session
    }

    public func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        let requestID = ObjectIdentifier(loadingRequest)
        let task = Task { [weak self, loadingRequest] in
            guard let self else { return }
            await self.handle(loadingRequest, requestID: requestID)
        }
        lock.withLock {
            activeTasks[requestID] = task
        }
        return true
    }

    public func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        let requestID = ObjectIdentifier(loadingRequest)
        let task = lock.withLock { activeTasks.removeValue(forKey: requestID) }
        task?.cancel()
    }

    private func handle(_ loadingRequest: AVAssetResourceLoadingRequest, requestID: ObjectIdentifier) async {
        defer {
            lock.withLock {
                activeTasks.removeValue(forKey: requestID)
            }
        }

        guard let assetURL = loadingRequest.request.url,
              let sourceURL = mapper.originalURL(for: assetURL) else {
            loadingRequest.finishLoading(with: VideoPlaybackError.resourceLoadingUnsupported)
            return
        }

        let requestedOffset = requestedOffset(for: loadingRequest)
        let requestedLength = max(loadingRequest.dataRequest?.requestedLength ?? 0, 0)

        do {
            if Task.isCancelled { throw CancellationError() }
            if requestedLength > 0, let cached = try await store.cachedData(for: sourceURL, offset: requestedOffset, length: requestedLength) {
                if let record = await store.record(for: sourceURL) {
                    fillContentInformation(on: loadingRequest, record: record, fallbackLength: Int64(cached.count))
                }
                loadingRequest.dataRequest?.respond(with: cached)
                loadingRequest.finishLoading()
                return
            }

            try await streamRemoteRange(
                sourceURL: sourceURL,
                requestedOffset: requestedOffset,
                requestedLength: requestedLength,
                loadingRequest: loadingRequest
            )
        } catch is CancellationError {
            // AVFoundation owns cancelled loading requests; do not finish a request it cancelled.
        } catch {
            loadingRequest.finishLoading(with: error)
        }
    }

    private func streamRemoteRange(
        sourceURL: URL,
        requestedOffset: Int64,
        requestedLength: Int,
        loadingRequest: AVAssetResourceLoadingRequest
    ) async throws {
        var request = URLRequest(url: sourceURL)
        if requestedLength > 0 {
            let end = requestedOffset + Int64(requestedLength) - 1
            request.setValue("bytes=\(requestedOffset)-\(end)", forHTTPHeaderField: "Range")
        }

        let (bytes, response) = try await session.bytes(for: request)
        let metadata = responseMetadata(from: response, requestedOffset: requestedOffset)
        let initialRecord = ProgressiveVideoCacheRecord(
            sourceURL: sourceURL,
            contentLength: metadata.contentLength,
            contentType: metadata.contentType
        )
        fillContentInformation(on: loadingRequest, record: initialRecord, fallbackLength: metadata.contentLength ?? Int64(requestedLength))

        var buffer = Data()
        buffer.reserveCapacity(streamChunkSize)
        var writeOffset = requestedOffset
        var lastRecord = initialRecord

        for try await byte in bytes {
            try Task.checkCancellation()
            buffer.append(byte)
            if buffer.count >= streamChunkSize {
                lastRecord = try await flush(buffer, sourceURL: sourceURL, offset: writeOffset, metadata: metadata, loadingRequest: loadingRequest)
                writeOffset += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
            }
        }

        if !buffer.isEmpty {
            lastRecord = try await flush(buffer, sourceURL: sourceURL, offset: writeOffset, metadata: metadata, loadingRequest: loadingRequest)
        }

        fillContentInformation(on: loadingRequest, record: lastRecord, fallbackLength: metadata.contentLength ?? Int64(requestedLength))
        loadingRequest.finishLoading()
    }

    private func flush(
        _ data: Data,
        sourceURL: URL,
        offset: Int64,
        metadata: (contentLength: Int64?, contentType: String?),
        loadingRequest: AVAssetResourceLoadingRequest
    ) async throws -> ProgressiveVideoCacheRecord {
        loadingRequest.dataRequest?.respond(with: data)
        return try await store.store(
            data: data,
            for: sourceURL,
            offset: offset,
            contentLength: metadata.contentLength,
            contentType: metadata.contentType
        )
    }

    private func requestedOffset(for loadingRequest: AVAssetResourceLoadingRequest) -> Int64 {
        guard let dataRequest = loadingRequest.dataRequest else { return 0 }
        if dataRequest.currentOffset != 0 {
            return dataRequest.currentOffset
        }
        return dataRequest.requestedOffset
    }

    private func fillContentInformation(
        on loadingRequest: AVAssetResourceLoadingRequest,
        record: ProgressiveVideoCacheRecord,
        fallbackLength: Int64
    ) {
        guard let contentInformationRequest = loadingRequest.contentInformationRequest else { return }
        contentInformationRequest.contentType = record.contentType ?? AVFileType.mp4.rawValue
        contentInformationRequest.contentLength = record.contentLength ?? fallbackLength
        contentInformationRequest.isByteRangeAccessSupported = true
    }

    private func responseMetadata(
        from response: URLResponse,
        requestedOffset: Int64
    ) -> (contentLength: Int64?, contentType: String?) {
        guard let httpResponse = response as? HTTPURLResponse else {
            let expectedLength = response.expectedContentLength > 0 ? response.expectedContentLength : nil
            return (expectedLength.map { requestedOffset + $0 }, response.mimeType)
        }
        let contentRange = httpResponse.value(forHTTPHeaderField: "Content-Range")
        let totalLength = contentRange.flatMap { value -> Int64? in
            guard let slash = value.lastIndex(of: "/") else { return nil }
            return Int64(value[value.index(after: slash)...])
        }
        let expectedLength = httpResponse.expectedContentLength > 0 ? httpResponse.expectedContentLength : nil
        let contentLength = totalLength ?? expectedLength.map { requestedOffset + $0 }
        return (contentLength, httpResponse.mimeType)
    }
}
