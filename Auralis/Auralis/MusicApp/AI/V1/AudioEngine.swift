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
    private var audioEngine = AVAudioEngine()
    private var playerNodeA = AVAudioPlayerNode()
    private var playerNodeB = AVAudioPlayerNode()
    private let mixerA = AVAudioMixerNode()
    private let mixerB = AVAudioMixerNode()
    private let gainA = TinyGainUnit()
    private let gainB = TinyGainUnit()
    private var currentNodeIsA: Bool = true
    private var currentNode: AVAudioPlayerNode { currentNodeIsA ? playerNodeA : playerNodeB }
    private var nextNode: AVAudioPlayerNode { currentNodeIsA ? playerNodeB : playerNodeA }
    private var currentMixer: AVAudioMixerNode { currentNodeIsA ? mixerA : mixerB }
    private var nextMixer: AVAudioMixerNode { currentNodeIsA ? mixerB : mixerA }
    private var currentGainUnit: TinyGainUnit { currentNodeIsA ? gainA : gainB }
    private var nextGainUnit: TinyGainUnit { currentNodeIsA ? gainB : gainA }
    private var crossfadeDuration: TimeInterval = 2.0
    // Crossfade configuration
    private let crossfadePeakGain: Float = 0.9 // cap peak during overlap to avoid clipping (Option A)
    private let crossfadeSafetyPad: TimeInterval = 0.05 // 50 ms safety pad before track end
    
    public var audioFile: AVAudioFile?
    public var previousAudio = Playlist(name: "Previous")
    public var nextAudio = Playlist(name: "Next")
    private var currentNFT: NFT? = nil
    
    private var pausedAt: TimeInterval = 0
    private var seekPosition: TimeInterval = 0
    private var tempAudioURL: URL? // Track temporary downloaded file

    private var currentLoadTask: Task<Void, Never>?
    private var activeLoadID: UUID = .init()
    
    @Published var currentTrack: Track? = nil    
    @Published var playbackState: PlaybackState = .stopped
    @Published var lastError: AudioEngineError? = nil
    private var needsEngineStart: Bool = false
    
    // Computed property to eliminate state redundancy
    var isPlaying: Bool {
        playbackState == .playing
    }
    
    var progress: Double {
        duration > 0 ? currentTime / duration : 0
    }
    
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

    enum AudioEngineError: Error {
        case sessionSetupFailed
        case engineStartFailed(underlying: Error?)
        case fileLoadFailed
        case unsupportedFormat
        case seekFailed
        case downloadFailed
        
        var localizedDescription: String {
            switch self {
            case .sessionSetupFailed:
                return "Failed to configure audio session"
            case .engineStartFailed(let underlying):
                if let underlying { return "Failed to start audio engine: \(underlying.localizedDescription)" }
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
    
    // MARK: - Loading Helpers (non-isolated)
    nonisolated private static func downloadToManagedTemp(from url: URL) async throws -> URL {
        // Cooperatively cancellable download; move to a managed temp folder we control
        let (tempURL, response) = try await URLSession.shared.download(from: url)
        try Task.checkCancellation()

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw AudioEngineError.downloadFailed
        }

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("AudioLoads", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Preserve extension if present, otherwise default to mp3
        let suggestedName = url.lastPathComponent.isEmpty ? UUID().uuidString : url.lastPathComponent
        let ext = (suggestedName as NSString).pathExtension.isEmpty ? "mp3" : (suggestedName as NSString).pathExtension
        let base = ((suggestedName as NSString).deletingPathExtension)
        let dest = dir.appendingPathComponent("\(base)-\(UUID().uuidString).\(ext)")

        // Remove any file if it somehow already exists (extremely unlikely)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tempURL, to: dest)
        return dest
    }

    nonisolated private static func shouldTreatAsRemote(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
    
    // Added single-flight starter without arguments
    @discardableResult
    private func beginNewLoad() async -> UUID {
        // Cancel and await any in-flight load task to avoid overlap
        let previousTask = currentLoadTask
        currentLoadTask = nil
        previousTask?.cancel()
        _ = await previousTask?.value
        let id = UUID()
        activeLoadID = id
        return id
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
        audioEngine.attach(gainA)
        audioEngine.attach(gainB)
        audioEngine.attach(mixerA)
        audioEngine.attach(mixerB)

        // Normalize formats to the engine's output format to avoid conversion issues
        let outFormat = audioEngine.outputNode.inputFormat(forBus: 0)

        // player A → gain A → mixer A → main mixer
        audioEngine.connect(playerNodeA, to: gainA, format: outFormat)
        audioEngine.connect(gainA, to: mixerA, format: outFormat)
        audioEngine.connect(mixerA, to: audioEngine.mainMixerNode, format: outFormat)

        // player B → gain B → mixer B → main mixer
        audioEngine.connect(playerNodeB, to: gainB, format: outFormat)
        audioEngine.connect(gainB, to: mixerB, format: outFormat)
        audioEngine.connect(mixerB, to: audioEngine.mainMixerNode, format: outFormat)

        // Start silent by default
        mixerA.volume = 0.0
        mixerB.volume = 0.0
        gainA.setLinearGain(0.0)
        gainB.setLinearGain(0.0)

        audioEngine.prepare()
    }
    
    // MARK: - Engine Start Guarantees
    @MainActor
    private func ensureSessionActive() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetoothA2DP])
        try session.setActive(true, options: [])
    }

    @MainActor
    private func ensureEngineReadyToPlay() throws {
        if audioEngine.isRunning && !needsEngineStart { return }

        do {
            try ensureSessionActive()
        } catch {
            throw AudioEngineError.sessionSetupFailed
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            needsEngineStart = false
            return
        } catch {
            // Attempt minimal recovery then retry once
            audioEngine.stop()
            audioEngine.reset()
            audioEngine.prepare()
            do {
                try audioEngine.start()
                needsEngineStart = false
                return
            } catch {
                throw AudioEngineError.engineStartFailed(underlying: error)
            }
        }
    }

    @MainActor
    func performCrossfade(duration: TimeInterval,
                          from currentMixer: AVAudioMixerNode,
                          to nextMixer: AVAudioMixerNode) {
        // Clamp duration
        let d = max(0.05, min(duration, 10.0))
        // Enable next path in the graph
        nextMixer.volume = 1.0
        // Compute a hostTime aligned to the engine's render timeline
        guard let renderTime = self.audioEngine.outputNode.lastRenderTime else { return }
        let hostTime = renderTime.hostTime
        // Schedule ramps: current down to 0, next up to crossfadePeakGain
        nextGainUnit.scheduleLinearRamp(to: crossfadePeakGain, duration: d, atHostTime: hostTime)
        currentGainUnit.scheduleLinearRamp(to: 0.0, duration: d, atHostTime: hostTime)
    }
    
    // MARK: - Audio Interruption Handling
    private func setupInterruptionHandling() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
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
                needsEngineStart = true
                if playbackState == .playing {
                    pause()
                }
            case .ended:
                needsEngineStart = true
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
    
    @objc private func handleRouteChange(notification: Notification) {
        // Mark that the engine needs a fresh start on next playback after route changes
        needsEngineStart = true
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

    
    // MARK: - Audio Loading and Playback
    private func loadAudio(from url: URL, title: String?, artist: String?, imageUrl: String?, loadID: UUID) async throws {
        playbackState = .loading
        
        guard loadID == activeLoadID else { throw CancellationError() }
        
        // Clean up previous temp file
        if let tempURL = tempAudioURL {
            try? FileManager.default.removeItem(at: tempURL)
            tempAudioURL = nil
        }
        
        let localURL: URL
        
        if AudioEngine.shouldTreatAsRemote(url) {
            let downloadedURL = try await AudioEngine.downloadToManagedTemp(from: url)
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

        try ensureEngineReadyToPlay()

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
        // Ensure path gain: enable active mixer, mute inactive; set gains for paths
        currentMixer.volume = 1.0
        nextMixer.volume = 0.0
        currentGainUnit.setLinearGain(crossfadePeakGain)
        nextGainUnit.setLinearGain(0.0)
        playbackState = .playing
        scheduleCrossfadeIfPossible()
    }
    
    // Fixed pause implementation - AVAudioPlayerNode doesn't have pause()
    public func pause() {
        guard playbackState == .playing else { return }
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
        playerNodeA.stop()
        playerNodeB.stop()
        mixerA.volume = 0.0
        mixerB.volume = 0.0
        gainA.setLinearGain(0.0)
        gainB.setLinearGain(0.0)
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
            let fadeID = activeLoadID
            // Immediate crossfade with pre-roll at mixer=0
            let next = nextAudio.tracks.removeFirst()
            if let current = currentNFT { previousAudio.tracks.append(current) }
            Task { @MainActor in
                do {
                    guard let url = next.musicURL else { return }
                    try self.ensureEngineReadyToPlay()
                    let localURL: URL
                    if AudioEngine.shouldTreatAsRemote(url) {
                        localURL = try await AudioEngine.downloadToManagedTemp(from: url)
                    } else {
                        localURL = url
                    }
                    let nextFile = try AVAudioFile(forReading: localURL)
                    guard fadeID == self.activeLoadID else {
                        print("xfade_cancelled_stale {\(fadeID)}")
                        return
                    }
                    self.nextMixer.volume = 0.0
                    self.nextGainUnit.setLinearGain(0.0)
                    self.nextNode.stop()
                    self.nextNode.scheduleFile(nextFile, at: nil, completionHandler: nil)
                    self.nextNode.play()

                    // Auto-cap fade: min(configured, 30% of current track length)
                    let cappedFade = min(self.crossfadeDuration, 0.3 * self.duration)
                    let d = max(0.05, min(cappedFade, 10.0))
                    self.performCrossfade(duration: d, from: self.currentMixer, to: self.nextMixer)

                    DispatchQueue.main.asyncAfter(deadline: .now() + d) { [weak self] in
                        guard let self else { return }
                        guard fadeID == self.activeLoadID else {
                            print("xfade_cancelled_stale {\(fadeID)}")
                            return
                        }
                        self.currentNode.stop()
                        // Mute old mix path, flip, then enable new path
                        self.currentMixer.volume = 0.0

                        // Commit new state
                        if let oldNFT = self.currentNFT { self.previousAudio.tracks.append(oldNFT) }
                        _ = self.nextAudio.tracks.isEmpty ? nil : self.nextAudio.tracks.removeFirst()
                        self.currentNodeIsA.toggle()
                        // After toggle, currentMixer/nextMixer refer to new roles
                        self.currentMixer.volume = 1.0
                        self.nextMixer.volume = 0.0
                        // Set gains for new roles: active path ~-0.915 dB, inactive muted
                        self.currentGainUnit.setLinearGain(self.crossfadePeakGain)
                        self.nextGainUnit.setLinearGain(0.0)
                        self.audioFile = nextFile
                        self.seekPosition = 0
                        self.pausedAt = 0
                        self.currentNFT = next
                        self.currentTrack = Track(title: next.name, artist: next.artistName, duration: self.duration, imageUrl: next.image?.secureUrl ?? next.image?.originalUrl)
                        self.playbackState = .playing
                    }
                } catch {
                    print("xfade_cancelled_stale {\(fadeID)}")
                }
            }
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
            // If nothing in previous, restart current position or remain stopped
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
    
    // Added beginNewLoad(nft:) overload for actual load and play
    @MainActor
    private func beginNewLoad(nft: NFT) async {
        // Cancel any existing load and establish new active ID
        let loadID = await beginNewLoad()

        guard let url = nft.musicURL else {
            playbackState = .error
            lastError = .fileLoadFailed
            return
        }

        // Show upcoming track metadata while loading
        self.currentTrack = Track(
            title: nft.name,
            artist: nft.artistName,
            duration: 0,
            imageUrl: nft.image?.secureUrl ?? nft.image?.originalUrl
        )
        self.playbackState = .loading

        // Capture prior temp for cleanup if we succeed
        let previousTemp = self.tempAudioURL

        // Detach heavy work off the main actor
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            // Prepare a local URL (download if remote)
            var managedURL: URL?
            do {
                let localURL: URL
                if AudioEngine.shouldTreatAsRemote(url) {
                    localURL = try await AudioEngine.downloadToManagedTemp(from: url)
                    managedURL = localURL
                } else {
                    localURL = url
                }
                try Task.checkCancellation()

                // Open AVAudioFile off-main
                let file = try AVAudioFile(forReading: localURL)
                try Task.checkCancellation()

                // Hop to main to apply if still current
                try await MainActor.run {
                    guard loadID == self.activeLoadID else {
                        // Stale: cleanup and exit
                        if localURL != url { try? FileManager.default.removeItem(at: localURL) }
                        return
                    }

                    // Swap in new state
                    self.audioFile = file
                    self.seekPosition = 0
                    self.pausedAt = 0
                    self.currentNFT = nft
                    self.currentTrack = Track(title: nft.name, artist: nft.artistName, duration: self.duration, imageUrl: nft.image?.secureUrl ?? nft.image?.originalUrl)

                    // Update temp ownership and cleanup previous temp file
                    if AudioEngine.shouldTreatAsRemote(url) {
                        self.tempAudioURL = localURL
                        managedURL = localURL
                        if let prev = previousTemp, prev != localURL {
                            try? FileManager.default.removeItem(at: prev)
                        }
                    } else {
                        // No temp management for local files
                        self.tempAudioURL = nil
                    }

                    // Start playback now that file is ready
                    do { try self.play() } catch {
                        self.playbackState = .error
                        self.lastError = (error as? AudioEngineError) ?? .fileLoadFailed
                    }
                }
            } catch is CancellationError {
                // Cancelled: best-effort cleanup of any temp we created
                if let url = managedURL { try? FileManager.default.removeItem(at: url) }
            } catch {
                // Error: only report if still current
                await MainActor.run {
                    guard loadID == self.activeLoadID else { return }
                    self.playbackState = .error
                    self.lastError = (error as? AudioEngineError) ?? .fileLoadFailed
                }
            }
        }

        currentLoadTask = task
    }
    
    // Note: Replaced implementation with single-flight delegator
    public func loadAndPlay(nft: NFT) async throws {
        // Start a new single-flight load
        await beginNewLoad(nft: nft)
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
        
        mixerA.volume = 0.0
        mixerB.volume = 0.0
        gainA.setLinearGain(0.0)
        gainB.setLinearGain(0.0)
        
        audioEngine.detach(playerNodeA)
        audioEngine.detach(playerNodeB)
        audioEngine.detach(mixerA)
        audioEngine.detach(mixerB)
        audioEngine.detach(gainA)
        audioEngine.detach(gainB)
        
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
    private func scheduleCrossfadeIfPossible() {
        // If there's no upcoming track or no current file, do nothing
        guard !nextAudio.tracks.isEmpty, let audioFile = audioFile else { return }

        // Compute remaining time on the current file from the current seek position
        let sampleRate = audioFile.processingFormat.sampleRate
        let startFrame = AVAudioFramePosition(seekPosition * sampleRate)
        let remainingFrames = max(0, audioFile.length - startFrame)
        let remainingTime = Double(remainingFrames) / sampleRate

        // Auto-cap fade: min(configured, 30% of track length)
        let cappedFade = min(crossfadeDuration, max(0.0, 0.3 * (Double(audioFile.length) / sampleRate)))
        let overlap = min(cappedFade, max(0.0, remainingTime))
        guard overlap > 0 else { return }

        // Safety pad near the end to avoid underruns / render race
        let safety = crossfadeSafetyPad
        let fireIn = max(0.0, remainingTime - overlap - safety)

        // Prepare and schedule the next track to start at the computed node time with its mixer muted
        let fadeID = activeLoadID

        // Obtain current render time references
        guard let nodeTime = currentNode.lastRenderTime,
              let playerTime = currentNode.playerTime(forNodeTime: nodeTime) else { return }

        let framesUntilStart = AVAudioFramePosition((remainingTime - overlap - safety) * playerTime.sampleRate)
        let targetSampleTime = playerTime.sampleTime + framesUntilStart
        let targetPlayerTime = AVAudioTime(sampleTime: targetSampleTime, atRate: playerTime.sampleRate)

        // Pre-roll next track on its player; keep its mixer at 0.0
        let next = nextAudio.tracks.first!
        Task { @MainActor in
            do {
                guard fadeID == self.activeLoadID else {
                    print("xfade_cancelled_stale {\(fadeID)}")
                    return
                }
                guard let url = next.musicURL else { return }
                try self.ensureEngineReadyToPlay()

                // Prepare local URL (download if remote) for pre-roll
                let localURL: URL
                if AudioEngine.shouldTreatAsRemote(url) {
                    localURL = try await AudioEngine.downloadToManagedTemp(from: url)
                } else {
                    localURL = url
                }

                let nextFile = try AVAudioFile(forReading: localURL)

                // Keep next mixer silent until fade begins
                self.nextMixer.volume = 0.0
                self.nextGainUnit.setLinearGain(0.0)

                self.nextNode.stop()
                self.nextNode.scheduleFile(nextFile, at: targetPlayerTime, completionHandler: nil)
                self.nextNode.play()

                // Schedule a one-shot to trigger the fade at the computed time.
                // We convert framesUntilStart to seconds relative to now; minor drift expected <10ms.
                let secondsUntilStart = max(0.0, fireIn)
                DispatchQueue.main.asyncAfter(deadline: .now() + secondsUntilStart) { [weak self] in
                    guard let self else { return }
                    guard fadeID == self.activeLoadID else {
                        print("xfade_cancelled_stale {\(fadeID)}")
                        return
                    }
                    // Begin crossfade
                    self.performCrossfade(duration: overlap, from: self.currentMixer, to: self.nextMixer)

                    // After fade completes, stop previous player, reset its mixer, and flip roles
                    DispatchQueue.main.asyncAfter(deadline: .now() + overlap) { [weak self] in
                        guard let self else { return }
                        guard fadeID == self.activeLoadID else {
                            print("xfade_cancelled_stale {\(fadeID)}")
                            return
                        }
                        self.currentNode.stop()
                        // Mute old mix path, then flip roles and enable new path
                        self.currentMixer.volume = 0.0

                        // Commit new state
                        if let oldNFT = self.currentNFT { self.previousAudio.tracks.append(oldNFT) }
                        _ = self.nextAudio.tracks.isEmpty ? nil : self.nextAudio.tracks.removeFirst()
                        self.currentNodeIsA.toggle()
                        // After toggle, currentMixer/nextMixer refer to new roles
                        self.currentMixer.volume = 1.0
                        self.nextMixer.volume = 0.0
                        // Set gains for new roles: active path ~-0.915 dB, inactive muted
                        self.currentGainUnit.setLinearGain(self.crossfadePeakGain)
                        self.nextGainUnit.setLinearGain(0.0)
                        self.audioFile = nextFile
                        self.seekPosition = 0
                        self.pausedAt = 0
                        self.currentNFT = next
                        self.currentTrack = Track(title: next.name, artist: next.artistName, duration: self.duration, imageUrl: next.image?.secureUrl ?? next.image?.originalUrl)
                        self.playbackState = .playing
                    }
                }
            } catch is CancellationError {
                print("xfade_cancelled_stale {\(fadeID)}")
            } catch {
                // On error, mute both to safe state and attempt to advance normally
                self.currentMixer.volume = 0.0
                self.nextMixer.volume = 0.0
                Task { @MainActor in
                    await self.playNext()
                }
            }
        }
    }
}

