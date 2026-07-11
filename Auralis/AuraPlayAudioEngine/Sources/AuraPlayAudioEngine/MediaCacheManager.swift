import AuraPlayMediaCore
import Foundation

public actor MediaCacheManager: MediaCacheManaging {
    public nonisolated var progress: AsyncStream<CacheProgress> {
        progressBroadcast.stream()
    }

    public nonisolated var loudnessMeasurements: AsyncStream<CachedLoudnessMeasurement> {
        loudnessBroadcast.stream()
    }

    private let cacheDirectory: URL
    private let indexURL: URL
    private let diskCapBytes: Int64
    private let fileManager: FileManager
    private let downloader: any MediaDownloading
    private let resolver: any MediaURLResolving
    private let gatewayFallbackResolver: (any MediaGatewayFallbackResolving)?
    private let networkStatusProvider: any NetworkStatusProviding
    private let loudnessAnalyzer: ApproximateLoudnessAnalyzer
    private nonisolated let progressBroadcast = AsyncBroadcast<CacheProgress>()
    private nonisolated let loudnessBroadcast = AsyncBroadcast<CachedLoudnessMeasurement>()
    private var index: [String: CacheEntry]
    private var inFlightDownloads: [String: InFlightDownload] = [:]
    private var activeReaderCounts: [String: Int] = [:]

    public init(
        cacheDirectory: URL? = nil,
        diskCapBytes: Int64 = 1_000_000_000,
        fileManager: FileManager = .default,
        downloader: any MediaDownloading = URLSessionMediaDownloader(),
        resolver: any MediaURLResolving = GatewayMediaURLResolver(),
        gatewayFallbackResolver: (any MediaGatewayFallbackResolving)? = nil,
        networkStatusProvider: any NetworkStatusProviding = AlwaysOnlineNetworkStatusProvider(),
        loudnessAnalyzer: ApproximateLoudnessAnalyzer = ApproximateLoudnessAnalyzer()
    ) throws {
        self.fileManager = fileManager
        self.diskCapBytes = diskCapBytes
        self.downloader = downloader
        self.resolver = resolver
        self.gatewayFallbackResolver = gatewayFallbackResolver
        self.networkStatusProvider = networkStatusProvider
        self.loudnessAnalyzer = loudnessAnalyzer

        let baseDirectory = cacheDirectory ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "AuraPlayAudioEngine", directoryHint: .isDirectory)
        self.cacheDirectory = baseDirectory
        self.indexURL = baseDirectory.appending(path: "index.json")

        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)

        self.index = Self.loadIndex(from: indexURL)
    }

    deinit {
        progressBroadcast.finish()
        loudnessBroadcast.finish()
    }

    public func localFile<M: AuraPlayableMedia>(for media: M) async throws -> URL {
        let erased = AnyAuraPlayableMedia(media)
        let key = CacheKey(mediaID: erased.id).rawValue
        let fingerprint = cacheFingerprint(for: erased)

        if let cachedURL = validatedCompleteCachedURL(forKey: key, fingerprint: fingerprint) {
            markAccessed(key: key)
            return cachedURL
        }

        guard !networkStatusProvider.isOffline else {
            throw AuraPlayError.mediaUnavailableOffline
        }

        if let inFlight = inFlightDownloads[key] {
            if inFlight.fingerprint == fingerprint {
                return try await finalURL(for: inFlight)
            }
            _ = try? await finalURL(for: inFlight)
        }

        if let partialTask = resumableTaskIfAvailable(for: erased, key: key, fingerprint: fingerprint) {
            inFlightDownloads[key] = InFlightDownload(fingerprint: fingerprint, kind: .complete(partialTask))
            do {
                let url = try await partialTask.value
                inFlightDownloads[key] = nil
                return url
            } catch {
                inFlightDownloads[key] = nil
                throw error
            }
        }

        let task = Task<URL, Error> {
            try await download(erased, key: key, fingerprint: fingerprint)
        }
        inFlightDownloads[key] = InFlightDownload(fingerprint: fingerprint, kind: .complete(task))

        do {
            let url = try await task.value
            inFlightDownloads[key] = nil
            return url
        } catch {
            inFlightDownloads[key] = nil
            throw error
        }
    }

    public func localFileWhenPlayable<M: AuraPlayableMedia>(for media: M, minimumPlayableBytes: Int64 = 512_000) async throws -> URL {
        let erased = AnyAuraPlayableMedia(media)
        let key = CacheKey(mediaID: erased.id).rawValue
        let fingerprint = cacheFingerprint(for: erased)

        if let cachedURL = validatedCompleteCachedURL(forKey: key, fingerprint: fingerprint) {
            markAccessed(key: key)
            return cachedURL
        }

        if let partialURL = try playablePartialURL(forKey: key, fingerprint: fingerprint, declaredFormat: fingerprint.declaredFormat) {
            markAccessed(key: key)
            return partialURL
        }

        guard !networkStatusProvider.isOffline else {
            throw AuraPlayError.mediaUnavailableOffline
        }

        guard let progressiveDownloader = downloader as? any ProgressiveMediaDownloading else {
            return try await localFile(for: erased)
        }

        if let inFlight = inFlightDownloads[key] {
            if inFlight.fingerprint == fingerprint {
                return try await playableURL(for: inFlight)
            }
            _ = try? await finalURL(for: inFlight)
        }

        let task = Task<ProgressiveCacheDownload, Error> {
            try await self.startProgressiveDownload(
                erased,
                key: key,
                fingerprint: fingerprint,
                progressiveDownloader: progressiveDownloader,
                minimumPlayableBytes: minimumPlayableBytes
            )
        }
        inFlightDownloads[key] = InFlightDownload(fingerprint: fingerprint, kind: .progressive(task))

        do {
            let download = try await task.value
            return download.playableURL
        } catch {
            inFlightDownloads[key] = nil
            throw error
        }
    }

    public func isCached<M: AuraPlayableMedia>(_ media: M) async -> Bool {
        let erased = AnyAuraPlayableMedia(media)
        let key = CacheKey(mediaID: erased.id).rawValue
        let fingerprint = cacheFingerprint(for: erased)
        return validatedCompleteCachedURL(forKey: key, fingerprint: fingerprint) != nil
    }

    public func prefetch<M: AuraPlayableMedia>(_ media: M) async {
        let erased = AnyAuraPlayableMedia(media)
        Task { [weak self] in
            _ = try? await self?.localFile(for: erased)
        }
    }

    public func pin<M: AuraPlayableMedia>(_ media: M) async throws {
        let erased = AnyAuraPlayableMedia(media)
        let key = CacheKey(mediaID: erased.id).rawValue
        let fingerprint = cacheFingerprint(for: erased)
        if !isCompleteCacheEntry(key, matching: fingerprint) {
            _ = try await localFile(for: erased)
        }
        index[key]?.isPinned = true
        index[key]?.state = AuraCachedFileState.pinned.rawValue
        try persistIndex()
    }

    public func unpin<M: AuraPlayableMedia>(_ media: M) async throws {
        let key = CacheKey(mediaID: media.id).rawValue
        index[key]?.isPinned = false
        index[key]?.state = AuraCachedFileState.cached.rawValue
        try persistIndex()
    }

    public func beginReading<M: AuraPlayableMedia>(_ media: M) {
        let key = CacheKey(mediaID: media.id).rawValue
        activeReaderCounts[key, default: 0] += 1
    }

    public func endReading<M: AuraPlayableMedia>(_ media: M) {
        let key = CacheKey(mediaID: media.id).rawValue
        let nextCount = max(0, activeReaderCounts[key, default: 0] - 1)
        activeReaderCounts[key] = nextCount == 0 ? nil : nextCount
    }

    private func validatedCompleteCachedURL(forKey key: String, fingerprint: CacheFingerprint) -> URL? {
        guard
            let entry = index[key],
            entry.matches(fingerprint),
            entry.state == AuraCachedFileState.cached.rawValue || entry.state == AuraCachedFileState.pinned.rawValue
        else {
            return nil
        }

        let cachedURL = cacheDirectory.appending(path: entry.fileName)
        guard fileManager.fileExists(atPath: cachedURL.path) else {
            removeCachedEntry(key: key)
            return nil
        }

        do {
            try validateDownloadedFile(at: cachedURL, response: nil, sourceURL: cachedURL)
            try validatePlayableAudioFile(at: cachedURL, declaredFormat: fingerprint.declaredFormat ?? cachedURL.pathExtension)
            return cachedURL
        } catch {
            removeCachedEntry(key: key)
            return nil
        }
    }

    private func playablePartialURL(forKey key: String, fingerprint: CacheFingerprint, declaredFormat: String?) throws -> URL? {
        guard
            let entry = index[key],
            entry.state == AuraCachedFileState.partial.rawValue,
            entry.matches(fingerprint)
        else {
            return nil
        }

        let partialURL = cacheDirectory.appending(path: entry.partialFileName ?? entry.fileName)
        guard fileManager.fileExists(atPath: partialURL.path) else {
            return nil
        }

        try validateDownloadedFile(at: partialURL, response: nil, sourceURL: partialURL, allowsIncomplete: true)
        try validatePlayableAudioFile(at: partialURL, declaredFormat: declaredFormat)
        return partialURL
    }

    private func withGatewayFallback<Result>(
        startingAt sourceURL: URL,
        operation: (URL) async throws -> Result
    ) async throws -> (result: Result, resolvedURL: URL) {
        var currentURL = sourceURL
        var attemptedURLs: Set<String> = [currentURL.absoluteString]

        while true {
            do {
                return (try await operation(currentURL), currentURL)
            } catch {
                guard let gatewayFallbackResolver,
                      let nextURL = try await gatewayFallbackResolver.nextResolvedURL(after: currentURL),
                      attemptedURLs.insert(nextURL.absoluteString).inserted else {
                    throw error
                }
                currentURL = nextURL
            }
        }
    }

    private func startProgressiveDownload(
        _ media: AnyAuraPlayableMedia,
        key: String,
        fingerprint: CacheFingerprint,
        progressiveDownloader: any ProgressiveMediaDownloading,
        minimumPlayableBytes: Int64
    ) async throws -> ProgressiveCacheDownload {
        let sourceURL = try await resolver.resolve(media.sourceURL)
        let destination = destinationURL(forKey: key, declaredFormat: fingerprint.declaredFormat ?? sourceURL.pathExtension)
        progressBroadcast.yield(CacheProgress(mediaID: media.id, bytesWritten: 0, expectedBytes: nil, state: .partial))
        let (handle, resolvedSourceURL) = try await withGatewayFallback(startingAt: sourceURL) { candidateURL in
            try await progressiveDownloader.downloadUntilPlayable(from: candidateURL, to: destination, minimumPlayableBytes: minimumPlayableBytes) { [progressBroadcast] bytesWritten, expectedBytes in
                progressBroadcast.yield(CacheProgress(mediaID: media.id, bytesWritten: bytesWritten, expectedBytes: expectedBytes, state: .partial))
            }
        }
        try validate(response: handle.response, sourceURL: resolvedSourceURL)

        let completionStatus = ProgressiveCompletionStatus()
        let monitoredCompletion = Task<URL, Error> {
            do {
                let completedURL = try await handle.completion.value
                await completionStatus.succeed(completedURL)
                return completedURL
            } catch {
                await completionStatus.fail(error)
                throw error
            }
        }

        let finalState: AuraCachedFileState = media.cachedFileState == .pinned ? .pinned : .cached

        guard let expectedByteCount = expectedByteCount(from: handle.response) else {
            let completedURL = try await monitoredCompletion.value
            try finalizeProgressiveDownload(key: key, mediaID: media.id, fingerprint: fingerprint, completedURL: completedURL, response: handle.response, sourceURL: resolvedSourceURL, finalState: finalState)
            clearInFlightDownload(key: key, fingerprint: fingerprint)
            return ProgressiveCacheDownload(playableURL: completedURL, completion: monitoredCompletion)
        }

        do {
            try await waitUntilProgressiveFileIsPlayable(
                fileURL: handle.playableURL,
                response: handle.response,
                sourceURL: resolvedSourceURL,
                declaredFormat: fingerprint.declaredFormat ?? resolvedSourceURL.pathExtension,
                expectedByteCount: expectedByteCount,
                completionStatus: completionStatus
            )
        } catch {
            monitoredCompletion.cancel()
            throw error
        }

        try recordCachedFile(
            key: key,
            url: handle.playableURL,
            response: handle.response,
            state: .partial,
            fingerprint: fingerprint,
            partialFileName: handle.playableURL.lastPathComponent
        )

        let completion = Task<URL, Error> { [weak self, monitoredCompletion, key, mediaID = media.id, fingerprint, response = handle.response, resolvedSourceURL, finalState] in
            do {
                let completedURL = try await monitoredCompletion.value
                if let self {
                    try await self.finalizeProgressiveDownload(key: key, mediaID: mediaID, fingerprint: fingerprint, completedURL: completedURL, response: response, sourceURL: resolvedSourceURL, finalState: finalState)
                    await self.clearInFlightDownload(key: key, fingerprint: fingerprint)
                }
                return completedURL
            } catch {
                await self?.removePartialDownload(key: key)
                await self?.clearInFlightDownload(key: key, fingerprint: fingerprint)
                throw error
            }
        }

        return ProgressiveCacheDownload(playableURL: handle.playableURL, completion: completion)
    }

    private func waitUntilProgressiveFileIsPlayable(
        fileURL: URL,
        response: URLResponse,
        sourceURL: URL,
        declaredFormat: String?,
        expectedByteCount: Int64,
        completionStatus: ProgressiveCompletionStatus
    ) async throws {
        var lastValidationError: Error?

        while true {
            do {
                try validateDownloadedFile(at: fileURL, response: response, sourceURL: sourceURL, allowsIncomplete: true)
                try validatePlayableAudioFile(at: fileURL, declaredFormat: declaredFormat)
                return
            } catch {
                lastValidationError = error
            }

            switch await completionStatus.state() {
            case .running:
                break
            case .succeeded:
                throw lastValidationError ?? AuraPlayError.corruptedFile(fileURL)
            case .failed(let error):
                throw error
            }

            if fileSize(fileURL) >= expectedByteCount {
                throw lastValidationError ?? AuraPlayError.corruptedFile(fileURL)
            }

            try await Task.sleep(nanoseconds: 25_000_000)
        }
    }

    private func playableURL(for inFlight: InFlightDownload) async throws -> URL {
        switch inFlight.kind {
        case .complete(let task):
            return try await task.value
        case .progressive(let task):
            return try await task.value.playableURL
        }
    }

    private func finalURL(for inFlight: InFlightDownload) async throws -> URL {
        switch inFlight.kind {
        case .complete(let task):
            return try await task.value
        case .progressive(let task):
            return try await task.value.completion.value
        }
    }

    private func clearInFlightDownload(key: String, fingerprint: CacheFingerprint) {
        guard inFlightDownloads[key]?.fingerprint == fingerprint else {
            return
        }
        inFlightDownloads[key] = nil
    }

    private func resumableTaskIfAvailable(for media: AnyAuraPlayableMedia, key: String, fingerprint: CacheFingerprint) -> Task<URL, Error>? {
        guard
            let entry = index[key],
            entry.state == AuraCachedFileState.partial.rawValue,
            entry.supportsByteRanges,
            entry.matches(fingerprint),
            let resumableDownloader = downloader as? any ResumableMediaDownloading
        else {
            return nil
        }

        let partialURL = cacheDirectory.appending(path: entry.partialFileName ?? entry.fileName)
        let byteOffset = fileSize(partialURL)
        guard byteOffset > 0, fileManager.fileExists(atPath: partialURL.path) else {
            return nil
        }

        return Task<URL, Error> {
            let resolvedURL = try await resolver.resolve(media.sourceURL)
            progressBroadcast.yield(CacheProgress(mediaID: media.id, bytesWritten: byteOffset, expectedBytes: nil, state: .partial))
            let ((completedURL, response), usedURL) = try await withGatewayFallback(startingAt: resolvedURL) { candidateURL in
                try await resumableDownloader.resumeDownload(
                    from: candidateURL,
                    to: partialURL,
                    startingAt: byteOffset,
                    eTag: entry.eTag
                ) { [progressBroadcast] bytesWritten, expectedBytes in
                    progressBroadcast.yield(CacheProgress(mediaID: media.id, bytesWritten: bytesWritten, expectedBytes: expectedBytes, state: .partial))
                }
            }
            try validate(response: response, sourceURL: usedURL)
            try validateDownloadedFile(at: completedURL, response: response, sourceURL: usedURL)
            try validatePlayableAudioFile(at: completedURL, declaredFormat: fingerprint.declaredFormat ?? usedURL.pathExtension)
            try recordCachedFile(key: key, url: completedURL, response: response, state: media.cachedFileState == .pinned ? .pinned : .cached, fingerprint: fingerprint)
            emitLoudnessMeasurement(mediaID: media.id, fileURL: completedURL)
            progressBroadcast.yield(CacheProgress(mediaID: media.id, bytesWritten: fileSize(completedURL), expectedBytes: fileSize(completedURL), state: media.cachedFileState == .pinned ? .pinned : .cached))
            try evictIfNeeded()
            return completedURL
        }
    }

    private func download(_ media: AnyAuraPlayableMedia, key: String, fingerprint: CacheFingerprint, minimumPlayableBytes: Int64? = nil) async throws -> URL {
        let sourceURL = try await resolver.resolve(media.sourceURL)

        if sourceURL.isFileURL {
            let destination = destinationURL(forKey: key, declaredFormat: fingerprint.declaredFormat ?? sourceURL.pathExtension)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: sourceURL, to: destination)
            try validateDownloadedFile(at: destination, response: nil, sourceURL: sourceURL)
            try validatePlayableAudioFile(at: destination, declaredFormat: fingerprint.declaredFormat ?? sourceURL.pathExtension)
            try recordCachedFile(key: key, url: destination, state: media.cachedFileState == .pinned ? .pinned : .cached, fingerprint: fingerprint)
            emitLoudnessMeasurement(mediaID: media.id, fileURL: destination)
            progressBroadcast.yield(CacheProgress(mediaID: media.id, bytesWritten: fileSize(destination), expectedBytes: fileSize(destination), state: media.cachedFileState == .pinned ? .pinned : .cached))
            try evictIfNeeded()
            return destination
        }

        do {
            progressBroadcast.yield(CacheProgress(mediaID: media.id, bytesWritten: 0, expectedBytes: nil, state: .partial))
            let ((temporaryURL, response), usedURL) = try await withGatewayFallback(startingAt: sourceURL) { candidateURL in
                try await downloader.download(from: candidateURL) { [progressBroadcast] bytesWritten, expectedBytes in
                    progressBroadcast.yield(CacheProgress(mediaID: media.id, bytesWritten: bytesWritten, expectedBytes: expectedBytes, state: .partial))
                }
            }
            try validate(response: response, sourceURL: usedURL)
            try validateDownloadedFile(at: temporaryURL, response: response, sourceURL: usedURL)
            try validatePlayableAudioFile(at: temporaryURL, declaredFormat: fingerprint.declaredFormat ?? usedURL.pathExtension)

            if let minimumPlayableBytes, fileSize(temporaryURL) < minimumPlayableBytes {
                throw AuraPlayError.downloadFailed("Downloaded file is smaller than the minimum playable threshold for \(usedURL.absoluteString)")
            }

            let destination = destinationURL(forKey: key, declaredFormat: fingerprint.declaredFormat ?? usedURL.pathExtension)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: temporaryURL, to: destination)
            try recordCachedFile(key: key, url: destination, response: response, state: media.cachedFileState == .pinned ? .pinned : .cached, fingerprint: fingerprint)
            emitLoudnessMeasurement(mediaID: media.id, fileURL: destination)
            progressBroadcast.yield(CacheProgress(mediaID: media.id, bytesWritten: fileSize(destination), expectedBytes: fileSize(destination), state: media.cachedFileState == .pinned ? .pinned : .cached))
            try evictIfNeeded()
            return destination
        } catch let error as AuraPlayError {
            throw error
        } catch {
            throw AuraPlayError.downloadFailed(error.localizedDescription)
        }
    }

    private func finalizeProgressiveDownload(key: String, mediaID: String, fingerprint: CacheFingerprint, completedURL: URL, response: URLResponse, sourceURL: URL, finalState: AuraCachedFileState) throws {
        try validateDownloadedFile(at: completedURL, response: response, sourceURL: sourceURL)
        try recordCachedFile(key: key, url: completedURL, response: response, state: finalState, fingerprint: fingerprint)
        emitLoudnessMeasurement(mediaID: mediaID, fileURL: completedURL)
        progressBroadcast.yield(CacheProgress(mediaID: mediaID, bytesWritten: fileSize(completedURL), expectedBytes: fileSize(completedURL), state: finalState))
        try evictIfNeeded()
    }

    private func removePartialDownload(key: String) {
        removeCachedEntry(key: key)
    }

    private func removeCachedEntry(key: String) {
        guard let entry = index.removeValue(forKey: key) else {
            return
        }
        try? fileManager.removeItem(at: cacheDirectory.appending(path: entry.fileName))
        if let partialFileName = entry.partialFileName, partialFileName != entry.fileName {
            try? fileManager.removeItem(at: cacheDirectory.appending(path: partialFileName))
        }
        try? persistIndex()
    }

    private func validate(response: URLResponse, sourceURL: URL) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            return
        }
        guard (200...206).contains(httpResponse.statusCode) else {
            throw AuraPlayError.downloadFailed("Unexpected HTTP status \(httpResponse.statusCode) for \(sourceURL.absoluteString)")
        }

        if let mimeType = httpResponse.mimeType?.lowercased(), !isAllowedAudioMimeType(mimeType) {
            throw AuraPlayError.downloadFailed("Unexpected content type \(mimeType) for \(sourceURL.absoluteString)")
        }
    }

    private func validateDownloadedFile(at fileURL: URL, response: URLResponse?, sourceURL: URL, allowsIncomplete: Bool = false) throws {
        let byteCount = fileSize(fileURL)
        guard byteCount > 0 else {
            throw AuraPlayError.downloadFailed("Downloaded media was empty for \(sourceURL.absoluteString)")
        }

        if let mimeType = response?.mimeType?.lowercased(), !isAllowedAudioMimeType(mimeType) {
            throw AuraPlayError.downloadFailed("Unexpected content type \(mimeType) for \(sourceURL.absoluteString)")
        }

        if !allowsIncomplete, let response, let expectedByteCount = expectedByteCount(from: response), byteCount != expectedByteCount {
            throw AuraPlayError.downloadFailed("Downloaded media length \(byteCount) did not match expected length \(expectedByteCount) for \(sourceURL.absoluteString)")
        }
    }

    private func validatePlayableAudioFile(at fileURL: URL, declaredFormat: String?) throws {
        _ = try AudioTrackSourceFactory().makeSource(for: fileURL, declaredFormat: declaredFormat)
    }

    private func expectedByteCount(from response: URLResponse) -> Int64? {
        if let httpResponse = response as? HTTPURLResponse {
            if let contentRange = httpResponse.value(forHTTPHeaderField: "Content-Range"),
               let totalComponent = contentRange.split(separator: "/").last,
               let value = Int64(totalComponent),
               value > 0 {
                return value
            }

            if let contentLength = httpResponse.value(forHTTPHeaderField: "Content-Length"), let value = Int64(contentLength), value > 0 {
                return value
            }
        }

        if response.expectedContentLength > 0 {
            return response.expectedContentLength
        }

        return nil
    }

    private func isAllowedAudioMimeType(_ mimeType: String) -> Bool {
        mimeType.hasPrefix("audio/") || mimeType == "application/octet-stream" || mimeType == "binary/octet-stream"
    }

    private func emitLoudnessMeasurement(mediaID: String, fileURL: URL) {
        guard let value = try? loudnessAnalyzer.measureApproxLoudnessLUFS(fileURL: fileURL), value.isFinite else {
            return
        }
        loudnessBroadcast.yield(CachedLoudnessMeasurement(mediaID: mediaID, approxLoudnessLUFS: value))
    }

    private func recordCachedFile(key: String, url: URL, response: URLResponse? = nil, state: AuraCachedFileState, fingerprint: CacheFingerprint, partialFileName: String? = nil) throws {
        let httpResponse = response as? HTTPURLResponse
        if let previousEntry = index[key], previousEntry.fileName != url.lastPathComponent {
            try? fileManager.removeItem(at: cacheDirectory.appending(path: previousEntry.fileName))
            if let previousPartialFileName = previousEntry.partialFileName, previousPartialFileName != previousEntry.fileName {
                try? fileManager.removeItem(at: cacheDirectory.appending(path: previousPartialFileName))
            }
        }
        index[key] = CacheEntry(
            fileName: url.lastPathComponent,
            byteCount: fileSize(url),
            lastAccessed: Date(),
            isPinned: state == .pinned,
            state: state.rawValue,
            supportsByteRanges: httpResponse?.value(forHTTPHeaderField: "Accept-Ranges")?.lowercased() == "bytes",
            eTag: httpResponse?.value(forHTTPHeaderField: "ETag"),
            partialFileName: partialFileName,
            sourceURL: fingerprint.sourceURL,
            declaredFormat: fingerprint.declaredFormat
        )
        try persistIndex()
    }

    private func markAccessed(key: String) {
        index[key]?.lastAccessed = Date()
        try? persistIndex()
    }

    private func evictIfNeeded() throws {
        var totalBytes = index.values.reduce(Int64(0)) { $0 + $1.byteCount }
        guard totalBytes > diskCapBytes else {
            return
        }

        let candidates = index
            .filter { key, entry in !entry.isPinned && entry.state != AuraCachedFileState.partial.rawValue && activeReaderCounts[key, default: 0] == 0 }
            .sorted { $0.value.lastAccessed < $1.value.lastAccessed }

        for (key, entry) in candidates where totalBytes > diskCapBytes {
            let fileURL = cacheDirectory.appending(path: entry.fileName)
            try? fileManager.removeItem(at: fileURL)
            if let partialFileName = entry.partialFileName {
                try? fileManager.removeItem(at: cacheDirectory.appending(path: partialFileName))
            }
            index.removeValue(forKey: key)
            totalBytes -= entry.byteCount
        }

        try persistIndex()
    }

    private func cachedURL(forKey key: String, matching fingerprint: CacheFingerprint) -> URL? {
        guard let entry = index[key], entry.matches(fingerprint) else {
            return nil
        }
        return cacheDirectory.appending(path: entry.fileName)
    }

    private func isCompleteCacheEntry(_ key: String, matching fingerprint: CacheFingerprint) -> Bool {
        guard let entry = index[key], entry.matches(fingerprint) else {
            return false
        }
        return entry.state == AuraCachedFileState.cached.rawValue || entry.state == AuraCachedFileState.pinned.rawValue
    }

    private func cacheFingerprint(for media: AnyAuraPlayableMedia) -> CacheFingerprint {
        CacheFingerprint(
            sourceURL: media.sourceURL.absoluteString,
            declaredFormat: normalizedDeclaredFormat(media.declaredFormat ?? media.sourceURL.pathExtension)
        )
    }

    private func normalizedDeclaredFormat(_ value: String?) -> String? {
        guard let normalized = value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased(),
            !normalized.isEmpty
        else {
            return nil
        }
        return normalized
    }

    private func destinationURL(forKey key: String, declaredFormat: String?) -> URL {
        let normalizedExtension = declaredFormat?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let fileName: String
        if let normalizedExtension, !normalizedExtension.isEmpty {
            fileName = "\(key).\(normalizedExtension)"
        } else {
            fileName = key
        }
        return cacheDirectory.appending(path: fileName)
    }

    private func fileSize(_ url: URL) -> Int64 {
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        return attributes?[.size] as? Int64 ?? 0
    }

    private func persistIndex() throws {
        let data = try JSONEncoder.auraPlayIndexEncoder.encode(index)
        try data.write(to: indexURL, options: .atomic)
    }

    private static func loadIndex(from url: URL) -> [String: CacheEntry] {
        guard let data = try? Data(contentsOf: url) else {
            return [:]
        }
        return (try? JSONDecoder.auraPlayIndexDecoder.decode([String: CacheEntry].self, from: data)) ?? [:]
    }
}

private struct InFlightDownload: Sendable {
    let fingerprint: CacheFingerprint
    let kind: InFlightDownloadKind
}

private enum InFlightDownloadKind: Sendable {
    case complete(Task<URL, Error>)
    case progressive(Task<ProgressiveCacheDownload, Error>)
}

private struct ProgressiveCacheDownload: Sendable {
    let playableURL: URL
    let completion: Task<URL, Error>
}

private actor ProgressiveCompletionStatus {
    private var currentState: ProgressiveCompletionState = .running

    func state() -> ProgressiveCompletionState {
        currentState
    }

    func succeed(_ url: URL) {
        currentState = .succeeded(url)
    }

    func fail(_ error: any Error) {
        currentState = .failed(error)
    }
}

private enum ProgressiveCompletionState: Sendable {
    case running
    case succeeded(URL)
    case failed(any Error)
}

private struct CacheFingerprint: Equatable, Sendable {
    let sourceURL: String
    let declaredFormat: String?
}

private struct CacheEntry: Codable, Sendable {
    var fileName: String
    var byteCount: Int64
    var lastAccessed: Date
    var isPinned: Bool
    var state: String
    var supportsByteRanges: Bool
    var eTag: String?
    var partialFileName: String?
    var sourceURL: String?
    var declaredFormat: String?

    init(
        fileName: String,
        byteCount: Int64,
        lastAccessed: Date,
        isPinned: Bool,
        state: String,
        supportsByteRanges: Bool = false,
        eTag: String? = nil,
        partialFileName: String? = nil,
        sourceURL: String? = nil,
        declaredFormat: String? = nil
    ) {
        self.fileName = fileName
        self.byteCount = byteCount
        self.lastAccessed = lastAccessed
        self.isPinned = isPinned
        self.state = state
        self.supportsByteRanges = supportsByteRanges
        self.eTag = eTag
        self.partialFileName = partialFileName
        self.sourceURL = sourceURL
        self.declaredFormat = declaredFormat
    }

    func matches(_ fingerprint: CacheFingerprint) -> Bool {
        sourceURL == fingerprint.sourceURL && declaredFormat == fingerprint.declaredFormat
    }
}

private extension JSONEncoder {
    static var auraPlayIndexEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var auraPlayIndexDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
