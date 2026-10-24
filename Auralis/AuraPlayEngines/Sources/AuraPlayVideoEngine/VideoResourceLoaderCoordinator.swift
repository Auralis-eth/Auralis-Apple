import AVFoundation
import Foundation
import UniformTypeIdentifiers

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
    public let maxCacheBytes: Int64?

    /// Only URLs with these path extensions are routed through the progressive cache.
    /// Extensionless URLs (common on IPFS/Arweave gateways) can be HLS, which the
    /// byte-range resource loader cannot serve, so they play directly instead.
    public let progressiveFileExtensions: Set<String>

    public init(
        customScheme: String = "auraplay-video-cache",
        cacheDirectory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AuraPlayVideoEngine/ProgressiveCache", isDirectory: true),
        maxCacheBytes: Int64? = 2 * 1024 * 1024 * 1024,
        progressiveFileExtensions: Set<String> = ["mp4", "m4v", "mov"]
    ) {
        self.customScheme = customScheme
        self.cacheDirectory = cacheDirectory
        self.maxCacheBytes = maxCacheBytes
        self.progressiveFileExtensions = Set(progressiveFileExtensions.map { $0.lowercased() })
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
        return configuration.progressiveFileExtensions.contains(url.pathExtension.lowercased())
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
        // Overflow-checked: requests-to-end windows can carry `Int.max` lengths.
        let (requestEnd, overflow) = requestedOffset.addingReportingOverflow(Int64(requestedLength))
        return !overflow && offset <= requestedOffset && endOffset >= requestEnd
    }
}

public actor ProgressiveVideoCacheStore {
    private let configuration: ProgressiveVideoCacheConfiguration
    private let fileManager: FileManager
    private var records: [URL: ProgressiveVideoCacheRecord] = [:]
    private var recordsLoaded = false
    private var unenforcedWriteBytes: Int64 = 0

    /// Budget enforcement stats every cache file, so batch it instead of running per flush.
    private static let budgetEnforcementByteInterval: Int64 = 32 * 1024 * 1024

    public init(
        configuration: ProgressiveVideoCacheConfiguration = ProgressiveVideoCacheConfiguration(),
        fileManager: FileManager = .default
    ) {
        self.configuration = configuration
        self.fileManager = fileManager
    }

    public func record(for sourceURL: URL) async -> ProgressiveVideoCacheRecord? {
        try? loadRecordsIfNeeded()
        return records[sourceURL]
    }

    /// Returns the fully cached local file for `sourceURL`, if the cache is complete.
    ///
    /// This is a cache-inspection API. Do not pass the returned file URL to
    /// `VideoPlayerController.load(resolvedURL:)` — the controller validates
    /// HTTPS-only playback URLs. Keep loading through the original HTTPS URL;
    /// the progressive pipeline serves bytes from this cache automatically.
    public func localFileURL(for sourceURL: URL) async -> URL? {
        try? loadRecordsIfNeeded()
        guard records[sourceURL]?.isComplete == true else { return nil }
        let fileURL = dataFileURL(for: sourceURL)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            dropStaleRecord(for: sourceURL)
            return nil
        }
        return fileURL
    }

    public func cachedData(for sourceURL: URL, offset: Int64, length: Int) async throws -> Data? {
        try loadRecordsIfNeeded()
        guard let record = records[sourceURL], record.cachedRanges.contains(where: { $0.contains(offset: offset, length: length) }) else {
            return nil
        }
        return readCachedBytes(for: sourceURL, offset: offset, length: length)
    }

    /// Returns the cached bytes at the start of the requested window when only a
    /// prefix of it is cached, so callers can serve the prefix locally and fetch
    /// just the remainder from the network.
    public func cachedPrefixData(for sourceURL: URL, offset: Int64, maxLength: Int) async throws -> Data? {
        try loadRecordsIfNeeded()
        guard maxLength > 0,
              let record = records[sourceURL],
              let range = record.cachedRanges.first(where: { $0.offset <= offset && $0.endOffset > offset }) else {
            return nil
        }
        let length = Int(min(Int64(maxLength), range.endOffset - offset))
        return readCachedBytes(for: sourceURL, offset: offset, length: length)
    }

    private func readCachedBytes(for sourceURL: URL, offset: Int64, length: Int) -> Data? {
        let fileURL = dataFileURL(for: sourceURL)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            dropStaleRecord(for: sourceURL)
            return nil
        }
        do {
            let handle = try FileHandle(forReadingFrom: fileURL)
            defer { try? handle.close() }
            try handle.seek(toOffset: UInt64(offset))
            guard let data = try handle.read(upToCount: length), data.count == length else {
                return nil
            }
            return data
        } catch {
            // The system can purge or truncate Caches content at any time; treat
            // unreadable cache data as a miss so the caller refetches from the network.
            return nil
        }
    }

    private func dropStaleRecord(for sourceURL: URL) {
        records[sourceURL] = nil
        try? fileManager.removeItem(at: metadataFileURL(for: sourceURL))
    }

    public func store(
        data: Data,
        for sourceURL: URL,
        offset: Int64,
        contentLength: Int64?,
        contentType: String?
    ) async throws -> ProgressiveVideoCacheRecord {
        try loadRecordsIfNeeded()
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
        unenforcedWriteBytes += Int64(data.count)
        if record.isComplete || unenforcedWriteBytes >= Self.budgetEnforcementByteInterval {
            try enforceCacheBudget(excluding: sourceURL)
            unenforcedWriteBytes = 0
        }
        return record
    }

    /// Records content length/type learned from a response so later
    /// content-information requests and requests-to-end window resolution do not
    /// refetch from the network.
    public func registerContentInformation(
        for sourceURL: URL,
        contentLength: Int64?,
        contentType: String?
    ) async throws {
        try loadRecordsIfNeeded()
        var record = records[sourceURL] ?? ProgressiveVideoCacheRecord(sourceURL: sourceURL)
        record.contentLength = contentLength ?? record.contentLength
        record.contentType = contentType ?? record.contentType
        records[sourceURL] = record
        try fileManager.createDirectory(at: configuration.cacheDirectory, withIntermediateDirectories: true)
        try persist(record)
    }

    private func loadRecordsIfNeeded() throws {
        guard !recordsLoaded else { return }
        defer { recordsLoaded = true }
        try fileManager.createDirectory(at: configuration.cacheDirectory, withIntermediateDirectories: true)
        records = Self.loadRecordsFromDisk(configuration: configuration, fileManager: fileManager)
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

    private func enforceCacheBudget(excluding protectedSourceURL: URL) throws {
        guard let maxCacheBytes = configuration.maxCacheBytes, maxCacheBytes >= 0 else { return }
        var entries = records.values.map { record in
            CacheEntry(
                sourceURL: record.sourceURL,
                dataFileURL: dataFileURL(for: record.sourceURL),
                metadataFileURL: metadataFileURL(for: record.sourceURL),
                modifiedAt: modificationDate(for: record.sourceURL)
            )
        }
        var totalBytes = try entries.reduce(Int64(0)) { total, entry in
            try total + fileSize(at: entry.dataFileURL) + fileSize(at: entry.metadataFileURL)
        }
        guard totalBytes > maxCacheBytes else { return }

        entries.sort {
            if $0.modifiedAt == $1.modifiedAt {
                return $0.sourceURL.absoluteString < $1.sourceURL.absoluteString
            }
            return $0.modifiedAt < $1.modifiedAt
        }

        for entry in entries where entry.sourceURL != protectedSourceURL && totalBytes > maxCacheBytes {
            totalBytes -= try fileSize(at: entry.dataFileURL) + fileSize(at: entry.metadataFileURL)
            try? fileManager.removeItem(at: entry.dataFileURL)
            try? fileManager.removeItem(at: entry.metadataFileURL)
            records[entry.sourceURL] = nil
        }
    }

    private func modificationDate(for sourceURL: URL) -> Date {
        let metadataURL = metadataFileURL(for: sourceURL)
        return (try? fileManager.attributesOfItem(atPath: metadataURL.path)[.modificationDate] as? Date) ?? .distantPast
    }

    private func fileSize(at url: URL) throws -> Int64 {
        guard fileManager.fileExists(atPath: url.path) else { return 0 }
        return (try fileManager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
    }

    private func dataFileURL(for sourceURL: URL) -> URL {
        configuration.cacheDirectory.appendingPathComponent(CacheKey(url: sourceURL).rawValue).appendingPathExtension("media")
    }

    private func metadataFileURL(for sourceURL: URL) -> URL {
        configuration.cacheDirectory.appendingPathComponent(CacheKey(url: sourceURL).rawValue).appendingPathExtension("json")
    }

    private struct CacheEntry {
        let sourceURL: URL
        let dataFileURL: URL
        let metadataFileURL: URL
        let modifiedAt: Date
    }
}

public final class ProgressiveVideoResourceLoader: NSObject, VideoAssetResourceLoaderDelegate, @unchecked Sendable {
    private let store: ProgressiveVideoCacheStore
    private let mapper: ProgressiveVideoCacheURLMapper
    private let session: URLSession
    private let lock = NSLock()
    private var activeTasks: [ObjectIdentifier: ActiveResourceLoadTask] = [:]
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
        lock.withLock {
            activeTasks[requestID] = .starting
        }
        let task = Task { [weak self, loadingRequest] in
            guard let self else { return }
            await self.handle(loadingRequest, requestID: requestID)
        }
        lock.withLock {
            if case .starting = activeTasks[requestID] {
                activeTasks[requestID] = .running(task)
            } else {
                task.cancel()
            }
        }
        return true
    }

    public func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        let requestID = ObjectIdentifier(loadingRequest)
        let task = lock.withLock { activeTasks.removeValue(forKey: requestID)?.task }
        task?.cancel()
    }

    private func handle(_ loadingRequest: AVAssetResourceLoadingRequest, requestID: ObjectIdentifier) async {
        defer {
            _ = lock.withLock {
                activeTasks.removeValue(forKey: requestID)
            }
        }

        guard let assetURL = loadingRequest.request.url,
              let sourceURL = mapper.originalURL(for: assetURL) else {
            loadingRequest.finishLoading(with: VideoPlaybackError.resourceLoadingUnsupported)
            return
        }

        let requestedOffset = requestedOffset(for: loadingRequest)

        do {
            if Task.isCancelled { throw CancellationError() }

            // A request with no data request only needs content information; answering
            // it must not stream the whole remote file.
            if loadingRequest.dataRequest == nil {
                try await fulfillContentInformationOnly(sourceURL: sourceURL, loadingRequest: loadingRequest)
                return
            }

            // AVFoundation reports requests-to-end with `requestedLength == Int.max`,
            // which overflows any `offset + length` math. Resolve a concrete window
            // from the known content length when available; otherwise `nil` means
            // "stream open-ended to the end of the resource".
            let requestedLength: Int?
            if loadingRequest.dataRequest?.requestsAllDataToEndOfResource == true {
                if let contentLength = await store.record(for: sourceURL)?.contentLength,
                   contentLength > requestedOffset {
                    requestedLength = Int(contentLength - requestedOffset)
                } else {
                    requestedLength = nil
                }
            } else {
                requestedLength = max(loadingRequest.dataRequest?.requestedLength ?? 0, 0)
            }

            if let requestedLength, requestedLength > 0,
               let cached = (try? await store.cachedData(for: sourceURL, offset: requestedOffset, length: requestedLength)) ?? nil {
                if let record = await store.record(for: sourceURL) {
                    fillContentInformation(on: loadingRequest, record: record, fallbackLength: Int64(cached.count))
                }
                loadingRequest.dataRequest?.respond(with: cached)
                loadingRequest.finishLoading()
                return
            }

            // Serve any cached prefix of the window locally so only the remainder
            // is fetched from the network.
            var remainingOffset = requestedOffset
            var remainingLength = requestedLength
            if let prefix = (try? await store.cachedPrefixData(for: sourceURL, offset: requestedOffset, maxLength: requestedLength ?? Int.max)) ?? nil,
               !prefix.isEmpty {
                if let record = await store.record(for: sourceURL) {
                    fillContentInformation(on: loadingRequest, record: record, fallbackLength: Int64(prefix.count))
                }
                loadingRequest.dataRequest?.respond(with: prefix)
                remainingOffset += Int64(prefix.count)
                if let length = remainingLength {
                    remainingLength = length - prefix.count
                    if length - prefix.count <= 0 {
                        loadingRequest.finishLoading()
                        return
                    }
                }
            }

            try await streamRemoteRange(
                sourceURL: sourceURL,
                requestedOffset: remainingOffset,
                requestedLength: remainingLength,
                loadingRequest: loadingRequest
            )
        } catch is CancellationError {
            // AVFoundation owns cancelled loading requests; do not finish a request it cancelled.
        } catch {
            loadingRequest.finishLoading(with: error)
        }
    }

    private func fulfillContentInformationOnly(
        sourceURL: URL,
        loadingRequest: AVAssetResourceLoadingRequest
    ) async throws {
        if let record = await store.record(for: sourceURL), record.contentLength != nil {
            fillContentInformation(on: loadingRequest, record: record, fallbackLength: 0)
            loadingRequest.finishLoading()
            return
        }

        var request = URLRequest(url: sourceURL)
        request.setValue("bytes=0-1", forHTTPHeaderField: "Range")
        let bridge = DataChunkStreamingBridge()
        let task = session.dataTask(with: request)
        task.delegate = bridge
        do {
            try await withTaskCancellationHandler {
                defer { task.cancel() }
                task.resume()
                let response = try await bridge.waitForResponse()
                try validateRemoteResponse(response)
                let metadata = responseMetadata(from: response, requestedOffset: 0)
                let record = ProgressiveVideoCacheRecord(
                    sourceURL: sourceURL,
                    contentLength: metadata.contentLength,
                    contentType: metadata.contentType
                )
                // Remember the learned length/type so later content-information
                // requests and requests-to-end windows resolve without refetching.
                if metadata.contentLength != nil {
                    try? await store.registerContentInformation(
                        for: sourceURL,
                        contentLength: metadata.contentLength,
                        contentType: metadata.contentType
                    )
                }
                fillContentInformation(on: loadingRequest, record: record, fallbackLength: metadata.contentLength ?? 0)
                loadingRequest.finishLoading()
            } onCancel: {
                task.cancel()
            }
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw error
        }
    }

    private func streamRemoteRange(
        sourceURL: URL,
        requestedOffset: Int64,
        requestedLength: Int?,
        loadingRequest: AVAssetResourceLoadingRequest
    ) async throws {
        var request = URLRequest(url: sourceURL)
        if let requestedLength, requestedLength > 0 {
            // Overflow-checked: a misbehaving length must degrade to an
            // open-ended range, not trap.
            let (end, overflow) = requestedOffset.addingReportingOverflow(Int64(requestedLength) - 1)
            request.setValue(
                overflow ? "bytes=\(requestedOffset)-" : "bytes=\(requestedOffset)-\(end)",
                forHTTPHeaderField: "Range"
            )
        } else {
            request.setValue("bytes=\(requestedOffset)-", forHTTPHeaderField: "Range")
        }

        let bridge = DataChunkStreamingBridge()
        let task = session.dataTask(with: request)
        task.delegate = bridge
        do {
            try await withTaskCancellationHandler {
                task.resume()
                let response = try await bridge.waitForResponse()
                try validateRemoteResponse(response)
                // A server that ignores the Range header replies 200 and streams
                // from byte zero. Keep playback working: cache from zero and
                // forward only the requested window to AVFoundation.
                let streamStart: Int64 = (response as? HTTPURLResponse)?.statusCode == 200 ? 0 : requestedOffset
                let metadata = responseMetadata(from: response, requestedOffset: streamStart)
                let initialRecord = ProgressiveVideoCacheRecord(
                    sourceURL: sourceURL,
                    contentLength: metadata.contentLength,
                    contentType: metadata.contentType
                )
                fillContentInformation(on: loadingRequest, record: initialRecord, fallbackLength: metadata.contentLength ?? Int64(requestedLength ?? 0))

                var buffer = Data()
                buffer.reserveCapacity(streamChunkSize)
                var writeOffset = streamStart
                var respondedBytes = 0
                var lastRecord = initialRecord
                let windowFulfilled: () -> Bool = {
                    guard let requestedLength else { return false }
                    return respondedBytes >= requestedLength
                }

                for try await chunk in bridge.chunks {
                    try Task.checkCancellation()
                    buffer.append(chunk)
                    if buffer.count >= streamChunkSize {
                        let flushed = try await flush(
                            buffer,
                            sourceURL: sourceURL,
                            offset: writeOffset,
                            metadata: metadata,
                            loadingRequest: loadingRequest,
                            windowOffset: requestedOffset,
                            windowLength: requestedLength
                        )
                        lastRecord = flushed.record
                        respondedBytes += flushed.respondedBytes
                        writeOffset += Int64(buffer.count)
                        buffer.removeAll(keepingCapacity: true)
                        if windowFulfilled() { break }
                    }
                }
                try Task.checkCancellation()

                if !buffer.isEmpty {
                    let flushed = try await flush(
                        buffer,
                        sourceURL: sourceURL,
                        offset: writeOffset,
                        metadata: metadata,
                        loadingRequest: loadingRequest,
                        windowOffset: requestedOffset,
                        windowLength: requestedLength
                    )
                    lastRecord = flushed.record
                    respondedBytes += flushed.respondedBytes
                }

                if windowFulfilled() {
                    // Stop a range-ignoring server from streaming the rest of the file.
                    task.cancel()
                }
                fillContentInformation(on: loadingRequest, record: lastRecord, fallbackLength: metadata.contentLength ?? Int64(requestedLength ?? 0))
                loadingRequest.finishLoading()
            } onCancel: {
                task.cancel()
            }
        } catch {
            task.cancel()
            if Task.isCancelled { throw CancellationError() }
            throw error
        }
    }

    private func flush(
        _ data: Data,
        sourceURL: URL,
        offset: Int64,
        metadata: (contentLength: Int64?, contentType: String?),
        loadingRequest: AVAssetResourceLoadingRequest,
        windowOffset: Int64,
        windowLength: Int?
    ) async throws -> (record: ProgressiveVideoCacheRecord, respondedBytes: Int) {
        var respondedBytes = 0
        if let dataRequest = loadingRequest.dataRequest,
           let slice = windowedSlice(of: data, at: offset, windowOffset: windowOffset, windowLength: windowLength) {
            dataRequest.respond(with: slice)
            respondedBytes = slice.count
        }
        let record = try await store.store(
            data: data,
            for: sourceURL,
            offset: offset,
            contentLength: metadata.contentLength,
            contentType: metadata.contentType
        )
        return (record, respondedBytes)
    }

    /// Returns the portion of `data` (whose first byte sits at absolute resource
    /// `offset`) that falls inside the requested window, or nil when nothing
    /// overlaps. Bytes outside the window are cached but never forwarded, which
    /// keeps playback correct when a server ignores the Range header.
    func windowedSlice(of data: Data, at offset: Int64, windowOffset: Int64, windowLength: Int?) -> Data? {
        guard !data.isEmpty else { return nil }
        let dataEnd = offset + Int64(data.count)
        guard dataEnd > windowOffset else { return nil }

        var slice = data
        if offset < windowOffset {
            slice = slice.dropFirst(Int(windowOffset - offset))
        }
        if let windowLength {
            let (windowEnd, overflow) = windowOffset.addingReportingOverflow(Int64(windowLength))
            if !overflow, dataEnd > windowEnd {
                slice = slice.dropLast(Int(dataEnd - windowEnd))
            }
        }
        guard !slice.isEmpty else { return nil }
        return Data(slice)
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
        contentInformationRequest.contentType = contentTypeIdentifier(for: record)
        contentInformationRequest.contentLength = record.contentLength ?? fallbackLength
        contentInformationRequest.isByteRangeAccessSupported = true
    }

    func contentTypeIdentifier(for record: ProgressiveVideoCacheRecord) -> String {
        if let contentType = record.contentType {
            switch contentType.lowercased() {
            case "video/mp4", "application/mp4":
                return AVFileType.mp4.rawValue
            case "video/quicktime":
                return AVFileType.mov.rawValue
            default:
                break
            }
            if contentType.contains("/"), contentType.rangeOfCharacter(from: .whitespacesAndNewlines) == nil, let type = UTType(mimeType: contentType) {
                return type.identifier
            }
            if contentType.contains("."), contentType.rangeOfCharacter(from: .whitespacesAndNewlines) == nil, UTType(contentType) != nil {
                return contentType
            }
        }
        switch record.sourceURL.pathExtension.lowercased() {
        case "mp4", "m4v":
            return AVFileType.mp4.rawValue
        case "mov", "qt":
            return AVFileType.mov.rawValue
        default:
            break
        }
        if let type = UTType(filenameExtension: record.sourceURL.pathExtension) {
            return type.identifier
        }
        return AVFileType.mp4.rawValue
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

    /// Error responses fail the request. A 200 reply to a range request is not an
    /// error: the stream is treated as starting at byte zero and only the requested
    /// window is forwarded to AVFoundation.
    func validateRemoteResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        if httpResponse.statusCode >= 400 {
            throw VideoPlaybackError.videoLoadFailed("Progressive video request failed with HTTP \(httpResponse.statusCode).")
        }
    }
}

private enum ActiveResourceLoadTask {
    case starting
    case running(Task<Void, Never>)

    var task: Task<Void, Never>? {
        guard case .running(let task) = self else { return nil }
        return task
    }
}

/// Bridges URLSession data-task delegate callbacks into an awaitable response plus a
/// stream of `Data` chunks, so range downloads are consumed per URLSession buffer
/// instead of per byte.
private final class DataChunkStreamingBridge: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    let chunks: AsyncThrowingStream<Data, any Error>

    private let chunkContinuation: AsyncThrowingStream<Data, any Error>.Continuation
    private let lock = NSLock()
    private var response: URLResponse?
    private var completionError: (any Error)?
    private var didComplete = false
    private var responseContinuation: CheckedContinuation<URLResponse, any Error>?

    override init() {
        var continuation: AsyncThrowingStream<Data, any Error>.Continuation!
        self.chunks = AsyncThrowingStream(bufferingPolicy: .unbounded) { continuation = $0 }
        self.chunkContinuation = continuation
        super.init()
    }

    func waitForResponse() async throws -> URLResponse {
        try await withCheckedThrowingContinuation { continuation in
            let resumeAction: (() -> Void)? = lock.withLock {
                if let response {
                    return { continuation.resume(returning: response) }
                }
                if didComplete {
                    let error = completionError ?? URLError(.cancelled)
                    return { continuation.resume(throwing: error) }
                }
                responseContinuation = continuation
                return nil
            }
            resumeAction?()
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        let continuation = lock.withLock {
            self.response = response
            let continuation = responseContinuation
            responseContinuation = nil
            return continuation
        }
        continuation?.resume(returning: response)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        chunkContinuation.yield(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let continuation = lock.withLock {
            didComplete = true
            completionError = error
            let continuation = responseContinuation
            responseContinuation = nil
            return continuation
        }
        continuation?.resume(throwing: error ?? URLError(.cancelled))
        chunkContinuation.finish(throwing: error)
    }
}
