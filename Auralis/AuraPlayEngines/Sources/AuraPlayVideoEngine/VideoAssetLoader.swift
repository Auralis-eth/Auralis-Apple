import AVFoundation
import AuraPlayMediaCore
import Foundation

public struct VideoURLAssetConfiguration: Equatable, Sendable {
    public let preferPreciseDurationAndTiming: Bool

    public init(preferPreciseDurationAndTiming: Bool = false) {
        self.preferPreciseDurationAndTiming = preferPreciseDurationAndTiming
    }

    var avURLAssetOptions: [String: Any] {
        [AVURLAssetPreferPreciseDurationAndTimingKey: preferPreciseDurationAndTiming]
    }
}

public enum VideoAssetPreloadKey: Equatable, Sendable {
    case tracks
    case duration
    case commonMetadata
    case availableMediaCharacteristics
    case playable
}

public struct VideoAssetLoadPlan: Equatable, Sendable {
    public let configuration: VideoURLAssetConfiguration
    public let preloadKeys: [VideoAssetPreloadKey]

    public init(
        configuration: VideoURLAssetConfiguration = VideoURLAssetConfiguration(),
        preloadKeys: [VideoAssetPreloadKey] = [.tracks, .duration, .availableMediaCharacteristics, .playable]
    ) {
        self.configuration = configuration
        self.preloadKeys = preloadKeys
    }
}

public protocol VideoAssetResourceLoaderDelegate: AVAssetResourceLoaderDelegate, AnyObject, Sendable {}

public struct VideoURLAssetFactory: Sendable {
    public init() {}

    public func asset(
        for url: URL,
        configuration: VideoURLAssetConfiguration = VideoURLAssetConfiguration(),
        resourceLoaderDelegate: VideoAssetResourceLoaderDelegate? = nil,
        resourceLoaderQueue: DispatchQueue = .main
    ) -> AVURLAsset {
        let asset = AVURLAsset(url: url, options: configuration.avURLAssetOptions)
        if let resourceLoaderDelegate {
            asset.resourceLoader.setDelegate(resourceLoaderDelegate, queue: resourceLoaderQueue)
        }
        return asset
    }
}

public struct VideoAssetLoader: Sendable {
    private let factory: VideoURLAssetFactory
    private let urlMapper: any VideoAssetURLMapping
    private let offlineManifestStore: VideoOfflineManifestStoring?

    public init(
        factory: VideoURLAssetFactory = VideoURLAssetFactory(),
        urlMapper: any VideoAssetURLMapping = DirectVideoAssetURLMapper(),
        offlineManifestStore: VideoOfflineManifestStoring? = nil
    ) {
        self.factory = factory
        self.urlMapper = urlMapper
        self.offlineManifestStore = offlineManifestStore
    }

    public func asset(
        for url: URL,
        plan: VideoAssetLoadPlan = VideoAssetLoadPlan(),
        resourceLoaderDelegate: VideoAssetResourceLoaderDelegate? = nil,
        resourceLoaderQueue: DispatchQueue = .main
    ) async throws -> AVURLAsset {
        let playbackURL = await localPlaybackURL(for: url) ?? urlMapper.assetURL(for: url)
        let delegate = resourceLoaderDelegate ?? urlMapper.resourceLoaderDelegate
        let queue = resourceLoaderDelegate == nil ? urlMapper.resourceLoaderQueue : resourceLoaderQueue
        let asset = factory.asset(
            for: playbackURL,
            configuration: plan.configuration,
            resourceLoaderDelegate: delegate,
            resourceLoaderQueue: queue
        )
        try await preload(plan.preloadKeys, for: asset)
        return asset
    }

    public func playerItem(
        for url: URL,
        plan: VideoAssetLoadPlan = VideoAssetLoadPlan(),
        bufferingPolicy: VideoBufferingPolicy = VideoBufferingPolicy(),
        resourceLoaderDelegate: VideoAssetResourceLoaderDelegate? = nil,
        resourceLoaderQueue: DispatchQueue = .main
    ) async throws -> AVPlayerItem {
        let asset = try await asset(
            for: url,
            plan: plan,
            resourceLoaderDelegate: resourceLoaderDelegate,
            resourceLoaderQueue: resourceLoaderQueue
        )
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = bufferingPolicy.preferredForwardBufferDuration(for: url)
        return item
    }

    public func preload(_ keys: [VideoAssetPreloadKey], for asset: AVAsset) async throws {
        for key in keys {
            try await preload(key, for: asset)
        }
    }

    public func preload(_ key: VideoAssetPreloadKey, for asset: AVAsset) async throws {
        switch key {
        case .tracks:
            _ = try await asset.load(.tracks)
        case .duration:
            _ = try await asset.load(.duration)
        case .commonMetadata:
            _ = try await asset.load(.commonMetadata)
        case .availableMediaCharacteristics:
            _ = try await asset.load(.availableMediaCharacteristicsWithMediaSelectionOptions)
        case .playable:
            _ = try await asset.load(.isPlayable)
        }
    }

    private func localPlaybackURL(for sourceURL: URL) async -> URL? {
        guard let offlineManifestStore,
              let record = try? await offlineManifestStore.record(for: sourceURL),
              record.state == .available,
              let localFileURL = record.localFileURL,
              FileManager.default.fileExists(atPath: localFileURL.path) else {
            return nil
        }
        return localFileURL
    }
}

public enum VideoOfflineAssetKind: String, Codable, Equatable, Sendable {
    case progressiveFile
    case hlsPackage
}

public typealias VideoOfflineDownloadState = MediaOfflineState

public struct VideoOfflineAssetRecord: Codable, Equatable, Sendable {
    public let sourceURL: URL
    public var localFileURL: URL?
    fileprivate var localFileRelativePath: String?
    fileprivate var localFileBookmarkData: Data?
    public var kind: VideoOfflineAssetKind
    public var state: VideoOfflineDownloadState
    public var progress: Double
    public var errorDescription: String?

    public init(
        sourceURL: URL,
        localFileURL: URL? = nil,
        kind: VideoOfflineAssetKind,
        state: VideoOfflineDownloadState = .queued,
        progress: Double = 0,
        errorDescription: String? = nil
    ) {
        self.sourceURL = sourceURL
        self.localFileURL = localFileURL
        self.localFileRelativePath = nil
        self.localFileBookmarkData = nil
        self.kind = kind
        self.state = state
        self.progress = progress
        self.errorDescription = errorDescription
    }

    public static func == (lhs: VideoOfflineAssetRecord, rhs: VideoOfflineAssetRecord) -> Bool {
        lhs.sourceURL == rhs.sourceURL
            && lhs.localFileURL == rhs.localFileURL
            && lhs.kind == rhs.kind
            && lhs.state == rhs.state
            && lhs.progress == rhs.progress
            && lhs.errorDescription == rhs.errorDescription
    }
}

public protocol VideoOfflineManifestStoring: Sendable {
    func record(for sourceURL: URL) async throws -> VideoOfflineAssetRecord?
    func upsert(_ record: VideoOfflineAssetRecord) async throws
    func allRecords() async throws -> [VideoOfflineAssetRecord]
}

public actor VideoOfflineManifestStore: VideoOfflineManifestStoring {
    private let directory: URL
    private let manifestURL: URL
    private let fileManager: FileManager
    private var records: [URL: VideoOfflineAssetRecord] = [:]
    private var recordsLoaded = false

    public init(
        directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AuraPlayVideoEngine/Offline", isDirectory: true),
        fileManager: FileManager = .default
    ) {
        self.directory = directory
        self.manifestURL = directory.appendingPathComponent("offline-manifest.json")
        self.fileManager = fileManager
    }

    public func record(for sourceURL: URL) async throws -> VideoOfflineAssetRecord? {
        try loadRecordsIfNeeded()
        return records[sourceURL]
    }

    public func upsert(_ record: VideoOfflineAssetRecord) async throws {
        try loadRecordsIfNeeded()
        if let existing = records[record.sourceURL],
           !Self.shouldApply(record, over: existing) {
            return
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        records[record.sourceURL] = Self.resolvedRecord(record, directory: directory)
        let data = try JSONEncoder().encode(records.values.map {
            Self.recordForPersistence($0, directory: directory)
        })
        try data.write(to: manifestURL, options: [.atomic])
    }

    public func allRecords() async throws -> [VideoOfflineAssetRecord] {
        try loadRecordsIfNeeded()
        return Array(records.values)
    }

    private func loadRecordsIfNeeded() throws {
        guard !recordsLoaded else { return }
        // Mark loaded only after a successful read: a transient directory or read
        // failure must throw and be retried, not silently treat the manifest as
        // empty and let a later upsert rewrite it with a single record.
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: manifestURL.path) {
            let data = try Data(contentsOf: manifestURL)
            // An undecodable manifest is unrecoverable; start fresh.
            if let decoded = try? JSONDecoder().decode([VideoOfflineAssetRecord].self, from: data) {
                records = Dictionary(uniqueKeysWithValues: decoded.map {
                    let resolvedRecord = Self.resolvedRecord($0, directory: directory)
                    return (resolvedRecord.sourceURL, resolvedRecord)
                })
            }
        }
        recordsLoaded = true
    }

    private static func resolvedRecord(_ record: VideoOfflineAssetRecord, directory: URL) -> VideoOfflineAssetRecord {
        guard record.localFileURL == nil else {
            return record
        }
        if let relativePath = record.localFileRelativePath {
            var resolved = record
            resolved.localFileURL = directory.appendingPathComponent(relativePath)
            return resolved
        }
        var bookmarkDataIsStale = false
        if let bookmarkData = record.localFileBookmarkData,
           let bookmarkURL = try? URL(resolvingBookmarkData: bookmarkData, bookmarkDataIsStale: &bookmarkDataIsStale),
           !bookmarkDataIsStale {
            var resolved = record
            resolved.localFileURL = bookmarkURL
            return resolved
        }
        return record
    }

    private static func recordForPersistence(_ record: VideoOfflineAssetRecord, directory: URL) -> VideoOfflineAssetRecord {
        guard let localFileURL = record.localFileURL else {
            return record
        }
        var persisted = record
        if let relativePath = relativePath(for: localFileURL, relativeTo: directory) {
            persisted.localFileURL = nil
            persisted.localFileRelativePath = relativePath
            persisted.localFileBookmarkData = nil
            return persisted
        }
        if let bookmarkData = try? localFileURL.bookmarkData() {
            persisted.localFileURL = nil
            persisted.localFileRelativePath = nil
            persisted.localFileBookmarkData = bookmarkData
        }
        return persisted
    }

    private static func relativePath(for fileURL: URL, relativeTo directory: URL) -> String? {
        let directoryPath = directory.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        let prefix = directoryPath.hasSuffix("/") ? directoryPath : directoryPath + "/"
        guard filePath.hasPrefix(prefix) else { return nil }
        return String(filePath.dropFirst(prefix.count))
    }

    private static func shouldApply(_ candidate: VideoOfflineAssetRecord, over existing: VideoOfflineAssetRecord) -> Bool {
        if existing.state == .cancelled, candidate.state == .failed {
            return false
        }
        if existing.state.isTerminalOrAvailable, candidate.state == .downloading, candidate.progress > 0 {
            return false
        }
        return true
    }
}

struct VideoOfflineDownloadCompletionRecord {
    static func record(
        for error: Error,
        sourceURL: URL,
        kind: VideoOfflineAssetKind
    ) -> VideoOfflineAssetRecord {
        if isCancellation(error) {
            return VideoOfflineAssetRecord(sourceURL: sourceURL, kind: kind, state: .cancelled)
        }

        return VideoOfflineAssetRecord(
            sourceURL: sourceURL,
            kind: kind,
            state: .failed,
            errorDescription: error.localizedDescription
        )
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if (error as? URLError)?.code == .cancelled {
            return true
        }

        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
}

private extension VideoOfflineDownloadState {
    var isTerminalOrAvailable: Bool {
        switch self {
        case .available, .failed, .cancelled:
            true
        case .queued, .downloading:
            false
        }
    }
}

public protocol VideoOfflineDownloading: Sendable {
    func downloadProgress(for sourceURL: URL) async -> AsyncStream<VideoOfflineAssetRecord>
    func startDownload(for sourceURL: URL) async throws
    func cancelDownload(for sourceURL: URL) async
}

public final class ProgressiveVideoOfflineDownloadManager: NSObject, VideoOfflineDownloading, URLSessionDownloadDelegate, @unchecked Sendable {
    public static let defaultBackgroundSessionIdentifier = "com.auraplay.video.offline.progressive"

    private let manifestStore: VideoOfflineManifestStoring
    private let downloadDirectory: URL
    private var persistQueue: Task<Void, Never>?
    private let backgroundSessionIdentifier: String?
    private var session: URLSession!
    private let lock = NSLock()
    private var continuations: [URL: [UUID: AsyncStream<VideoOfflineAssetRecord>.Continuation]] = [:]
    private var taskURLs: [Int: URL] = [:]
    private var backgroundEventsCompletionHandler: (@Sendable () -> Void)?

    public init(
        manifestStore: VideoOfflineManifestStoring,
        downloadDirectory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AuraPlayVideoEngine/Offline/Progressive", isDirectory: true),
        backgroundSessionIdentifier: String
    ) {
        let configuration = URLSessionConfiguration.background(withIdentifier: backgroundSessionIdentifier)
        self.manifestStore = manifestStore
        self.downloadDirectory = downloadDirectory
        self.backgroundSessionIdentifier = configuration.identifier
        try? FileManager.default.createDirectory(at: downloadDirectory, withIntermediateDirectories: true)
        Self.excludeFromBackup(downloadDirectory)
        super.init()
        self.session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    public init(
        manifestStore: VideoOfflineManifestStoring,
        downloadDirectory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AuraPlayVideoEngine/Offline/Progressive", isDirectory: true),
        configuration: URLSessionConfiguration
    ) {
        self.manifestStore = manifestStore
        self.downloadDirectory = downloadDirectory
        self.backgroundSessionIdentifier = configuration.identifier
        try? FileManager.default.createDirectory(at: downloadDirectory, withIntermediateDirectories: true)
        Self.excludeFromBackup(downloadDirectory)
        super.init()
        self.session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    public func downloadProgress(for sourceURL: URL) async -> AsyncStream<VideoOfflineAssetRecord> {
        AsyncStream(bufferingPolicy: .bufferingNewest(20)) { continuation in
            let continuationID = UUID()
            lock.withLock {
                continuations[sourceURL, default: [:]][continuationID] = continuation
            }
            continuation.onTermination = { [weak self] _ in
                self?.removeContinuation(id: continuationID, for: sourceURL)
            }
            Task {
                if let record = try? await manifestStore.record(for: sourceURL) {
                    continuation.yield(record)
                }
            }
        }
    }

    public func startDownload(for sourceURL: URL) async throws {
        if lock.withLock({ taskURLs.values.contains(sourceURL) }) {
            return
        }
        let initial = VideoOfflineAssetRecord(sourceURL: sourceURL, kind: .progressiveFile, state: .downloading)
        let task = session.downloadTask(with: sourceURL)
        let shouldStart = lock.withLock {
            guard !taskURLs.values.contains(sourceURL) else { return false }
            taskURLs[task.taskIdentifier] = sourceURL
            return true
        }
        guard shouldStart else {
            task.cancel()
            return
        }
        do {
            try await manifestStore.upsert(initial)
        } catch {
            lock.withLock {
                taskURLs[task.taskIdentifier] = nil
            }
            task.cancel()
            throw error
        }
        publish(initial)
        task.resume()
    }

    public func cancelDownload(for sourceURL: URL) async {
        await session.allTasks.forEach { task in
            if self.sourceURL(for: task) == sourceURL {
                task.cancel()
            }
        }
        let record = VideoOfflineAssetRecord(sourceURL: sourceURL, kind: .progressiveFile, state: .cancelled)
        try? await manifestStore.upsert(record)
        publish(record)
    }

    @discardableResult
    public func handleEventsForBackgroundURLSession(
        identifier: String,
        completionHandler: @escaping @Sendable () -> Void
    ) -> Bool {
        guard identifier == backgroundSessionIdentifier else { return false }
        lock.withLock {
            backgroundEventsCompletionHandler = completionHandler
        }
        return true
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let completionHandler = lock.withLock {
            let completionHandler = backgroundEventsCompletionHandler
            backgroundEventsCompletionHandler = nil
            return completionHandler
        }
        guard let completionHandler else { return }
        DispatchQueue.main.async {
            completionHandler()
        }
    }

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let sourceURL = sourceURL(for: downloadTask) else { return }
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        let record = VideoOfflineAssetRecord(sourceURL: sourceURL, kind: .progressiveFile, state: .downloading, progress: progress)
        persistAndPublish(record)
    }

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let sourceURL = sourceURL(for: downloadTask) else { return }
        let destination = downloadDirectory
            .appendingPathComponent(CacheKey(url: sourceURL).rawValue)
            .appendingPathExtension(sourceURL.pathExtension.isEmpty ? "media" : sourceURL.pathExtension)
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            Self.excludeFromBackup(destination)
            let record = VideoOfflineAssetRecord(sourceURL: sourceURL, localFileURL: destination, kind: .progressiveFile, state: .available, progress: 1)
            persistAndPublish(record)
        } catch {
            let record = VideoOfflineAssetRecord(sourceURL: sourceURL, kind: .progressiveFile, state: .failed, errorDescription: error.localizedDescription)
            persistAndPublish(record)
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let sourceURL = lock.withLock({ taskURLs.removeValue(forKey: task.taskIdentifier) }) ?? task.originalRequest?.url else {
            return
        }
        guard let error else { return }
        let record = VideoOfflineDownloadCompletionRecord.record(
            for: error,
            sourceURL: sourceURL,
            kind: .progressiveFile
        )
        persistAndPublish(record)
    }

    private func publish(_ record: VideoOfflineAssetRecord) {
        let activeContinuations = lock.withLock {
            let activeContinuations = continuations[record.sourceURL].map { Array($0.values) } ?? []
            if record.state.isTerminalOrAvailable {
                continuations[record.sourceURL] = nil
            }
            return activeContinuations
        }
        for continuation in activeContinuations {
            continuation.yield(record)
            if record.state.isTerminalOrAvailable {
                continuation.finish()
            }
        }
    }

    // Chains writes so records reach the manifest and observers in emission order.
    private func persistAndPublish(_ record: VideoOfflineAssetRecord) {
        lock.withLock {
            let previous = persistQueue
            persistQueue = Task { [manifestStore, weak self] in
                await previous?.value
                try? await manifestStore.upsert(record)
                self?.publish(record)
            }
        }
    }

    private func sourceURL(for task: URLSessionTask) -> URL? {
        lock.withLock {
            if let sourceURL = taskURLs[task.taskIdentifier] {
                return sourceURL
            }
            guard let sourceURL = task.originalRequest?.url else { return nil }
            taskURLs[task.taskIdentifier] = sourceURL
            return sourceURL
        }
    }

    private func removeContinuation(id: UUID, for sourceURL: URL) {
        lock.withLock {
            continuations[sourceURL]?[id] = nil
            if continuations[sourceURL]?.isEmpty == true {
                continuations[sourceURL] = nil
            }
        }
    }

    // Downloads are re-fetchable media and must not count against the user's backup.
    private static func excludeFromBackup(_ url: URL) {
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var excludedURL = url
        try? excludedURL.setResourceValues(resourceValues)
    }
}

#if !os(watchOS)
public final class HLSVideoOfflineDownloadManager: NSObject, VideoOfflineDownloading, AVAssetDownloadDelegate, @unchecked Sendable {
    public static let defaultBackgroundSessionIdentifier = "com.auraplay.video.offline.hls"

    private let manifestStore: VideoOfflineManifestStoring
    private var persistQueue: Task<Void, Never>?
    private let backgroundSessionIdentifier: String?
    private var session: AVAssetDownloadURLSession!
    private let lock = NSLock()
    private var continuations: [URL: [UUID: AsyncStream<VideoOfflineAssetRecord>.Continuation]] = [:]
    private var taskURLs: [Int: URL] = [:]
    private var backgroundEventsCompletionHandler: (@Sendable () -> Void)?

    public init(
        manifestStore: VideoOfflineManifestStoring,
        backgroundSessionIdentifier: String
    ) {
        let configuration = URLSessionConfiguration.background(withIdentifier: backgroundSessionIdentifier)
        self.manifestStore = manifestStore
        self.backgroundSessionIdentifier = configuration.identifier
        super.init()
        self.session = AVAssetDownloadURLSession(configuration: configuration, assetDownloadDelegate: self, delegateQueue: OperationQueue())
    }

    /// - Parameter configuration: Must be a background configuration
    ///   (`URLSessionConfiguration.background(withIdentifier:)`); AVFoundation
    ///   raises an Objective-C exception for any other kind.
    public init(
        manifestStore: VideoOfflineManifestStoring,
        configuration: URLSessionConfiguration
    ) {
        precondition(
            configuration.identifier != nil,
            "HLSVideoOfflineDownloadManager requires a background URLSessionConfiguration created with URLSessionConfiguration.background(withIdentifier:)."
        )
        self.manifestStore = manifestStore
        self.backgroundSessionIdentifier = configuration.identifier
        super.init()
        self.session = AVAssetDownloadURLSession(configuration: configuration, assetDownloadDelegate: self, delegateQueue: OperationQueue())
    }

    public func downloadProgress(for sourceURL: URL) async -> AsyncStream<VideoOfflineAssetRecord> {
        AsyncStream(bufferingPolicy: .bufferingNewest(20)) { continuation in
            let continuationID = UUID()
            lock.withLock {
                continuations[sourceURL, default: [:]][continuationID] = continuation
            }
            continuation.onTermination = { [weak self] _ in
                self?.removeContinuation(id: continuationID, for: sourceURL)
            }
            Task {
                if let record = try? await manifestStore.record(for: sourceURL) {
                    continuation.yield(record)
                }
            }
        }
    }

    public func startDownload(for sourceURL: URL) async throws {
        if lock.withLock({ taskURLs.values.contains(sourceURL) }) {
            return
        }
        let asset = AVURLAsset(url: sourceURL)
        guard let task = session.makeAssetDownloadTask(asset: asset, assetTitle: sourceURL.lastPathComponent, assetArtworkData: nil, options: nil) else {
            throw VideoPlaybackError.videoLoadFailed("Unable to create HLS download task")
        }
        let initial = VideoOfflineAssetRecord(sourceURL: sourceURL, kind: .hlsPackage, state: .downloading)
        let shouldStart = lock.withLock {
            guard !taskURLs.values.contains(sourceURL) else { return false }
            taskURLs[task.taskIdentifier] = sourceURL
            return true
        }
        guard shouldStart else {
            task.cancel()
            return
        }
        do {
            try await manifestStore.upsert(initial)
        } catch {
            lock.withLock {
                taskURLs[task.taskIdentifier] = nil
            }
            task.cancel()
            throw error
        }
        publish(initial)
        task.resume()
    }

    public func cancelDownload(for sourceURL: URL) async {
        await session.allTasks.forEach { task in
            if self.sourceURL(for: task) == sourceURL {
                task.cancel()
            }
        }
        let record = VideoOfflineAssetRecord(sourceURL: sourceURL, kind: .hlsPackage, state: .cancelled)
        try? await manifestStore.upsert(record)
        publish(record)
    }

    @discardableResult
    public func handleEventsForBackgroundURLSession(
        identifier: String,
        completionHandler: @escaping @Sendable () -> Void
    ) -> Bool {
        guard identifier == backgroundSessionIdentifier else { return false }
        lock.withLock {
            backgroundEventsCompletionHandler = completionHandler
        }
        return true
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let completionHandler = lock.withLock {
            let completionHandler = backgroundEventsCompletionHandler
            backgroundEventsCompletionHandler = nil
            return completionHandler
        }
        guard let completionHandler else { return }
        DispatchQueue.main.async {
            completionHandler()
        }
    }

    public func urlSession(
        _ session: URLSession,
        assetDownloadTask: AVAssetDownloadTask,
        didLoad timeRange: CMTimeRange,
        totalTimeRangesLoaded loadedTimeRanges: [NSValue],
        timeRangeExpectedToLoad: CMTimeRange
    ) {
        guard let sourceURL = sourceURL(for: assetDownloadTask) else { return }
        let loadedSeconds = loadedTimeRanges.map { $0.timeRangeValue.duration.seconds }.filter(\.isFinite).reduce(0, +)
        let expectedSeconds = timeRangeExpectedToLoad.duration.seconds
        guard expectedSeconds.isFinite, expectedSeconds > 0 else { return }
        let progress = min(loadedSeconds / expectedSeconds, 1)
        let record = VideoOfflineAssetRecord(sourceURL: sourceURL, kind: .hlsPackage, state: .downloading, progress: progress)
        persistAndPublish(record)
    }

    public func urlSession(
        _ session: URLSession,
        assetDownloadTask: AVAssetDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let sourceURL = sourceURL(for: assetDownloadTask) else { return }
        let record = VideoOfflineAssetRecord(sourceURL: sourceURL, localFileURL: location, kind: .hlsPackage, state: .available, progress: 1)
        persistAndPublish(record)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let fallbackSourceURL = (task as? AVAssetDownloadTask)?.urlAsset.url
        guard let sourceURL = lock.withLock({ taskURLs.removeValue(forKey: task.taskIdentifier) }) ?? fallbackSourceURL else {
            return
        }
        guard let error else { return }
        let record = VideoOfflineDownloadCompletionRecord.record(
            for: error,
            sourceURL: sourceURL,
            kind: .hlsPackage
        )
        persistAndPublish(record)
    }

    private func publish(_ record: VideoOfflineAssetRecord) {
        let activeContinuations = lock.withLock {
            let activeContinuations = continuations[record.sourceURL].map { Array($0.values) } ?? []
            if record.state.isTerminalOrAvailable {
                continuations[record.sourceURL] = nil
            }
            return activeContinuations
        }
        for continuation in activeContinuations {
            continuation.yield(record)
            if record.state.isTerminalOrAvailable {
                continuation.finish()
            }
        }
    }

    // Chains writes so records reach the manifest and observers in emission order.
    private func persistAndPublish(_ record: VideoOfflineAssetRecord) {
        lock.withLock {
            let previous = persistQueue
            persistQueue = Task { [manifestStore, weak self] in
                await previous?.value
                try? await manifestStore.upsert(record)
                self?.publish(record)
            }
        }
    }

    private func sourceURL(for task: URLSessionTask) -> URL? {
        lock.withLock {
            if let sourceURL = taskURLs[task.taskIdentifier] {
                return sourceURL
            }
            guard let sourceURL = (task as? AVAssetDownloadTask)?.urlAsset.url else { return nil }
            taskURLs[task.taskIdentifier] = sourceURL
            return sourceURL
        }
    }

    private func removeContinuation(id: UUID, for sourceURL: URL) {
        lock.withLock {
            continuations[sourceURL]?[id] = nil
            if continuations[sourceURL]?.isEmpty == true {
                continuations[sourceURL] = nil
            }
        }
    }
}
#endif

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
