//
//  AudioEngine.swift
//  Auralis
//
//  Created by Daniel Bell on 9/4/25.
//

import AVFoundation
import Foundation

@MainActor
/// Shared playback engine for loading remote NFT audio, managing queue state, and exposing playback status to SwiftUI.
public final class AudioEngine: ObservableObject {
    private static let downloadSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }()

    private static let maxDownloadAttempts = 3
    private static let initialRetryDelayNanoseconds: UInt64 = 1_000_000_000
    private static let maxRetryDelayNanoseconds: UInt64 = 4_000_000_000

    private var currentNFT: NFT?
    private var audioEngine = AVAudioEngine()
    private var playerNode = AVAudioPlayerNode()
    private var interruptionObserver: NSObjectProtocol?
    private let downloadSession: URLSession

    /// The currently loaded audio file, if any.
    public var audioFile: AVAudioFile?
    /// Queue of previously played items.
    public var previousAudio = Playlist(name: "Previous")
    /// Queue of upcoming items.
    public var nextAudio = Playlist(name: "Next")

    private var pausedAt: TimeInterval = 0
    private var seekPosition: TimeInterval = 0
    private var tempAudioURL: URL? // Track temporary downloaded file

    private var currentLoadTask: Task<Void, Error>?
    private var activeLoadID = UUID()
    private var displayUpdateTask: Task<Void, Never>?
    private var musicReceiptLogger: MusicReceiptEventLogger?
    private var pendingPlaybackTriggerCause: MusicReceiptTriggerCause?

    /// High-level playback states exposed to the UI.
    public enum PlaybackState: Equatable, Sendable, Codable {
        case stopped
        case playing
        case paused
        case loading
        case error
    }

    /// Lightweight presentation model for the currently playing track.
    public struct Track: Identifiable, Equatable, Hashable, Codable, Sendable {
        /// Stable identifier that matches the NFT identifier.
        public let id: String
        var title: String?
        var artist: String?
        var duration: TimeInterval
        var imageUrl: String?
    }

    @Published var currentTrack: Track?
    @Published var playbackState: PlaybackState = .stopped
    @Published private(set) var currentTime: TimeInterval = 0

    // Computed property to eliminate state redundancy
    var isPlaying: Bool {
        playbackState == .playing
    }

    var progress: Double {
        currentTime
    }

    var currentTrackNFTID: String? {
        currentTrack?.id
    }

    enum AudioEngineError: Error, LocalizedError {
        case sessionSetupFailed
        case engineStartFailed
        case fileLoadFailed
        case unsupportedFormat
        case seekFailed
        case downloadFailed(underlying: Error)
        case invalidDownloadResponse
        case badStatus(Int)
        case unauthorized
        case rateLimited(retryAfter: TimeInterval?)

        var errorDescription: String? {
            switch self {
            case .sessionSetupFailed:
                return "Failed to configure audio session"
            case .engineStartFailed:
                return "Failed to start audio engine"
            case .fileLoadFailed:
                return "Failed to load audio file"
            case .unsupportedFormat:
                return "Unsupported audio format"
            case .seekFailed:
                return "Failed to seek to position"
            case .downloadFailed(let underlying):
                return "Failed to download remote audio file: \(underlying.localizedDescription)"
            case .invalidDownloadResponse:
                return "The audio server returned an invalid response."
            case .badStatus(let statusCode):
                if statusCode == 404 {
                    return "The remote audio file could not be found."
                }
                if (500...599).contains(statusCode) {
                    return "The audio server is unavailable right now. Please try again."
                }
                return "The audio server returned HTTP \(statusCode)."
            case .unauthorized:
                return "The audio source rejected the request."
            case .rateLimited(let retryAfter):
                if let retryAfter {
                    return "The audio source is rate-limiting requests. Retry after \(Int(retryAfter)) seconds."
                }
                return "The audio source is rate-limiting requests. Please try again shortly."
            }
        }
    }

    init(downloadSession: URLSession? = nil) throws {
        self.downloadSession = downloadSession ?? Self.downloadSession
        try setupAudioSession()
        try setupAudioEngine()
        setupInterruptionHandling()
    }

    func configureMusicReceiptLogger(_ logger: MusicReceiptEventLogger?) {
        musicReceiptLogger = logger
    }

    // MARK: - Audio Session Configuration
    private func setupAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        do {
            // Removed .mixWithOthers for proper music app behavior
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            throw AudioEngineError.sessionSetupFailed
        }
    }

    // MARK: - Audio Engine Setup
    private func setupAudioEngine() throws {
        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: nil)

        do {
            try audioEngine.start()
        } catch {
            throw AudioEngineError.engineStartFailed
        }
    }

    // MARK: - Audio Interruption Handling
    private func setupInterruptionHandling() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let userInfo = notification.userInfo
            let typeValue = userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let optionsValue = userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            Task { @MainActor in
                self.handleInterruption(typeValue: typeValue, optionsValue: optionsValue)
            }
        }
    }

    @discardableResult
    private func beginNewLoad() async -> UUID {
        // Capture and cancel any in-flight load task, then await its completion to avoid overlap
        let previousTask = currentLoadTask
        currentLoadTask = nil
        previousTask?.cancel()
        _ = try? await previousTask?.value
        let id = UUID()
        activeLoadID = id
        return id
    }

    private func handleInterruption(typeValue: UInt?, optionsValue: UInt?) {
        guard let typeValue,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            if playbackState == .playing {
                pause()
            }
        case .ended:
            do {
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                return
            }

            guard let optionsValue else {
                return
            }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) && playbackState == .paused {
                try? resume()
            }
        @unknown default:
            break
        }
    }

    private func canPlayFormat(_ url: URL) -> Bool {
        guard url.isSupportedRemoteMediaURL else {
            return false
        }

        // File extensions supported by AVAudioFile/Core Audio
        let supportedFormats: Set<String> = [
            // Uncompressed / PCM
            "wav",      // Waveform Audio
            "aif", "aiff", "aifc", // AIFF / AIFC
            "caf",      // Core Audio Format

            // Compressed
            "mp3",      // MPEG Layer III
            "m4a",      // MPEG-4 Audio (AAC or ALAC)
            "mp4",      // MPEG-4 container with audio
            "aac", "adts", // AAC raw or ADTS

            // Dolby
            "ac3", "eac3", // AC-3 and Enhanced AC-3 (device support dependent)

            // FLAC (iOS 11+ / macOS 10.13+)
            "flac"
        ]

        // Domains that serve audio content without file extensions
        let audioServingDomains: Set<String> = [
            "arweave.net",
            "ipfs.io",
            "gateway.pinata.cloud"
        ]

        if let host = url.host?.lowercased(), audioServingDomains.contains(host) {
            return true
        }

        let fileExtension = url.pathExtension.lowercased()
        return supportedFormats.contains(fileExtension)
    }

    private func shouldRetryDownload(after error: Error) -> Bool {
        switch error {
        case AudioEngineError.downloadFailed:
            return true
        case AudioEngineError.badStatus(let statusCode):
            return statusCode == 408 || statusCode == 429 || (500...599).contains(statusCode)
        case AudioEngineError.rateLimited:
            return true
        default:
            return false
        }
    }

    private func retryDelay(after error: Error, fallbackDelay: UInt64) -> UInt64 {
        guard case AudioEngineError.rateLimited(let retryAfter) = error,
              let retryAfter else {
            return fallbackDelay
        }

        let retryDelay = UInt64(max(retryAfter, 0) * 1_000_000_000)
        return min(retryDelay, Self.maxRetryDelayNanoseconds)
    }

    private func retryDelayAfterDoubling(_ delay: UInt64) -> UInt64 {
        let (doubled, overflowed) = delay.multipliedReportingOverflow(by: 2)
        if overflowed {
            return Self.maxRetryDelayNanoseconds
        }
        return min(doubled, Self.maxRetryDelayNanoseconds)
    }

    private func retryAfterInterval(from response: HTTPURLResponse) -> TimeInterval? {
        RetryAfterSupport.parse(from: response)
    }

    private func downloadRemoteAudio(from url: URL) async throws -> URL {
        var delay = Self.initialRetryDelayNanoseconds

        for attempt in 1...Self.maxDownloadAttempts {
            do {
                return try await downloadRemoteAudioOnce(from: url)
            } catch {
                guard attempt < Self.maxDownloadAttempts, shouldRetryDownload(after: error) else {
                    throw error
                }

                try await Task.sleep(nanoseconds: retryDelay(after: error, fallbackDelay: delay))
                delay = retryDelayAfterDoubling(delay)
            }
        }

        throw AudioEngineError.downloadFailed(underlying: URLError(.unknown))
    }

    private func downloadRemoteAudioOnce(from url: URL) async throws -> URL {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        do {
            let (downloadedTemporaryURL, response) = try await downloadSession.download(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw AudioEngineError.invalidDownloadResponse
            }

            switch httpResponse.statusCode {
            case 200...299:
                return downloadedTemporaryURL
            case 401, 403:
                throw AudioEngineError.unauthorized
            case 429:
                throw AudioEngineError.rateLimited(
                    retryAfter: retryAfterInterval(from: httpResponse)
                )
            default:
                throw AudioEngineError.badStatus(httpResponse.statusCode)
            }
        } catch let error as AudioEngineError {
            throw error
        } catch let error as URLError {
            throw AudioEngineError.downloadFailed(underlying: error)
        } catch {
            throw AudioEngineError.downloadFailed(underlying: error)
        }
    }

    /// Starts playback for the current file or advances to the next queued item.
    public func play() throws {
        if pendingPlaybackTriggerCause == nil {
            pendingPlaybackTriggerCause = .userInitiated
        }
        try play(shouldRecordStart: true)
    }

    private func play(shouldRecordStart: Bool) throws {
        // If no audio file is loaded, try to advance to the next queued item
        guard let audioFile = audioFile else {
            Task { @MainActor in
                await self.playNext()
            }
            return
        }

        // Stop and clear any existing playback
        playerNode.stop()

        // Schedule from current seek position
        let sampleRate = audioFile.processingFormat.sampleRate
        let startFrame = AVAudioFramePosition(seekPosition * sampleRate)
        let remainingFrames = AVAudioFrameCount(audioFile.length - startFrame)

        // If we've reached the end or there's nothing to play, try next item
        guard remainingFrames > 0 else {
            Task { @MainActor in
                await self.playNext()
            }
            return
        }

        let completedTrackID = currentTrack?.id
        let completedTitle = currentTrack?.title
        let completedArtist = currentTrack?.artist

        playerNode.scheduleSegment(audioFile, startingFrame: startFrame, frameCount: remainingFrames, at: nil) {
            Task { @MainActor in
                if self.playbackState == .playing, self.currentTrack?.id == completedTrackID {
                    if let completedTrackID {
                        await self.recordPlaybackCompletedIfPossible(
                            mediaID: completedTrackID,
                            title: completedTitle,
                            artist: completedArtist,
                            triggerCause: .autoAdvance
                        )
                    }
                    self.playbackState = .stopped
                    // Auto-advance to next item in the next queue if available
                    await self.playNext(triggerCause: .autoAdvance)
                }
            }
        }

        playerNode.play()
        playbackState = .playing
        updateCurrentTime()
        startDisplayUpdates()
        if shouldRecordStart {
            recordPlaybackStartedIfPossible()
        }
        pendingPlaybackTriggerCause = nil
    }

    // Fixed pause implementation - AVAudioPlayerNode doesn't have pause()
    /// Pauses playback and remembers the current time.
    public func pause() {
        guard playbackState == .playing else { return }
        pausedAt = computedCurrentTime
        playerNode.stop()
        playbackState = .paused
        updateCurrentTime()
        stopDisplayUpdates()
    }

    /// Resumes playback from the last paused position.
    public func resume() throws {
        guard playbackState == .paused else { return }
        seekPosition = pausedAt
        try play()
    }

    private func stop() {
        playerNode.stop()
        seekPosition = 0
        pausedAt = 0
        playbackState = .stopped
        updateCurrentTime()
        stopDisplayUpdates()
    }

    // MARK: - Fixed Seek Functionality
    /// Seeks to a time within the current file.
    public func seek(to time: TimeInterval) throws {
        guard audioFile != nil else { return }

        let duration = self.duration
        let clampedTime = max(0, min(time, duration))

        let wasPlaying = playbackState == .playing

        // Stop and clear buffers
        playerNode.stop()

        // Update seek position
        seekPosition = clampedTime
        pausedAt = clampedTime
        updateCurrentTime()

        // If we were playing, restart from new position
        if wasPlaying {
            try play(shouldRecordStart: false)
        }
    }

    // MARK: - Playlist Navigation
    @MainActor
    /// Advances playback to the next queued item.
    public func playNext() async {
        await playNext(triggerCause: .userInitiated)
    }

    @MainActor
    private func playNext(triggerCause: MusicReceiptTriggerCause) async {
        // If there's an item queued in Next, play it
        guard !nextAudio.tracks.isEmpty else {
            stop()
            return
        }

        let beforeSummary = queueStateSummary()
        let next = nextAudio.tracks.removeFirst()

        // Move current item to Previous if available
        if let current = currentNFT {
            previousAudio.tracks.append(current)
        }

        do {
            // loadAndPlay auto-starts playback; no need to call play() again
            try await loadAndPlay(nft: next, triggerCause: triggerCause)
            await recordQueueChangedIfPossible(
                operation: "next",
                affectedMediaIDs: [next.id],
                beforeSummary: beforeSummary,
                afterSummary: queueStateSummary(),
                triggerCause: triggerCause,
                nft: next
            )
        } catch {
            // If the error is a cancellation (stale load), do nothing; a newer request will handle playback
            if error is CancellationError { return }
            // If playback fails, try the next item recursively, or stop if none
            await playNextSafely()
        }
    }

    @MainActor
    private func playNextSafely() async {
        if nextAudio.tracks.isEmpty {
            stop()
        } else {
            await playNext()
        }
    }

    @MainActor
    /// Returns playback to the previous queued item.
    public func playPrevious() async {
        await playPrevious(triggerCause: .userInitiated)
    }

    @MainActor
    private func playPrevious(triggerCause: MusicReceiptTriggerCause) async {
        guard !previousAudio.tracks.isEmpty else {
            // If nothing in previous, restart current or stop
            seekPosition = 0
            pausedAt = 0
            if playbackState == .playing {
                try? play()
            }
            return
        }

        let beforeSummary = queueStateSummary()
        let previous = previousAudio.tracks.removeLast()

        // Put current on the front of Next so we can go forward again
        if let current = currentNFT {
            nextAudio.tracks.insert(current, at: 0)
        }

        do {
            // loadAndPlay auto-starts playback; no need to call play() again
            try await loadAndPlay(nft: previous, triggerCause: triggerCause)
            await recordQueueChangedIfPossible(
                operation: "previous",
                affectedMediaIDs: [previous.id],
                beforeSummary: beforeSummary,
                afterSummary: queueStateSummary(),
                triggerCause: triggerCause,
                nft: previous
            )
        } catch {
            // If the error is a cancellation (stale load), do nothing; a newer request will handle playback
            if error is CancellationError { return }
            // If playback fails, attempt the previous again if available
            await playPreviousSafely()
        }
    }

    @MainActor
    private func playPreviousSafely() async {
        if previousAudio.tracks.isEmpty {
            stop()
        } else {
            await playPrevious()
        }
    }

    // Note: This method loads the file and immediately starts playback (auto-play).
    private func loadAndPlay(
        url: URL,
        trackID: String,
        title: String?,
        artist: String?,
        imageUrl: String?,
        loadID: UUID
    ) async throws {
        guard canPlayFormat(url) else {
            throw AudioEngineError.unsupportedFormat
        }

        playbackState = .loading

        try Task.checkCancellation()
        guard loadID == activeLoadID else { throw CancellationError() }

        if let tempURL = tempAudioURL {
            try? FileManager.default.removeItem(at: tempURL)
            tempAudioURL = nil
        }

        let localURL: URL
        if url.scheme == "http" || url.scheme == "https" {
            let downloadedTemporaryURL = try await downloadRemoteAudio(from: url)
            try Task.checkCancellation()

            let temporaryDirectory = FileManager.default.temporaryDirectory
            let baseName = url.lastPathComponent.isEmpty ? "audio" : url.deletingPathExtension().lastPathComponent
            let fileExtension = url.pathExtension.isEmpty ? "mp3" : url.pathExtension
            let fileName = "\(baseName)-\(UUID().uuidString).\(fileExtension)"
            let downloadedURL = temporaryDirectory.appendingPathComponent(fileName)
            try FileManager.default.moveItem(at: downloadedTemporaryURL, to: downloadedURL)

            try Task.checkCancellation()
            guard loadID == activeLoadID else {
                try? FileManager.default.removeItem(at: downloadedURL)
                throw CancellationError()
            }

            localURL = downloadedURL
            tempAudioURL = downloadedURL
        } else {
            localURL = url
        }

        try Task.checkCancellation()
        guard loadID == activeLoadID else { throw CancellationError() }

        do {
            audioFile = try AVAudioFile(forReading: localURL)
            seekPosition = 0
            pausedAt = 0
            playbackState = .stopped
            updateCurrentTime()
            currentTrack = Track(id: trackID, title: title, artist: artist, duration: self.duration, imageUrl: imageUrl)
        } catch {
            playbackState = .stopped
            updateCurrentTime()
            throw AudioEngineError.fileLoadFailed
        }

        try Task.checkCancellation()
        guard loadID == activeLoadID else { throw CancellationError() }
        try play()
    }

    // Convenience: Play directly from an NFT and track current item for prev/next
    /// Loads the NFT audio source and starts playback immediately.
    public func loadAndPlay(nft: NFT) async throws {
        try await loadAndPlay(nft: nft, triggerCause: .userInitiated)
    }

    private func loadAndPlay(nft: NFT, triggerCause: MusicReceiptTriggerCause) async throws {
        let loadID = await beginNewLoad()
        guard let url = nft.musicURL else {
            throw AudioEngineError.fileLoadFailed
        }
        pendingPlaybackTriggerCause = triggerCause

        // Start a new load task on the current actor (MainActor)
        let task = Task { [weak self] in
            guard let self else { return }
            try Task.checkCancellation()
            try await self.loadAndPlay(
                url: url,
                trackID: nft.id,
                title: nft.name,
                artist: nft.artistName,
                imageUrl: nft.image?.secureUrl ?? nft.image?.originalUrl,
                loadID: loadID
            )
            try Task.checkCancellation()
            // Only set currentNFT if this load is still the active one
            guard loadID == self.activeLoadID else { throw CancellationError() }
            self.currentNFT = nft
        }

        // Track and await the task
        currentLoadTask = task
        defer {
            if currentLoadTask == task {
                currentLoadTask = nil
            }
        }
        try await task.value
    }

    // MARK: - Improved Playback Information
    private var computedCurrentTime: TimeInterval {
        switch playbackState {
        case .playing:
            // For playing state, calculate from node time + seek position
            guard let nodeTime = playerNode.lastRenderTime,
                  let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else {
                return seekPosition
            }
            return seekPosition + (Double(playerTime.sampleTime) / playerTime.sampleRate)
        case .paused:
            return pausedAt
        case .stopped, .loading:
            return seekPosition
        case .error:
            return .zero
        }
    }

    private func updateCurrentTime() {
        currentTime = computedCurrentTime
    }

    private func startDisplayUpdates() {
        stopDisplayUpdates()
        displayUpdateTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                guard self.playbackState == .playing else { return }
                self.updateCurrentTime()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func stopDisplayUpdates() {
        displayUpdateTask?.cancel()
        displayUpdateTask = nil
    }

    private var duration: TimeInterval {
        guard let audioFile = audioFile else { return 0 }
        return Double(audioFile.length) / audioFile.processingFormat.sampleRate
    }

    // MARK: - Resource Cleanup
    isolated deinit {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        currentLoadTask?.cancel()
        if audioEngine.isRunning {
            audioEngine.stop()
        }

        displayUpdateTask?.cancel()

        audioEngine.detach(playerNode)

        // Clean up temp file
        if let tempURL = tempAudioURL {
            try? FileManager.default.removeItem(at: tempURL)
        }

        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            // Log cleanup error but don't throw in deinit
        }
    }

    func skipBackward() {
        // If we're a few seconds into the current track, restart it; otherwise go to the previous track
        let threshold: TimeInterval = 3
        if computedCurrentTime > threshold {
            try? seek(to: 0)
        } else {
            Task { @MainActor in
                await self.playPrevious()
            }
        }
    }

    func skipForward() {
        Task { @MainActor in
            await self.playNext()
        }
    }

    func getRecentlyPlayed(limit: Int) -> [NFT] {
        // "previousAudio" appends the most recently finished/left track at the end.
        // Return the most recent first, capped by the provided limit.
        guard limit > 0 else { return [] }
        let slice = previousAudio.tracks.suffix(limit)
        return Array(slice.reversed())
    }

    func lastPlayedDate(for id: String) -> Date {
        // No timestamp data is persisted in this engine; provide a sensible placeholder.
        // If it's the current item, treat as now; otherwise, return distantPast.
        if let current = currentNFT, current.id == id {
            return Date()
        }
        return .distantPast
    }

    func removeFromPrevious(id: String) {
        previousAudio.tracks.removeAll { $0.id == id }
    }

    func clearPreviousHistory() {
        previousAudio.tracks.removeAll()
    }
}

@MainActor
private extension AudioEngine {
    func queueStateSummary() -> MusicReceiptStateSummary {
        MusicReceiptStateSummary(
            values: [
                "currentTrackID": currentNFT.map { .string($0.id) } ?? .null,
                "upcomingCount": .number(Double(nextAudio.tracks.count)),
                "historyCount": .number(Double(previousAudio.tracks.count))
            ]
        )
    }

    func receiptContext(for nft: NFT?, triggerCause: MusicReceiptTriggerCause) -> MusicReceiptContext {
        MusicReceiptContext(
            triggerCause: triggerCause,
            actor: .user,
            accountAddress: nft?.accountAddressRawValue.nilIfEmpty,
            chain: nft.flatMap { Chain(rawValue: $0.networkRawValue) },
            surface: "music.playback.engine"
        )
    }

    func recordPlaybackStartedIfPossible() {
        guard let musicReceiptLogger, let currentNFT else {
            return
        }

        let triggerCause = pendingPlaybackTriggerCause ?? .userInitiated
        Task { @MainActor in
            _ = try? await musicReceiptLogger.recordPlaybackStarted(
                mediaID: currentNFT.id,
                title: currentNFT.name,
                artist: currentNFT.artistName,
                context: receiptContext(for: currentNFT, triggerCause: triggerCause)
            )
        }
    }

    func recordPlaybackCompletedIfPossible(
        mediaID: String,
        title: String?,
        artist: String?,
        triggerCause: MusicReceiptTriggerCause
    ) async {
        guard let musicReceiptLogger else {
            return
        }

        _ = try? await musicReceiptLogger.recordPlaybackCompleted(
            mediaID: mediaID,
            title: title,
            artist: artist,
            context: receiptContext(for: currentNFT, triggerCause: triggerCause)
        )
    }

    func recordQueueChangedIfPossible(
        operation: String,
        affectedMediaIDs: [String],
        beforeSummary: MusicReceiptStateSummary,
        afterSummary: MusicReceiptStateSummary,
        triggerCause: MusicReceiptTriggerCause,
        nft: NFT
    ) async {
        guard let musicReceiptLogger else {
            return
        }

        _ = try? await musicReceiptLogger.recordQueueChanged(
            operation: operation,
            affectedMediaIDs: affectedMediaIDs,
            beforeSummary: beforeSummary,
            afterSummary: afterSummary,
            context: receiptContext(for: nft, triggerCause: triggerCause)
        )
    }
}
