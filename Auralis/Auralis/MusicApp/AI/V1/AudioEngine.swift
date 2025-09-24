//
//  AudioEngine.swift
//  Auralis
//
//  Created by Daniel Bell on 9/4/25.
//

import AVFoundation
import Foundation

@MainActor
class AudioEngine: ObservableObject {
    private var currentNFT: NFT?
    private var audioEngine = AVAudioEngine()
    private var playerNodeA = AVAudioPlayerNode()
    private var playerNodeB = AVAudioPlayerNode()
    private var currentNodeIsA: Bool = true
    private var currentNode: AVAudioPlayerNode { currentNodeIsA ? playerNodeA : playerNodeB }
    private var nextNode: AVAudioPlayerNode { currentNodeIsA ? playerNodeB : playerNodeA }
    private var crossfadeDuration: TimeInterval = 2.0
    private var fadeTimer: DispatchSourceTimer?
    private var isCrossfading: Bool = false
    
    public var audioFile: AVAudioFile?
    public var previousAudio = Playlist(name: "Previous")
    public var nextAudio = Playlist(name: "Next")
    
    
    private var pausedAt: TimeInterval = 0
    private var seekPosition: TimeInterval = 0
    private var tempAudioURL: URL? // Track temporary downloaded file

    private var currentLoadTask: Task<Void, Error>?
    private var activeLoadID = UUID()
    
    enum PlaybackState {
        case stopped
        case playing
        case paused
        case loading
        case error
    }
    
    struct Track: Identifiable, Equatable {
        let id = UUID()
        var title: String?
        var artist: String?
        var duration: TimeInterval
        var imageUrl: String?
    }

    @Published var currentTrack: Track? = nil    
    @Published var playbackState: PlaybackState = .stopped
    @Published var lastError: AudioEngineError? = nil
    
    // Computed property to eliminate state redundancy
    var isPlaying: Bool {
        playbackState == .playing
    }
    
    var progress: Double {
        duration > 0 ? currentTime / duration : 0
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
            try session.setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetoothA2DP])
            try session.setActive(true)
        } catch {
            throw AudioEngineError.sessionSetupFailed
        }
    }
    
    // MARK: - Audio Engine Setup
    private func setupAudioEngine() throws {
        audioEngine.attach(playerNodeA)
        audioEngine.attach(playerNodeB)
        audioEngine.connect(playerNodeA, to: audioEngine.mainMixerNode, format: nil)
        audioEngine.connect(playerNodeB, to: audioEngine.mainMixerNode, format: nil)
        do {
            try audioEngine.start()
        } catch {
            throw AudioEngineError.engineStartFailed
        }
    }
    
    // MARK: - Audio Interruption Handling
    private func setupInterruptionHandling() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
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
    
    @objc private func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        Task { @MainActor in
            switch type {
            case .began:
                if playbackState == .playing {
                    pause()
                }
            case .ended:
                // Reactivate the audio session first
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
        let fileName = url.lastPathComponent.isEmpty ? "audio.mp3" : url.lastPathComponent
        let permanentURL = documentsPath.appendingPathComponent(fileName)
        
        // Remove existing file if it exists
        try? FileManager.default.removeItem(at: permanentURL)
        
        // Move downloaded file to permanent location
        try FileManager.default.moveItem(at: tempURL, to: permanentURL)
        
        return permanentURL
    }
    
    // MARK: - Audio Loading and Playback
    private func loadAudio(from url: URL, title: String?, artist: String?, imageUrl: String?, loadID: UUID) async throws {
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
            currentTrack = Track(title: title, artist: artist, duration: self.duration, imageUrl: imageUrl)
        } catch {
            playbackState = .error
            lastError = .fileLoadFailed
            throw AudioEngineError.fileLoadFailed
        }
    }
    
    public func play() throws {
        // If no audio file is loaded, try to advance to the next queued item
        guard let audioFile = audioFile else {
            playbackState = .loading
            Task { @MainActor in
                await self.playNext()
            }
            return
        }

        // Stop and clear any existing playback
        currentNode.stop()

        // Schedule from current seek position
        let sampleRate = audioFile.processingFormat.sampleRate
        let startFrame = AVAudioFramePosition(seekPosition * sampleRate)
        let remainingFrames = AVAudioFrameCount(audioFile.length - startFrame)

        // If we've reached the end or there's nothing to play, try next item
        guard remainingFrames > 0 else {
            playbackState = .loading
            Task { @MainActor in
                await self.playNext()
            }
            return
        }

        currentNode.scheduleSegment(audioFile, startingFrame: startFrame, frameCount: remainingFrames, at: nil) {
            Task { @MainActor in
                if self.playbackState == .playing {
                    self.playbackState = .stopped
                    // Auto-advance to next item in the next queue if available
                    await self.playNext()
                }
            }
        }

        currentNode.play()
        playbackState = .playing
        scheduleCrossfadeIfPossible()
    }
    
    // Fixed pause implementation - AVAudioPlayerNode doesn't have pause()
    public func pause() {
        guard playbackState == .playing else { return }
        cancelFade()
        pausedAt = currentTime
        playerNodeA.stop()
        playerNodeB.stop()
        playbackState = .paused
    }
    
    public func resume() throws {
        guard playbackState == .paused else { return }
        seekPosition = pausedAt
        try play()
    }
    
    private func stop() {
        cancelFade()
        playerNodeA.stop()
        playerNodeB.stop()
        resetNodeVolumes()
        seekPosition = 0
        pausedAt = 0
        playbackState = .stopped
    }
    
    // MARK: - Fixed Seek Functionality
    public func seek(to time: TimeInterval) throws {
        guard let audioFile = audioFile else { return }
        
        let duration = self.duration
        let clampedTime = max(0, min(time, duration))
        
        let wasPlaying = playbackState == .playing
        
        // Stop and clear buffers
        playerNodeA.stop()
        playerNodeB.stop()
        
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
        // If there's an item queued in Next, crossfade to it if currently playing
        guard !nextAudio.tracks.isEmpty else {
            stop()
            return
        }
        if playbackState == .playing {
            // Emergency short crossfade
            startCrossfade(duration: 0.2)
            return
        }
        // If not currently playing, load and start normally
        let next = nextAudio.tracks.removeFirst()
        if let current = currentNFT { previousAudio.tracks.append(current) }
        do {
            try await loadAndPlay(nft: next)
        } catch {
            if error is CancellationError { return }
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
            playbackState = .error
            lastError = (error as? AudioEngineError) ?? .fileLoadFailed
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
    private func loadAndPlay(url: URL, title: String?, artist: String?, imageUrl: String?) async throws {
        guard canPlayFormat(url) else {
            throw AudioEngineError.unsupportedFormat
        }
        
        // Use the current activeLoadID to guard against stale completions
        let loadID = activeLoadID
        
        try await loadAudio(from: url, title: title, artist: artist, imageUrl: imageUrl, loadID: loadID)
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
        
        // Show upcoming track metadata while loading
        self.currentTrack = Track(
            title: nft.name,
            artist: nft.artistName,
            duration: 0,
            imageUrl: nft.image?.secureUrl ?? nft.image?.originalUrl
        )
        self.playbackState = .loading

        // Start a new load task on the current actor (MainActor)
        let task = Task { [weak self] in
            guard let self else { return }
            try Task.checkCancellation()
            try await self.loadAndPlay(
                url: url,
                title: nft.name,
                artist: nft.artistName,
                imageUrl: nft.image?.secureUrl ?? nft.image?.originalUrl
            )
            try Task.checkCancellation()
            // Only set currentNFT if this load is still the active one
            guard loadID == self.activeLoadID else { throw CancellationError() }
            self.currentNFT = nft
        }

        // Track and await the task
        currentLoadTask = task
        defer { currentLoadTask = nil }
        do {
            try await task.value
        } catch is CancellationError {
            // If this task was cancelled because a newer load started, leave state to the newer request.
            // If not, ensure we don't show stale playing/loading state.
            if loadID == activeLoadID { playbackState = .stopped }
        } catch {
            playbackState = .error
            lastError = (error as? AudioEngineError) ?? .fileLoadFailed
            throw error
        }
    }
    
    // MARK: - Improved Playback Information
    private var currentTime: TimeInterval {
        switch playbackState {
        case .playing:
            // For playing state, calculate from node time + seek position
            guard let audioFile = audioFile,
                  let nodeTime = currentNode.lastRenderTime,
                  let playerTime = currentNode.playerTime(forNodeTime: nodeTime) else {
                return seekPosition
            }
            return seekPosition + (Double(playerTime.sampleTime) / playerTime.sampleRate)
        case .paused:
            return pausedAt
        case .stopped, .loading, .error:
            return seekPosition
        }
    }
    
    private var duration: TimeInterval {
        guard let audioFile = audioFile else { return 0 }
        return Double(audioFile.length) / audioFile.processingFormat.sampleRate
    }
    
    // MARK: - Resource Cleanup
    deinit {
        NotificationCenter.default.removeObserver(self)
        currentLoadTask?.cancel()
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        
        audioEngine.detach(playerNodeA)
        audioEngine.detach(playerNodeB)
        
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
    
    // MARK: - Crossfade Helpers
    private func cancelFade() {
        fadeTimer?.cancel()
        fadeTimer = nil
        isCrossfading = false
    }

    private func resetNodeVolumes() {
        playerNodeA.volume = 1.0
        playerNodeB.volume = 1.0
    }

    private func scheduleCrossfadeIfPossible() {
        // If there's no upcoming track, do nothing
        guard !nextAudio.tracks.isEmpty, let audioFile = audioFile else { return }
        // Compute remaining time
        let sampleRate = audioFile.processingFormat.sampleRate
        let startFrame = AVAudioFramePosition(seekPosition * sampleRate)
        let remainingFrames = max(0, audioFile.length - startFrame)
        let remainingTime = Double(remainingFrames) / sampleRate
        let overlap = min(crossfadeDuration, max(0.0, remainingTime))
        guard overlap > 0 else { return }
        // Schedule a timer to begin crossfade overlap seconds before end
        let fireIn = max(0.0, remainingTime - overlap)
        cancelFade()
        isCrossfading = false
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + fireIn)
        timer.setEventHandler { [weak self] in
            self?.startCrossfade(duration: overlap)
        }
        fadeTimer = timer
        timer.resume()
    }

    private func startCrossfade(duration: TimeInterval) {
        guard !isCrossfading else { return }
        guard !nextAudio.tracks.isEmpty else { return }
        isCrossfading = true
        // Prepare next track
        let next = nextAudio.tracks.removeFirst()
        Task { @MainActor in
            do {
                guard let url = next.musicURL else { throw AudioEngineError.fileLoadFailed }
                // Download if needed without altering current state
                let localURL: URL
                if url.scheme == "http" || url.scheme == "https" {
                    localURL = try await downloadAudioFile(from: url)
                } else {
                    localURL = url
                }
                let nextFile = try AVAudioFile(forReading: localURL)
                // Start next node at volume 0
                nextNode.volume = 0.0
                nextNode.stop()
                nextNode.scheduleFile(nextFile, at: nil, completionHandler: nil)
                if !audioEngine.isRunning { try? audioEngine.start() }
                nextNode.play()
                // Fade loop (equal-power)
                let steps = max(1, Int(duration / 0.02))
                let stepDuration = duration / Double(steps)
                var i = 0
                cancelFade()
                let timer = DispatchSource.makeTimerSource(queue: .main)
                timer.schedule(deadline: .now(), repeating: stepDuration)
                timer.setEventHandler { [weak self] in
                    guard let self else { timer.cancel(); return }
                    let t = min(1.0, Double(i) / Double(steps))
                    // Equal-power curve
                    let fadeIn = sin(t * .pi / 2)
                    let fadeOut = cos(t * .pi / 2)
                    self.nextNode.volume = Float(fadeIn)
                    self.currentNode.volume = Float(fadeOut)
                    i += 1
                    if t >= 1.0 {
                        timer.cancel()
                        self.currentNode.stop()
                        if let oldNFT = self.currentNFT { self.previousAudio.tracks.append(oldNFT) }
                        self.resetNodeVolumes()
                        // Previous queue updated to keep navigation consistent for both scheduled and emergency crossfades.
                        // Swap nodes and update state
                        self.currentNodeIsA.toggle()
                        self.audioFile = nextFile
                        self.seekPosition = 0
                        self.pausedAt = 0
                        self.currentNFT = next
                        self.currentTrack = Track(title: next.name, artist: next.artistName, duration: self.duration, imageUrl: next.image?.secureUrl ?? next.image?.originalUrl)
                        self.playbackState = .playing
                        self.isCrossfading = false
                    }
                }
                self.fadeTimer = timer
                timer.resume()
            } catch {
                // On failure, stop crossfade and attempt normal advance
                self.isCrossfading = false
                self.resetNodeVolumes()
                await self.playNext()
            }
        }
    }
}

