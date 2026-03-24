//
//  AudioEngine.swift
//  Auralis
//
//  Created by Daniel Bell on 9/4/25.
//



import AVFoundation
import Foundation

@MainActor
public class AudioEngine: ObservableObject {
    private var currentNFT: NFT?
    private var audioEngine = AVAudioEngine()
    private var playerNode = AVAudioPlayerNode()
    private var interruptionObserver: NSObjectProtocol?
    
    public var audioFile: AVAudioFile?
    public var previousAudio = Playlist(name: "Previous")
    public var nextAudio = Playlist(name: "Next")
    
    
    private var pausedAt: TimeInterval = 0
    private var seekPosition: TimeInterval = 0
    private var tempAudioURL: URL? // Track temporary downloaded file

    private var currentLoadTask: Task<Void, Error>?
    private var activeLoadID = UUID()
    
    public enum PlaybackState: Equatable, Sendable, Codable  {
        case stopped
        case playing
        case paused
        case loading
        case error
    }

    
    public struct Track: Identifiable, Equatable, Hashable, Codable, Sendable {
        public let id: String
        var title: String?
        var artist: String?
        var duration: TimeInterval
        var imageUrl: String?
    }

    @Published var currentTrack: Track? = nil
    @Published var playbackState: PlaybackState = .stopped
    
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
    
    enum AudioEngineError: Error {
        case sessionSetupFailed
        case engineStartFailed
        case fileLoadFailed
        case unsupportedFormat
        case seekFailed
        case downloadFailed
        
        var localizedDescription: String {
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
            case .downloadFailed:
                return "Failed to download remote audio file"
            }
        }
    }
    
    init() throws {
        try setupAudioSession()
        try setupAudioEngine()
        setupInterruptionHandling()
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
            Task { @MainActor in
                self.handleInterruption(notification)
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

    private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
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

            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else {
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

    
    // MARK: - Remote File Download
    private func downloadAudioFile(from url: URL) async throws -> URL {
        let (tempURL, response) = try await URLSession.shared.download(from: url)
        
        try Task.checkCancellation()
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AudioEngineError.downloadFailed
        }
        
        // Create a permanent temp file with proper extension
        let documentsPath = FileManager.default.temporaryDirectory
        let baseName = url.lastPathComponent.isEmpty ? "audio" : url.deletingPathExtension().lastPathComponent
        let fileExtension = url.pathExtension.isEmpty ? "mp3" : url.pathExtension
        let fileName = "\(baseName)-\(UUID().uuidString).\(fileExtension)"
        let permanentURL = documentsPath.appendingPathComponent(fileName)

        // Move downloaded file to permanent location
        try FileManager.default.moveItem(at: tempURL, to: permanentURL)
        
        return permanentURL
    }
    
    // MARK: - Audio Loading and Playback
    private func loadAudio(from url: URL, trackID: String, title: String?, artist: String?, imageUrl: String?, loadID: UUID) async throws {
        playbackState = .loading
        
        // Respect task cancellation and staleness
        try Task.checkCancellation()
        guard loadID == activeLoadID else { throw CancellationError() }
        
        // Clean up previous temp file
        if let tempURL = tempAudioURL {
            try? FileManager.default.removeItem(at: tempURL)
            tempAudioURL = nil
        }
        
        let localURL: URL
        
        if url.scheme == "http" || url.scheme == "https" {
            let downloadedURL = try await downloadAudioFile(from: url)
            try Task.checkCancellation()
            guard loadID == activeLoadID else {
                // Clean up stale downloaded file
                try? FileManager.default.removeItem(at: downloadedURL)
                throw CancellationError()
            }
            localURL = downloadedURL
            tempAudioURL = localURL
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
            currentTrack = Track(id: trackID, title: title, artist: artist, duration: self.duration, imageUrl: imageUrl)
        } catch {
            playbackState = .stopped
            throw AudioEngineError.fileLoadFailed
        }
    }
    
    public func play() throws {
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

        playerNode.scheduleSegment(audioFile, startingFrame: startFrame, frameCount: remainingFrames, at: nil) {
            Task { @MainActor in
                if self.playbackState == .playing {
                    self.playbackState = .stopped
                    // Auto-advance to next item in the next queue if available
                    await self.playNext()
                }
            }
        }

        playerNode.play()
        playbackState = .playing
    }
    
    // Fixed pause implementation - AVAudioPlayerNode doesn't have pause()
    public func pause() {
        guard playbackState == .playing else { return }
        pausedAt = currentTime
        playerNode.stop()
        playbackState = .paused
    }
    
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
    }
    
    // MARK: - Fixed Seek Functionality
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
        
        // If we were playing, restart from new position
        if wasPlaying {
            try play()
        }
    }
    
    // MARK: - Playlist Navigation
    @MainActor
    public func playNext() async {
        // If there's an item queued in Next, play it
        guard !nextAudio.tracks.isEmpty else {
            stop()
            return
        }

        let next = nextAudio.tracks.removeFirst()

        // Move current item to Previous if available
        if let current = currentNFT {
            previousAudio.tracks.append(current)
        }

        do {
            // loadAndPlay auto-starts playback; no need to call play() again
            try await loadAndPlay(nft: next)
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
    public func playPrevious() async {
        guard !previousAudio.tracks.isEmpty else {
            // If nothing in previous, restart current or stop
            seekPosition = 0
            pausedAt = 0
            if playbackState == .playing {
                try? play()
            }
            return
        }

        let previous = previousAudio.tracks.removeLast()

        // Put current on the front of Next so we can go forward again
        if let current = currentNFT {
            nextAudio.tracks.insert(current, at: 0)
        }

        do {
            // loadAndPlay auto-starts playback; no need to call play() again
            try await loadAndPlay(nft: previous)
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

        try await loadAudio(from: url, trackID: trackID, title: title, artist: artist, imageUrl: imageUrl, loadID: loadID)
        try Task.checkCancellation()
        guard loadID == activeLoadID else { throw CancellationError() }
        try play()
    }
    
    // Convenience: Play directly from an NFT and track current item for prev/next
    public func loadAndPlay(nft: NFT) async throws {
        let loadID = await beginNewLoad()
        guard let url = nft.musicURL else {
            throw AudioEngineError.fileLoadFailed
        }

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
    private var currentTime: TimeInterval {
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
    
    private var duration: TimeInterval {
        guard let audioFile = audioFile else { return 0 }
        return Double(audioFile.length) / audioFile.processingFormat.sampleRate
    }
    
    // MARK: - Resource Cleanup
    deinit {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        currentLoadTask?.cancel()
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        
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
        if currentTime > threshold {
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
