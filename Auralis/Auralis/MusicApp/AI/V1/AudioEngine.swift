//
//  AudioEngine.swift
//  Auralis
//
//  Created by Daniel Bell on 9/4/25.
//



import AVFoundation

@MainActor
class AudioEngine: ObservableObject {
    private var audioEngine = AVAudioEngine()
    private var playerNode = AVAudioPlayerNode()
    private var audioFile: AVAudioFile?
    private var pausedAt: TimeInterval = 0
    private var seekPosition: TimeInterval = 0
    
    enum PlaybackState {
        case stopped
        case playing
        case paused
        case loading
    }
    
    @Published var playbackState: PlaybackState = .stopped
    
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
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

    func canPlayFormat(_ url: URL) -> Bool {
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

        let fileExtension = url.pathExtension.lowercased()
        return supportedFormats.contains(fileExtension)
    }

    
    // MARK: - Audio Loading and Playback
    func loadAudio(from url: URL) throws {
        playbackState = .loading
        
        do {
            audioFile = try AVAudioFile(forReading: url)
            seekPosition = 0
            pausedAt = 0
            playbackState = .stopped
        } catch {
            playbackState = .stopped
            throw AudioEngineError.fileLoadFailed
        }
    }
    
    func play() throws {
        guard let audioFile = audioFile else { return }
        
        // Stop and clear any existing playback
        playerNode.stop()
        
        // Schedule from current seek position
        let sampleRate = audioFile.processingFormat.sampleRate
        let startFrame = AVAudioFramePosition(seekPosition * sampleRate)
        let remainingFrames = AVAudioFrameCount(audioFile.length - startFrame)
        
        playerNode.scheduleSegment(audioFile, startingFrame: startFrame, frameCount: remainingFrames, at: nil) {
            Task { @MainActor in
                if self.playbackState == .playing {
                    self.playbackState = .stopped
                }
            }
        }
        
        playerNode.play()
        playbackState = .playing
    }
    
    // Fixed pause implementation - AVAudioPlayerNode doesn't have pause()
    func pause() {
        guard playbackState == .playing else { return }
        pausedAt = currentTime
        playerNode.stop()
        playbackState = .paused
    }
    
    func resume() throws {
        guard playbackState == .paused else { return }
        seekPosition = pausedAt
        try play()
    }
    
    func stop() {
        playerNode.stop()
        seekPosition = 0
        pausedAt = 0
        playbackState = .stopped
    }
    
    // MARK: - Fixed Seek Functionality
    func seek(to time: TimeInterval) throws {
        guard let audioFile = audioFile else { return }
        
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
    func playNext() {
        // To be implemented with playlist integration
        stop()
    }
    
    func playPrevious() {
        // To be implemented with playlist integration
        stop()
    }
    
    func loadAndPlay(url: URL) throws {
        guard canPlayFormat(url) else {
            throw AudioEngineError.unsupportedFormat
        }
        
        try loadAudio(from: url)
        try play()
    }
    
    // MARK: - Improved Playback Information
    var currentTime: TimeInterval {
        switch playbackState {
        case .playing:
            // For playing state, calculate from node time + seek position
            guard let audioFile = audioFile,
                  let nodeTime = playerNode.lastRenderTime,
                  let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else {
                return seekPosition
            }
            return seekPosition + (Double(playerTime.sampleTime) / playerTime.sampleRate)
        case .paused:
            return pausedAt
        case .stopped, .loading:
            return seekPosition
        }
    }
    
    var duration: TimeInterval {
        guard let audioFile = audioFile else { return 0 }
        return Double(audioFile.length) / audioFile.processingFormat.sampleRate
    }
    
    // MARK: - Resource Cleanup
    deinit {
        NotificationCenter.default.removeObserver(self)
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        
        audioEngine.detach(playerNode)
        
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            // Log cleanup error but don't throw in deinit
        }
    }
}
