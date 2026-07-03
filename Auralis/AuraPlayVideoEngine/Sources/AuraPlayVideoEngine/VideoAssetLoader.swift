import AVFoundation
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
              record.state == .available else {
            return nil
        }
        return record.localFileURL
    }
}

public enum VideoOfflineAssetKind: String, Codable, Equatable, Sendable {
    case progressiveFile
    case hlsPackage
}

public enum VideoOfflineDownloadState: String, Codable, Equatable, Sendable {
    case queued
    case downloading
    case available
    case failed
    case cancelled
}

public struct VideoOfflineAssetRecord: Codable, Equatable, Sendable {
    public let sourceURL: URL
    public var localFileURL: URL?
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
        self.kind = kind
        self.state = state
        self.progress = progress
        self.errorDescription = errorDescription
    }
}

public protocol VideoOfflineManifestStoring: Sendable {
    func record(for sourceURL: URL) async throws -> VideoOfflineAssetRecord?
    func upsert(_ record: VideoOfflineAssetRecord) async throws
    func allRecords() async throws -> [VideoOfflineAssetRecord]
}

public actor VideoOfflineManifestStore: VideoOfflineManifestStoring {
    private let manifestURL: URL
    private var records: [URL: VideoOfflineAssetRecord] = [:]

    public init(
        directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AuraPlayVideoEngine/Offline", isDirectory: true),
        fileManager: FileManager = .default
    ) {
        self.manifestURL = directory.appendingPathComponent("offline-manifest.json")
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: manifestURL),
           let decoded = try? JSONDecoder().decode([VideoOfflineAssetRecord].self, from: data) {
            self.records = Dictionary(uniqueKeysWithValues: decoded.map { ($0.sourceURL, $0) })
        }
    }

    public func record(for sourceURL: URL) async throws -> VideoOfflineAssetRecord? {
        records[sourceURL]
    }

    public func upsert(_ record: VideoOfflineAssetRecord) async throws {
        records[record.sourceURL] = record
        let data = try JSONEncoder().encode(Array(records.values))
        try data.write(to: manifestURL, options: [.atomic])
    }

    public func allRecords() async throws -> [VideoOfflineAssetRecord] {
        Array(records.values)
    }
}

public protocol VideoOfflineDownloading: Sendable {
    func downloadProgress(for sourceURL: URL) async -> AsyncStream<VideoOfflineAssetRecord>
    func startDownload(for sourceURL: URL) async throws
    func cancelDownload(for sourceURL: URL) async
}

public final class ProgressiveVideoOfflineDownloadManager: NSObject, VideoOfflineDownloading, URLSessionDownloadDelegate, @unchecked Sendable {
    private let manifestStore: VideoOfflineManifestStoring
    private let downloadDirectory: URL
    private var session: URLSession!
    private let lock = NSLock()
    private var continuations: [URL: [AsyncStream<VideoOfflineAssetRecord>.Continuation]] = [:]
    private var taskURLs: [Int: URL] = [:]

    public init(
        manifestStore: VideoOfflineManifestStoring,
        downloadDirectory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AuraPlayVideoEngine/Offline/Progressive", isDirectory: true),
        configuration: URLSessionConfiguration = .background(withIdentifier: "com.auraplay.video.offline.progressive")
    ) {
        self.manifestStore = manifestStore
        self.downloadDirectory = downloadDirectory
        try? FileManager.default.createDirectory(at: downloadDirectory, withIntermediateDirectories: true)
        super.init()
        self.session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    public convenience init(
        manifestStore: VideoOfflineManifestStoring,
        downloadDirectory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AuraPlayVideoEngine/Offline/Progressive", isDirectory: true)
    ) {
        let configuration = URLSessionConfiguration.background(withIdentifier: "com.auraplay.video.offline.progressive.\(UUID().uuidString)")
        self.init(manifestStore: manifestStore, downloadDirectory: downloadDirectory, configuration: configuration)
    }

    public func downloadProgress(for sourceURL: URL) async -> AsyncStream<VideoOfflineAssetRecord> {
        AsyncStream { continuation in
            lock.withLock {
                continuations[sourceURL, default: []].append(continuation)
            }
            Task {
                if let record = try? await manifestStore.record(for: sourceURL) {
                    continuation.yield(record)
                }
            }
        }
    }

    public func startDownload(for sourceURL: URL) async throws {
        let initial = VideoOfflineAssetRecord(sourceURL: sourceURL, kind: .progressiveFile, state: .downloading)
        try await manifestStore.upsert(initial)
        publish(initial)
        let task = session.downloadTask(with: sourceURL)
        lock.withLock {
            taskURLs[task.taskIdentifier] = sourceURL
        }
        task.resume()
    }

    public func cancelDownload(for sourceURL: URL) async {
        await session.allTasks.forEach { task in
            if self.lock.withLock({ self.taskURLs[task.taskIdentifier] == sourceURL }) {
                task.cancel()
            }
        }
        let record = VideoOfflineAssetRecord(sourceURL: sourceURL, kind: .progressiveFile, state: .cancelled)
        try? await manifestStore.upsert(record)
        publish(record)
    }

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let sourceURL = lock.withLock({ taskURLs[downloadTask.taskIdentifier] }) else { return }
        let progress = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0
        let record = VideoOfflineAssetRecord(sourceURL: sourceURL, kind: .progressiveFile, state: .downloading, progress: progress)
        Task {
            try? await manifestStore.upsert(record)
            publish(record)
        }
    }

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let sourceURL = lock.withLock({ taskURLs[downloadTask.taskIdentifier] }) else { return }
        let destination = downloadDirectory.appendingPathComponent(cacheKey(for: sourceURL)).appendingPathExtension(sourceURL.pathExtension.isEmpty ? "media" : sourceURL.pathExtension)
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            let record = VideoOfflineAssetRecord(sourceURL: sourceURL, localFileURL: destination, kind: .progressiveFile, state: .available, progress: 1)
            Task {
                try? await manifestStore.upsert(record)
                publish(record)
            }
        } catch {
            let record = VideoOfflineAssetRecord(sourceURL: sourceURL, kind: .progressiveFile, state: .failed, errorDescription: error.localizedDescription)
            Task {
                try? await manifestStore.upsert(record)
                publish(record)
            }
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error,
              let sourceURL = lock.withLock({ taskURLs.removeValue(forKey: task.taskIdentifier) }) else {
            return
        }
        let record = VideoOfflineAssetRecord(sourceURL: sourceURL, kind: .progressiveFile, state: .failed, errorDescription: error.localizedDescription)
        Task {
            try? await manifestStore.upsert(record)
            publish(record)
        }
    }

    private func publish(_ record: VideoOfflineAssetRecord) {
        let activeContinuations = lock.withLock { continuations[record.sourceURL] ?? [] }
        for continuation in activeContinuations {
            continuation.yield(record)
        }
    }

    private func cacheKey(for sourceURL: URL) -> String {
        Data(sourceURL.absoluteString.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
    }
}

#if !os(watchOS)
public final class HLSVideoOfflineDownloadManager: NSObject, VideoOfflineDownloading, AVAssetDownloadDelegate, @unchecked Sendable {
    private let manifestStore: VideoOfflineManifestStoring
    private var session: AVAssetDownloadURLSession!
    private let lock = NSLock()
    private var continuations: [URL: [AsyncStream<VideoOfflineAssetRecord>.Continuation]] = [:]
    private var taskURLs: [Int: URL] = [:]

    public init(
        manifestStore: VideoOfflineManifestStoring,
        configuration: URLSessionConfiguration = .background(withIdentifier: "com.auraplay.video.offline.hls")
    ) {
        self.manifestStore = manifestStore
        super.init()
        self.session = AVAssetDownloadURLSession(configuration: configuration, assetDownloadDelegate: self, delegateQueue: OperationQueue())
    }

    public func downloadProgress(for sourceURL: URL) async -> AsyncStream<VideoOfflineAssetRecord> {
        AsyncStream { continuation in
            lock.withLock {
                continuations[sourceURL, default: []].append(continuation)
            }
            Task {
                if let record = try? await manifestStore.record(for: sourceURL) {
                    continuation.yield(record)
                }
            }
        }
    }

    public func startDownload(for sourceURL: URL) async throws {
        let asset = AVURLAsset(url: sourceURL)
        guard let task = session.makeAssetDownloadTask(asset: asset, assetTitle: sourceURL.lastPathComponent, assetArtworkData: nil, options: nil) else {
            throw VideoPlaybackError.videoLoadFailed("Unable to create HLS download task")
        }
        let initial = VideoOfflineAssetRecord(sourceURL: sourceURL, kind: .hlsPackage, state: .downloading)
        try await manifestStore.upsert(initial)
        publish(initial)
        lock.withLock {
            taskURLs[task.taskIdentifier] = sourceURL
        }
        task.resume()
    }

    public func cancelDownload(for sourceURL: URL) async {
        await session.allTasks.forEach { task in
            if self.lock.withLock({ self.taskURLs[task.taskIdentifier] == sourceURL }) {
                task.cancel()
            }
        }
        let record = VideoOfflineAssetRecord(sourceURL: sourceURL, kind: .hlsPackage, state: .cancelled)
        try? await manifestStore.upsert(record)
        publish(record)
    }

    public func urlSession(
        _ session: URLSession,
        assetDownloadTask: AVAssetDownloadTask,
        didLoad timeRange: CMTimeRange,
        totalTimeRangesLoaded loadedTimeRanges: [NSValue],
        timeRangeExpectedToLoad: CMTimeRange
    ) {
        guard let sourceURL = lock.withLock({ taskURLs[assetDownloadTask.taskIdentifier] }) else { return }
        let loadedSeconds = loadedTimeRanges.map { $0.timeRangeValue.duration.seconds }.filter(\.isFinite).reduce(0, +)
        let expectedSeconds = timeRangeExpectedToLoad.duration.seconds
        let progress = expectedSeconds.isFinite && expectedSeconds > 0 ? min(loadedSeconds / expectedSeconds, 1) : 0
        let record = VideoOfflineAssetRecord(sourceURL: sourceURL, kind: .hlsPackage, state: .downloading, progress: progress)
        Task {
            try? await manifestStore.upsert(record)
            publish(record)
        }
    }

    public func urlSession(
        _ session: URLSession,
        assetDownloadTask: AVAssetDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let sourceURL = lock.withLock({ taskURLs[assetDownloadTask.taskIdentifier] }) else { return }
        let record = VideoOfflineAssetRecord(sourceURL: sourceURL, localFileURL: location, kind: .hlsPackage, state: .available, progress: 1)
        Task {
            try? await manifestStore.upsert(record)
            publish(record)
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error,
              let sourceURL = lock.withLock({ taskURLs.removeValue(forKey: task.taskIdentifier) }) else {
            return
        }
        let record = VideoOfflineAssetRecord(sourceURL: sourceURL, kind: .hlsPackage, state: .failed, errorDescription: error.localizedDescription)
        Task {
            try? await manifestStore.upsert(record)
            publish(record)
        }
    }

    private func publish(_ record: VideoOfflineAssetRecord) {
        let activeContinuations = lock.withLock { continuations[record.sourceURL] ?? [] }
        for continuation in activeContinuations {
            continuation.yield(record)
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
