//
//  AudioEngine.swift
//  Auralis
//
//  Created by Daniel Bell on 9/4/25.
//

import AVFoundation
import Foundation
import MediaPlayer
import AVKit
import CoreGraphics
import ImageIO

// MARK: - Testability protocols and default adapters
protocol AudioSessioning {
    func setCategory(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode, options: AVAudioSession.CategoryOptions) throws
    func setActive(_ active: Bool) throws
    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws
    var currentRoute: AVAudioSessionRouteDescription { get }
    @available(iOS 26.0, *)
    func setPrefersInterruptionOnRouteDisconnect(_ flag: Bool) throws
}

struct DefaultAudioSession: AudioSessioning {
    private var session: AVAudioSession { AVAudioSession.sharedInstance() }
    func setCategory(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode, options: AVAudioSession.CategoryOptions) throws { try session.setCategory(category, mode: mode, options: options) }
    func setActive(_ active: Bool) throws { try session.setActive(active) }
    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws { try session.setActive(active, options: options) }
    var currentRoute: AVAudioSessionRouteDescription { session.currentRoute }
    @available(iOS 26.0, *)
    func setPrefersInterruptionOnRouteDisconnect(_ flag: Bool) throws { try session.setPrefersInterruptionOnRouteDisconnect(flag) }
}

protocol NowPlayingCentering {
    var nowPlayingInfo: [String: Any]? { get set }
}

struct DefaultNowPlayingCenter: NowPlayingCentering {
    var center: MPNowPlayingInfoCenter { MPNowPlayingInfoCenter.default() }
    var nowPlayingInfo: [String: Any]? {
        get { center.nowPlayingInfo }
        set { center.nowPlayingInfo = newValue }
    }
}

protocol RemoteCommandCentering {
    var playCommand: MPRemoteCommand { get }
    var pauseCommand: MPRemoteCommand { get }
    var togglePlayPauseCommand: MPRemoteCommand { get }
    var nextTrackCommand: MPRemoteCommand { get }
    var previousTrackCommand: MPRemoteCommand { get }
    var changePlaybackPositionCommand: MPChangePlaybackPositionCommand { get }
    var skipForwardCommand: MPSkipIntervalCommand { get }
    var skipBackwardCommand: MPSkipIntervalCommand { get }
}

struct DefaultRemoteCommands: RemoteCommandCentering {
    private var center: MPRemoteCommandCenter { MPRemoteCommandCenter.shared() }
    var playCommand: MPRemoteCommand { center.playCommand }
    var pauseCommand: MPRemoteCommand { center.pauseCommand }
    var togglePlayPauseCommand: MPRemoteCommand { center.togglePlayPauseCommand }
    var nextTrackCommand: MPRemoteCommand { center.nextTrackCommand }
    var previousTrackCommand: MPRemoteCommand { center.previousTrackCommand }
    var changePlaybackPositionCommand: MPChangePlaybackPositionCommand { center.changePlaybackPositionCommand }
    var skipForwardCommand: MPSkipIntervalCommand { center.skipForwardCommand }
    var skipBackwardCommand: MPSkipIntervalCommand { center.skipBackwardCommand }
}

protocol AudioFileCaching {
    func cachedURL(forRemote url: URL) async throws -> URL
    func localURL(forRemote url: URL) async throws -> URL
    // AE-003: Memory pressure hooks (no-op in default impl)
    func trimMemoryAggressively()
    func clearAll()
}

struct DefaultAudioFileCache: AudioFileCaching {
    func cachedURL(forRemote url: URL) async throws -> URL {
        let maybeURL = try await AudioFileCache.shared.cachedURL(forRemote: url)
        guard let url = maybeURL else {
            throw URLError(.fileDoesNotExist)
        }
        return url
    }
    func localURL(forRemote url: URL) async throws -> URL {
        try await AudioFileCache.shared.localURL(forRemote: url)
    }
    // AE-003 default no-ops replaced with calls to AudioFileCache actor
    func trimMemoryAggressively() { Task { await AudioFileCache.shared.trimMemoryAggressively() } }
    func clearAll() { Task { await AudioFileCache.shared.clearAll() } }
}

@MainActor
class AudioEngine: ObservableObject {
    private var audioEngine = AVAudioEngine()
    private var playerNodeA = AVAudioPlayerNode()
    private var playerNodeB = AVAudioPlayerNode()
    private let mixerA = AVAudioMixerNode()
    private let mixerB = AVAudioMixerNode()
    private var currentNodeIsA: Bool = true
    private var currentNode: AVAudioPlayerNode { currentNodeIsA ? playerNodeA : playerNodeB }
    private var nextNode: AVAudioPlayerNode { currentNodeIsA ? playerNodeB : playerNodeA }
    private var currentMixer: AVAudioMixerNode { currentNodeIsA ? mixerA : mixerB }
    private var nextMixer: AVAudioMixerNode { currentNodeIsA ? mixerB : mixerA }
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

    private var currentLoadTask: Task<Void, Never>?
    private var activeLoadID: UUID = .init()
    private let audioCache: AudioFileCaching
    private var nowPlayingCenter: NowPlayingCentering
    private var remoteCommands: RemoteCommandCentering
    private var nowPlayingInfo: [String: Any] = [:]
    private var nowPlayingUpdateTimer: Timer?
    private var remoteCommandsRegistered: Bool = false
    
    private var artworkLoadID: UUID = .init()
    private var nextPreloadTask: Task<Void, Never>? = nil
    private var nextPreloadToken: UUID = .init()
    private var preloadedNext: (nft: NFT, url: URL, file: AVAudioFile)? = nil

    // Testability toggles and DI
    private let isTesting: Bool
    private let timersDisabled: Bool
    private let remoteCommandsDisabled: Bool

    private let session: AudioSessioning

    // Optional artwork loader to plug in app's image pipeline/cache
    var artworkLoader: ((URL) async -> UIImage?)?

    // Allow callers to inject a loader at runtime
    func setArtworkLoader(_ loader: @escaping (URL) async -> UIImage?) {
        self.artworkLoader = loader
    }
    
    @Published var currentTrack: Track? = nil    
    @Published var playbackState: PlaybackState = .stopped
    @Published var lastError: AudioEngineError? = nil
    
    // Shuffle / Repeat support (PB-010)
    enum RepeatMode { case none, track, playlist }
    @Published var isShuffleEnabled: Bool = false
    @Published var repeatMode: RepeatMode = .none

    // Coarse skip configuration (PB-004)
    private let coarseSkipDefaultsKey = "AudioEngine.coarseSkipSeconds"
    @Published var coarseSkipSeconds: TimeInterval = 10 {
        didSet {
            // Persist and reflect in remote commands
            UserDefaults.standard.set(coarseSkipSeconds, forKey: coarseSkipDefaultsKey)
            updateRemoteSkipIntervals()
        }
    }

    private func updateRemoteSkipIntervals() {
        // Reflect the configured skip interval in Remote Command Center
        guard !remoteCommandsDisabled else { return }
        remoteCommands.skipForwardCommand.preferredIntervals = [coarseSkipSeconds as NSNumber]
        remoteCommands.skipBackwardCommand.preferredIntervals = [coarseSkipSeconds as NSNumber]
    }
    
    private var needsEngineStart: Bool = false
    
    private var suppressAutoAdvanceOnce: Bool = false
    
    // AE-006: Route-change context
    // Removed private var wasPlayingBeforeRouteChange: Bool = false
    
    // AE-006: Debounce and single-flight route-change handling
    private var routeChangeDebounceTask: Task<Void, Never>? = nil
    private var isReconfiguringRoute: Bool = false
    
    // AE-008: Simulator throttle to avoid reconfiguration churn
    private var lastRouteChangeHandledAt: TimeInterval = 0
    private let routeChangeThrottleSeconds: TimeInterval = 1.0
    
    // Computed property to eliminate state redundancy
    var isPlaying: Bool {
        playbackState == .playing
    }
    
    var progress: Double {
        return currentTime
    }
    
    enum PlaybackState {
        case stopped
        case playing
        case paused
        case loading
        case error
    }
    
    // AE-001: Retry / circuit breaker
    private let maxLoadRetries: Int = 2
    private let baseBackoffSeconds: TimeInterval = 0.75
    private var consecutiveFailureCount: Int = 0
    private let circuitBreakerThreshold: Int = 5

    // AE-001: user-visible notification name
    static let trackFailedNotification = Notification.Name("AudioEngine.trackFailed")

    // AE-001: recent error log (for QA/ops)
    private var recentLoadErrors: [String] = [] // capped in code
    private let recentErrorsCap = 50

    // AE-004: Deferred session deactivation timer
    private var sessionDeactivationTimer: Timer? = nil

    // AE-003: Memory pressure
    private var memoryWarningObserver: NSObjectProtocol? = nil
    private var thermalStateObserver: NSObjectProtocol? = nil
    
    // AE-011: Centralized state management and debounce
    private var lastCommandTimestamp: CFAbsoluteTime = 0
    private let commandDebounceInterval: TimeInterval = 0.3

    private func shouldDebounceCommands() -> Bool {
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastCommandTimestamp < commandDebounceInterval {
            print("[AE-011] Debounced rapid command (\(now - lastCommandTimestamp)s < \(commandDebounceInterval)s)")
            return true
        }
        lastCommandTimestamp = now
        return false
    }

    // Source of truth for playback state transitions
    private func commitPlaybackState(_ newState: PlaybackState, reason: String) {
        if playbackState == newState {
            print("[AE-011] No-op transition: \(playbackState) -> \(newState) [reason=\(reason)]")
            return
        }
        print("[AE-011] Transition: \(playbackState) -> \(newState) [reason=\(reason)]")
        playbackState = newState
        switch newState {
        case .playing:
            startNowPlayingTimer()
        case .paused, .stopped, .loading, .error:
            stopNowPlayingTimer()
        }
        updateRemoteCommandAvailability()
        updateNowPlayingMetadata()
    }
    
    // AE-012: Now Playing throttling and telemetry
    private let nowPlayingProgressInterval: TimeInterval = 5.0 // steady-state cadence
    private var isAppInBackground: Bool = false

    private struct NowPlayingSnapshot {
        var elapsed: Double = -1
        var rate: Double = -1
        var itemID: UUID? = nil
        var duration: Double = -1
    }
    private var lastPublishedNowPlaying = NowPlayingSnapshot()

    // Telemetry counters
    private var npPublishCount: Int = 0
    private var npSuppressedCount: Int = 0

    struct Track: Identifiable, Codable {
        var id = UUID()
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
    
    // MARK: - Now Playing & Remote Command Center
    private func setupNowPlayingAndRemoteCommands() {
        guard !remoteCommandsRegistered else { return }
        guard !remoteCommandsDisabled else { return }
        remoteCommandsRegistered = true

        let center = remoteCommands

        // Play
        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in
                guard !self.shouldDebounceCommands() else { return }
                if self.playbackState == .paused || self.playbackState == .stopped {
                    try? self.resume()
                } else if self.playbackState == .loading {
                    // ignore until loaded
                } else if self.playbackState == .error {
                    await self.playNext()
                }
            }
            return .success
        }

        // Pause
        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in
                guard !self.shouldDebounceCommands() else { return }
                self.pause()
            }
            return .success
        }

        // Toggle
        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in
                guard !self.shouldDebounceCommands() else { return }
                if self.playbackState == .playing { self.pause() } else { try? self.resume() }
            }
            return .success
        }

        // Next / Previous
        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in
                await self.playNext()
            }
            return .success
        }

        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in
                await self.playPrevious()
            }
            return .success
        }

        // Scrubbing
        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self, let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in
                try? self.seek(to: e.positionTime)
            }
            return .success
        }

        // Optional skip forward/back by interval
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: coarseSkipSeconds)]
        center.skipForwardCommand.isEnabled = true
        center.skipForwardCommand.addTarget { [weak self] event in
            guard let self, let e = event as? MPSkipIntervalCommandEvent else { return .commandFailed }
            Task { @MainActor in
                try? self.seek(to: self.currentTime + e.interval)
            }
            return .success
        }

        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: coarseSkipSeconds)]
        center.skipBackwardCommand.isEnabled = true
        center.skipBackwardCommand.addTarget { [weak self] event in
            guard let self, let e = event as? MPSkipIntervalCommandEvent else { return .commandFailed }
            Task { @MainActor in
                try? self.seek(to: self.currentTime - e.interval)
            }
            return .success
        }

        // Initial availability
        updateRemoteCommandAvailability()
        updateRemoteSkipIntervals()
    }

    private func setupMediaServicesNotifications() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleMediaServicesLost),
                                               name: AVAudioSession.mediaServicesWereLostNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleMediaServicesReset),
                                               name: AVAudioSession.mediaServicesWereResetNotification,
                                               object: nil)
    }
    
    private func setupAppLifecycleObservers() {
        #if os(iOS)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleWillEnterForeground),
                                               name: UIApplication.willEnterForegroundNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleDidEnterBackground),
                                               name: UIApplication.didEnterBackgroundNotification,
                                               object: nil)
        #endif
    }

    // AE-003: Memory & thermal observers
    private func setupMemoryAndThermalObservers() {
        #if os(iOS)
        memoryWarningObserver = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.handleMemoryPressure()
        }
        thermalStateObserver = NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            let state = ProcessInfo.processInfo.thermalState
            if state == .serious || state == .critical {
                self.handleMemoryPressure()
            }
        }
        #endif
    }

    private func handleMemoryPressure() {
        // Trim preloads and caches aggressively
        cancelNextPreload()
        preloadedNext = nil
        audioCache.trimMemoryAggressively()
        // If paused for a while, consider releasing current file handles
        if playbackState != .playing {
            audioFile = nil
        }
    }

    @objc private func handleWillEnterForeground() {
        isAppInBackground = false
        // Refresh Now Playing metadata to keep it accurate on return
        updateNowPlayingMetadata()
    }

    @objc private func handleDidEnterBackground() {
        isAppInBackground = true
        // Keep metadata fresh for background controls
        updateNowPlayingMetadata()
    }

    @objc private func handleMediaServicesLost() {
        // Mark for restart; pause to avoid undefined state
        needsEngineStart = true
        if playbackState == .playing { pause() }
    }

    @objc private func handleMediaServicesReset() {
        // Reconfigure session and engine on reset
        needsEngineStart = true
        do {
            try ensureSessionActive()
        } catch { }
        // If we were playing before, try to resume
        if playbackState == .paused { try? resume() }
    }

    private func startNowPlayingTimer() {
        guard !timersDisabled else { return }
        stopNowPlayingTimer()
        nowPlayingUpdateTimer = Timer.scheduledTimer(withTimeInterval: nowPlayingProgressInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.updateNowPlayingProgress()
        }
        RunLoop.main.add(nowPlayingUpdateTimer!, forMode: .common)
    }

    private func stopNowPlayingTimer() {
        nowPlayingUpdateTimer?.invalidate()
        nowPlayingUpdateTimer = nil
    }

    private func updateNowPlayingMetadata() {
        // Gate redundant metadata writes when app is backgrounded and playback is paused
        if isAppInBackground && playbackState == .paused { return }

        guard let currentTrack = currentTrack else { return }
        var info: [String: Any] = nowPlayingInfo
        let isLive = currentTrack.duration <= 0
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        info[MPNowPlayingInfoPropertyIsLiveStream] = isLive
        info[MPMediaItemPropertyPlaybackDuration] = isLive ? 0 : currentTrack.duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = progress
        info[MPNowPlayingInfoPropertyPlaybackRate] = (playbackState == .playing) ? 1.0 : 0.0
        info[MPMediaItemPropertyTitle] = currentTrack.title
        info[MPMediaItemPropertyArtist] = currentTrack.artist
        
        // AE-009: Downsample/resize images per requested size before returning from requestHandler; race-protected via activeLoadID
        let token = self.activeLoadID
        if let urlString = currentTrack.imageUrl, let url = URL(string: urlString) {
            Task.detached(priority: .utility) { [weak self] in
                guard let self else { return }
                let imageData: Data?
                if let loader = await self.artworkLoader {
                    // Use injected loader, convert to data without heavy UI work
                    if let image = await loader(url) {
                        imageData = image.pngData() ?? image.jpegData(compressionQuality: 0.9)
                    } else {
                        imageData = nil
                    }
                } else {
                    var req = URLRequest(url: url)
                    req.timeoutInterval = 15
                    do {
                        let (data, resp) = try await URLSession.shared.data(for: req)
                        try Task.checkCancellation()
                        if let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                            imageData = data
                        } else {
                            imageData = nil
                        }
                    } catch {
                        imageData = nil
                    }
                }

                // Build artwork with requestHandler that downsamples per requested size
                var updated = info
                if let data = imageData as NSData? as Data? {
                    let maxSize: CGSize = {
                        if let src = CGImageSourceCreateWithData(data as CFData, nil),
                           let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
                           let w = props[kCGImagePropertyPixelWidth] as? CGFloat,
                           let h = props[kCGImagePropertyPixelHeight] as? CGFloat {
                            return CGSize(width: w, height: h)
                        }
                        return CGSize(width: 1024, height: 1024)
                    }()

                    let artwork = MPMediaItemArtwork(boundsSize: maxSize) { requestedSize in
                        let scale = UIScreen.main.scale
                        let pixelMax = max(requestedSize.width, requestedSize.height) * scale
                        let options: [CFString: Any] = [
                            kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceShouldCache: false,
                            kCGImageSourceShouldCacheImmediately: false,
                            kCGImageSourceThumbnailMaxPixelSize: pixelMax
                        ]
                        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
                              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else {
                            return UIImage()
                        }
                        return UIImage(cgImage: cg, scale: scale, orientation: .up)
                    }
                    updated[MPMediaItemPropertyArtwork] = artwork
                }

                await MainActor.run {
                    guard token == self.activeLoadID else { return }
                    // Refresh snapshot for immediate-update coherence
                    let currentElapsed = self.progress
                    let currentRate = (self.playbackState == .playing) ? 1.0 : 0.0
                    let currentItemID = self.currentTrack?.id
                    let currentDuration = self.currentTrack?.duration ?? self.duration
                    self.lastPublishedNowPlaying = NowPlayingSnapshot(elapsed: currentElapsed, rate: currentRate, itemID: currentItemID, duration: currentDuration)

                    self.nowPlayingCenter.nowPlayingInfo = updated
                    self.nowPlayingInfo = updated
                    self.updateRemoteCommandAvailability()
                }
            }
        } else {
            // Refresh snapshot for immediate-update coherence
            let currentElapsed = progress
            let currentRate = (playbackState == .playing) ? 1.0 : 0.0
            let currentItemID = currentTrack.id
            let currentDuration = currentTrack.duration
            lastPublishedNowPlaying = NowPlayingSnapshot(elapsed: currentElapsed, rate: currentRate, itemID: currentItemID, duration: currentDuration)

            nowPlayingCenter.nowPlayingInfo = info
            nowPlayingInfo = info
            updateRemoteCommandAvailability()
        }
    }

    private func updateNowPlayingProgress() {
        // Only publish periodic progress during active playback
        guard playbackState == .playing else { return }
        // Avoid unnecessary writes if app is backgrounded and not actively playing (already guarded)
        guard nowPlayingCenter.nowPlayingInfo != nil else { return }

        let currentElapsed = progress
        let currentRate = (playbackState == .playing) ? 1.0 : 0.0
        let currentItemID = currentTrack?.id
        let currentDuration = currentTrack?.duration ?? duration

        // Duplicate suppression: if values haven't meaningfully changed, skip
        let elapsedDelta = abs(currentElapsed - lastPublishedNowPlaying.elapsed)
        let isSameItem = (currentItemID == lastPublishedNowPlaying.itemID)
        let isSameRate = (currentRate == lastPublishedNowPlaying.rate)
        let isSameDuration = (currentDuration == lastPublishedNowPlaying.duration)

        if isSameItem && isSameRate && isSameDuration && elapsedDelta < 0.5 {
            npSuppressedCount += 1
            print("[AE-012] Suppressed duplicate progress update (suppressed=\(npSuppressedCount))")
            return
        }

        var info = nowPlayingInfo
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentElapsed
        info[MPNowPlayingInfoPropertyPlaybackRate] = currentRate
        nowPlayingCenter.nowPlayingInfo = info
        nowPlayingInfo = info

        // Update snapshot and telemetry
        lastPublishedNowPlaying = NowPlayingSnapshot(elapsed: currentElapsed, rate: currentRate, itemID: currentItemID, duration: currentDuration)
        npPublishCount += 1
        print("[AE-012] Published progress update (count=\(npPublishCount))")

        updateRemoteCommandAvailability()
    }
    
    private func updateRemoteCommandAvailability() {
        // Next/Previous availability based on queues and repeat mode
        let canAdvance = !nextAudio.tracks.isEmpty || repeatMode != .none
        remoteCommands.nextTrackCommand.isEnabled = canAdvance
        remoteCommands.previousTrackCommand.isEnabled = !previousAudio.tracks.isEmpty || (seekPosition > 1.0)

        // Scrubbing and skip only when we have a determinate duration (non-live)
        let hasDuration = duration > 0
        remoteCommands.changePlaybackPositionCommand.isEnabled = hasDuration
        remoteCommands.skipForwardCommand.isEnabled = hasDuration
        remoteCommands.skipBackwardCommand.isEnabled = hasDuration
    }
    
    private func cancelNextPreload() {
        nextPreloadTask?.cancel()
        nextPreloadTask = nil
        nextPreloadToken = UUID()
        preloadedNext = nil
    }

    private func triggerPreloadForNextIfNeeded() {
        // Only when currently playing and we don't already have a preload
        guard playbackState == .playing else { return }
        guard preloadedNext == nil else { return }
        guard let next = peekNextTrackRespectingModes(), let url = next.musicURL else { return }

        // Start a new preload task
        cancelNextPreload()
        let token = UUID()
        nextPreloadToken = token
        nextPreloadTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            do {
                let localURL: URL
                if AudioEngine.shouldTreatAsRemote(url) {
                    localURL = try await self.audioCache.localURL(forRemote: url)
                } else {
                    localURL = url
                }
                try Task.checkCancellation()
                let file = try AVAudioFile(forReading: localURL) // header/format validation only
                try Task.checkCancellation()
                await MainActor.run {
                    guard token == self.nextPreloadToken else { return }
                    self.preloadedNext = (nft: next, url: localURL, file: file)
                }
            } catch {
                // Ignore preload failures; playback path will attempt normal load
            }
        }
    }
    
    // MARK: - Loading Helpers (non-isolated)
    nonisolated internal static func shouldTreatAsRemote(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
    
    nonisolated private static func downloadToManagedTemp(from url: URL) async throws -> URL {
        // Maintain signature for existing call sites but route via AudioFileCache.
        if let cachedOpt = try? await AudioFileCache.shared.cachedURL(forRemote: url) {
            return cachedOpt
        }
        // Fallback: use cache to download and store
        let local = try await AudioFileCache.shared.localURL(forRemote: url)
        return local
    }

    nonisolated private static func cleanupLegacyTempDir() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("AudioLoads", isDirectory: true)
        // Best-effort removal; ignore errors if directory doesn't exist or is in use
        try? FileManager.default.removeItem(at: dir)
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
    
    // AE-001: Retry & backoff loading helper
    @MainActor
    private func loadAndPlayWithRetry(nft: NFT) async {
        consecutiveFailureCount = min(consecutiveFailureCount, circuitBreakerThreshold) // clamp
        var attempt = 0
        while attempt <= maxLoadRetries {
            let currentAttempt = attempt
            do {
                try await loadAndPlay(nft: nft)
                // success: reset counters and return
                consecutiveFailureCount = 0
                return
            } catch is CancellationError {
                // A newer request superseded this one; just return
                return
            } catch {
                consecutiveFailureCount += 1
                let desc = (error as NSError).localizedDescription
                recentLoadErrors.append("attempt=\(currentAttempt) error=\(desc)")
                if recentLoadErrors.count > recentErrorsCap { recentLoadErrors.removeFirst(recentLoadErrors.count - recentErrorsCap) }
                // Circuit breaker
                if consecutiveFailureCount >= circuitBreakerThreshold { break }
                // Backoff and retry if attempts remain
                if currentAttempt < maxLoadRetries {
                    let backoff = baseBackoffSeconds * pow(2.0, Double(currentAttempt))
                    try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                    attempt += 1
                    continue
                }
                break
            }
        }
        // Notify user on failure
        NotificationCenter.default.post(name: AudioEngine.trackFailedNotification, object: nil)
    }
    
    init(testing: Bool = false,
         disableRemoteCommands: Bool = true,
         disableTimers: Bool = true,
         session: AudioSessioning = DefaultAudioSession(),
         nowPlayingCenter: NowPlayingCentering = DefaultNowPlayingCenter(),
         remoteCommands: RemoteCommandCentering = DefaultRemoteCommands(),
         audioCache: AudioFileCaching = DefaultAudioFileCache()) throws {
        self.isTesting = testing
        self.timersDisabled = disableTimers
        self.remoteCommandsDisabled = disableRemoteCommands
        self.session = session
        self.nowPlayingCenter = nowPlayingCenter
        self.remoteCommands = remoteCommands
        self.audioCache = audioCache

        try setupAudioSession()
        try setupAudioEngine()
        setupInterruptionHandling()
        // Load persisted coarse skip interval if available
        if let storedSkip = UserDefaults.standard.object(forKey: coarseSkipDefaultsKey) as? Double {
            coarseSkipSeconds = storedSkip
        }
        AudioEngine.cleanupLegacyTempDir()
        if !remoteCommandsDisabled {
            setupNowPlayingAndRemoteCommands()
            updateRemoteSkipIntervals()
        }
        if !isTesting {
            setupMediaServicesNotifications()
            setupAppLifecycleObservers()
            setupMemoryAndThermalObservers()
        }
    }
    
    // MARK: - Audio Session Configuration
    private func setupAudioSession() throws {
        let session = self.session
        do {
            // Removed .mixWithOthers for proper music app behavior
            try session.setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetoothA2DP])
            try session.setActive(true)
            
            if #available(iOS 26.0, *) {
                do {
                    try session.setPrefersInterruptionOnRouteDisconnect(true)
                } catch {
                    print("[AE-006] Failed to set prefersInterruptionOnRouteDisconnect: \(error)")
                }
            }
            
        } catch {
            throw AudioEngineError.sessionSetupFailed
        }
    }
    
    // MARK: - Audio Engine Setup
    private func setupAudioEngine() throws {
        audioEngine.attach(playerNodeA)
        audioEngine.attach(playerNodeB)
        audioEngine.attach(mixerA)
        audioEngine.attach(mixerB)

        // Normalize formats to the engine's output format to avoid conversion issues
        let outFormat = audioEngine.outputNode.inputFormat(forBus: 0)

        // player A → mixer A → main mixer
        audioEngine.connect(playerNodeA, to: mixerA, format: outFormat)
        audioEngine.connect(mixerA, to: audioEngine.mainMixerNode, format: outFormat)

        // player B → mixer B → main mixer
        audioEngine.connect(playerNodeB, to: mixerB, format: outFormat)
        audioEngine.connect(mixerB, to: audioEngine.mainMixerNode, format: outFormat)

        // Start silent by default
        mixerA.volume = 0.0
        mixerB.volume = 0.0

        audioEngine.prepare()
    }
    
    // MARK: - Engine Start Guarantees
    @MainActor
    private func ensureSessionActive() throws {
        let session = self.session
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

            // Ensure mix path is audible after engine start
            if playbackState == .playing {
                currentMixer.volume = 1.0
                nextMixer.volume = 0.0
            }

            return
        } catch {
            // Attempt minimal recovery then retry once
            audioEngine.stop()
            audioEngine.reset()
            audioEngine.prepare()
            do {
                try audioEngine.start()
                needsEngineStart = false

                // Ensure mix path is audible after engine start
                if playbackState == .playing {
                    currentMixer.volume = 1.0
                    nextMixer.volume = 0.0
                }

                return
            } catch {
                throw AudioEngineError.engineStartFailed(underlying: error)
            }
        }
    }
    
    // AE-004: Defer session deactivation
    private func scheduleDeferredSessionDeactivation(delay: TimeInterval = 45) {
        guard !timersDisabled else { return }
        sessionDeactivationTimer?.invalidate()
        sessionDeactivationTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self else { return }
            // Only deactivate if not playing at the time of firing
            if self.playbackState != .playing {
                do { try self.session.setActive(false, options: [.notifyOthersOnDeactivation]) } catch { }
            }
        }
        RunLoop.main.add(sessionDeactivationTimer!, forMode: .common)
    }

    private func cancelDeferredSessionDeactivation() {
        sessionDeactivationTimer?.invalidate()
        sessionDeactivationTimer = nil
    }

    // MARK: - Precise Crossfade Ramping (AE-007)
    // High-priority queue for volume ramps and crossfade coordination
    private let rampQueue = DispatchQueue(label: "audio.ramp.queue", qos: .userInteractive, attributes: [], autoreleaseFrequency: .workItem)

    // Cancellable timers per mixer and for crossfade stages
    private var rampTimers: [ObjectIdentifier: DispatchSourceTimer] = [:]
    private var crossfadeStartTimer: DispatchSourceTimer? = nil
    private var crossfadeFlipTimer: DispatchSourceTimer? = nil

    // Cancel and clear all ramp timers (call on main actor when mutating mixer volumes/state)
    @MainActor
    private func cancelAllRampTimers() async {
        for (_, t) in rampTimers { t.cancel() }
        rampTimers.removeAll()
        crossfadeStartTimer?.cancel(); crossfadeStartTimer = nil
        crossfadeFlipTimer?.cancel(); crossfadeFlipTimer = nil
    }

    // Cancel ramp for a specific mixer
    @MainActor
    private func cancelRamp(for mixer: AVAudioMixerNode) {
        let id = ObjectIdentifier(mixer)
        if let t = rampTimers[id] { t.cancel() }
        rampTimers[id] = nil
    }

    // Lightweight ramp on mixer.volume driven by a background DispatchSourceTimer (~180 Hz)
    // Anchored to current uptime clock; short-lived (<= 10s) to minimize drift.
    @MainActor
    private func rampMixer(_ mixer: AVAudioMixerNode, to target: Float, duration: TimeInterval) {
        let d = max(0.05, min(duration, 10.0))
        if timersDisabled {
            mixer.volume = target
            return
        }

        // Cancel any existing ramp for this mixer
        cancelRamp(for: mixer)

        let id = ObjectIdentifier(mixer)
        let startVol = mixer.volume
        let delta = target - startVol
        if abs(delta) < 0.0001 {
            mixer.volume = target
            return
        }

        let intervalHz: Double = 180.0
        let tick = 1.0 / intervalHz
        let timer = DispatchSource.makeTimerSource(flags: [], queue: rampQueue)
        let start = DispatchTime.now()

        timer.setEventHandler { [weak self] in
            guard let self else { return }
            // Compute elapsed using uptime to avoid wall-clock drift
            let now = DispatchTime.now()
            let elapsedNs = now.uptimeNanoseconds &- start.uptimeNanoseconds
            let elapsed = Double(elapsedNs) / 1_000_000_000.0
            if elapsed >= d {
                // Finalize on main to keep property writes consistent with UI state
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    mixer.volume = target
                    self.cancelRamp(for: mixer)
                }
                return
            }
            let progress = Float(elapsed / d)
            let newVol = startVol + delta * progress
            DispatchQueue.main.async {
                mixer.volume = newVol
            }
        }

        // Minimal leeway for smoother ramps; schedule immediately
        timer.schedule(deadline: .now(), repeating: tick, leeway: .milliseconds(1))
        timer.resume()
        rampTimers[id] = timer
    }

    // Helper to schedule a one-shot at a specific hostTime (mach absolute).
    // Returns a configured DispatchSourceTimer stored in the provided reference.
    @MainActor
    private func scheduleOneShot(atHostTime hostTime: UInt64, storeIn slot: inout DispatchSourceTimer?, handler: @escaping () -> Void) {
        // Cancel any existing timer in the slot
        slot?.cancel(); slot = nil
        let timer = DispatchSource.makeTimerSource(flags: [], queue: rampQueue)
        let deadline = DispatchTime(uptimeNanoseconds: hostTime)
        timer.setEventHandler(handler: handler)
        timer.schedule(deadline: deadline, leeway: .milliseconds(1))
        timer.resume()
        slot = timer
    }

    @MainActor
    func performCrossfade(duration: TimeInterval,
                          from from: AVAudioMixerNode,
                          to to: AVAudioMixerNode) {
        // AE-002: Use native ramp if available, else fall back to timers
        let d = max(0.05, min(duration, 10.0))
        if timersDisabled {
            to.volume = crossfadePeakGain
            from.volume = 0.0
            return
        }
        // Prefer native ramp if available via KVC to avoid main-thread timers
        if to.responds(to: Selector(("setVolume:rampDuration:"))) && from.responds(to: Selector(("setVolume:rampDuration:"))) {
            // This selector is not public API in Swift; guard with responds(to:) and fall back if not present.
            // Use perform to avoid compile-time errors if selector is unavailable on some OS versions.
            _ = (to as AnyObject).perform(Selector(("setVolume:rampDuration:")), with: crossfadePeakGain as NSNumber, with: d as NSNumber)
            _ = (from as AnyObject).perform(Selector(("setVolume:rampDuration:")), with: 0.0 as NSNumber, with: d as NSNumber)
        } else {
            rampMixer(to, to: crossfadePeakGain, duration: d)
            rampMixer(from, to: 0.0, duration: d)
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
                    try self.session.setActive(true)
                } catch {
                    return
                }
                
                guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else {
                    return
                }
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) && playbackState == .paused {
                    try? resume()
                    self.updateNowPlayingMetadata()
                }
            @unknown default:
                break
            }
        }
    }
    
    @objc private func handleRouteChange(notification: Notification) {
        let session = self.session
        let userInfo = notification.userInfo ?? [:]

        // Removed wasPlayingBeforeRouteChange = (playbackState == .playing)

        // Read reason and previous route
        let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
        let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) ?? .unknown
        let previousRoute = userInfo[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription

        // AE-008: Immediate pause on unplug (no debounce)
        if reason == .oldDeviceUnavailable {
            Task { @MainActor in
                self.handleDeviceDisconnection(previousRoute: previousRoute ?? AVAudioSessionRouteDescription())
            }
        }

        // Log for QA
        logRouteChange(reason: reason, previous: previousRoute, current: session.currentRoute)

        // Removed unconditional needsEngineStart line to prevent unnecessary full resets

        // Debounce: cancel any in-flight handler and schedule a new one
        routeChangeDebounceTask?.cancel()
        routeChangeDebounceTask = Task { [weak self] in
            // Debounce window 200ms to collapse cascades
            try? await Task.sleep(nanoseconds: 200_000_000)
            await MainActor.run {
                guard let self = self else { return }
                // AE-008: Debounced handling without auto-resume
                switch reason {
                case .oldDeviceUnavailable:
                    // Already paused immediately; perform conservative reconfigure only
                    self.needsEngineStart = true
                    self.reaffirmRouteAndResume()
                case .categoryChange, .newDeviceAvailable, .routeConfigurationChange, .override, .wakeFromSleep, .noSuitableRouteForCategory, .unknown:
                    // Simulator guard to avoid churn
                    #if targetEnvironment(simulator)
                    let now = CFAbsoluteTimeGetCurrent()
                    if now - self.lastRouteChangeHandledAt < self.routeChangeThrottleSeconds {
                        print("[AE-008] Simulator: throttling route change handling")
                        return
                    }
                    self.lastRouteChangeHandledAt = now
                    #endif
                    self.needsEngineStart = true
                    self.reaffirmRouteAndResume()
                @unknown default:
                    self.needsEngineStart = true
                    self.reaffirmRouteAndResume()
                }
            }
        }
    }
    
    // AE-006: Pause-on-unplug for specific outputs
    private func handleDeviceDisconnection(previousRoute: AVAudioSessionRouteDescription) {
        for output in previousRoute.outputs {
            switch output.portType {
            case .headphones, .bluetoothA2DP, .airPlay:
                // Immediate pause and UI update
                if playbackState == .playing { pause() }
                updateNowPlayingMetadata()
                return
            default:
                continue
            }
        }
    }

    // AE-006: Reconfigure engine/session for current route (AirPlay, Bluetooth, sample rate changes)
    @MainActor
    private func reconfigureForCurrentRoute() {
        let session = self.session

        if isReconfiguringRoute { return }
        isReconfiguringRoute = true
        defer { isReconfiguringRoute = false }

        // Ensure playback category with AirPlay/Bluetooth A2DP
        do {
            try session.setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetoothA2DP])
            try session.setActive(true)
        } catch {
            print("[AE-006] Session reconfig failed: \(error)")
        }

        // Handle potential output format changes (sample rate / channels)
        // Reset the engine graph to the new output format
        let outFormat = audioEngine.outputNode.inputFormat(forBus: 0)
        audioEngine.stop()
        audioEngine.reset()

        // Reconnect nodes to main mixer using the output format to avoid conversions
        audioEngine.disconnectNodeOutput(playerNodeA)
        audioEngine.disconnectNodeOutput(playerNodeB)
        audioEngine.disconnectNodeOutput(mixerA)
        audioEngine.disconnectNodeOutput(mixerB)

        audioEngine.connect(playerNodeA, to: mixerA, format: outFormat)
        audioEngine.connect(mixerA, to: audioEngine.mainMixerNode, format: outFormat)

        audioEngine.connect(playerNodeB, to: mixerB, format: outFormat)
        audioEngine.connect(mixerB, to: audioEngine.mainMixerNode, format: outFormat)

        audioEngine.prepare()
        do {
            try audioEngine.start()
            needsEngineStart = false
        } catch {
            print("[AE-006] Engine restart failed after route change: \(error)")
            needsEngineStart = true
        }

        // If currently routed to AirPlay, ensure gains are safe and UI is up-to-date
        let isAirPlay = session.currentRoute.outputs.contains { $0.portType == .airPlay }
        if isAirPlay {
            // Nothing special required beyond session options; ensure metadata is fresh
            updateNowPlayingMetadata()
        }
    }

    // AE-006: Logging helper for QA
    private func logRouteChange(reason: AVAudioSession.RouteChangeReason,
                                previous: AVAudioSessionRouteDescription?,
                                current: AVAudioSessionRouteDescription) {
        func describe(_ route: AVAudioSessionRouteDescription?) -> String {
            guard let route else { return "nil" }
            let outs = route.outputs.map { "\($0.portType.rawValue):\($0.portName)" }.joined(separator: ", ")
            let ins = route.inputs.map { "\($0.portType.rawValue):\($0.portName)" }.joined(separator: ", ")
            return "outs=[\(outs)] ins=[\(ins)]"
        }
        print("[AE-006] Route change reason=\(reason.rawValue) prev=\(describe(previous)) curr=\(describe(current))")
    }
    
    @MainActor
    private func reaffirmRouteAndResume() {
        // Gate against overlapping reconfigurations
        if isReconfiguringRoute { return }
        isReconfiguringRoute = true
        defer { isReconfiguringRoute = false }

        do {
            try ensureSessionActive()
        } catch {
            // If we cannot ensure the session, attempt a full reset as a last resort
            fullReset()
            return
        }

        // Only rebuild if output format changed in sample rate or channel count
        let currentOut = audioEngine.outputNode.inputFormat(forBus: 0)
        let mainOut = audioEngine.mainMixerNode.outputFormat(forBus: 0)
        let formatChanged = (currentOut.sampleRate != mainOut.sampleRate) || (currentOut.channelCount != mainOut.channelCount)

        // If engine isn't running, start it; if it is, we can leave it as-is
        if !audioEngine.isRunning {
            do {
                try audioEngine.start()
                needsEngineStart = false
            } catch {
                // As a fallback, perform a full reset to rebuild the graph cleanly
                fullReset()
                return
            }
        } else if formatChanged {
            reconfigureForCurrentRoute()
        }

        // Re-apply mixer volumes in case they were affected by the route change
        if playbackState == .playing {
            currentMixer.volume = 1.0
            nextMixer.volume = 0.0
        }

        // Removed auto-resume after route change:
        // if wasPlayingBeforeRouteChange && playbackState == .paused {
        //     try? resume()
        // }

        updateNowPlayingMetadata()
    }

    @MainActor
    private func fullReset() {
        // Stop timers and nodes to reach a safe state
        stopNowPlayingTimer()
        playerNodeA.stop()
        playerNodeB.stop()
        mixerA.volume = 0.0
        mixerB.volume = 0.0

        // Stop and reset the engine
        audioEngine.pause()
        audioEngine.stop()
        audioEngine.reset()

        // Disconnect and detach existing nodes to avoid stale connections
        audioEngine.disconnectNodeOutput(playerNodeA)
        audioEngine.disconnectNodeOutput(playerNodeB)
        audioEngine.disconnectNodeOutput(mixerA)
        audioEngine.disconnectNodeOutput(mixerB)

        audioEngine.detach(playerNodeA)
        audioEngine.detach(playerNodeB)
        audioEngine.detach(mixerA)
        audioEngine.detach(mixerB)

        // Recreate fresh nodes and reattach
        playerNodeA = AVAudioPlayerNode()
        playerNodeB = AVAudioPlayerNode()
        // Keep mixers instances but ensure they are attached
        // (They are constants; detach/attach existing instances)
        audioEngine.attach(playerNodeA)
        audioEngine.attach(playerNodeB)
        audioEngine.attach(mixerA)
        audioEngine.attach(mixerB)

        // Reconnect using the current output format to avoid conversions
        let outFormat = audioEngine.outputNode.inputFormat(forBus: 0)
        audioEngine.connect(playerNodeA, to: mixerA, format: outFormat)
        audioEngine.connect(mixerA, to: audioEngine.mainMixerNode, format: outFormat)

        audioEngine.connect(playerNodeB, to: mixerB, format: outFormat)
        audioEngine.connect(mixerB, to: audioEngine.mainMixerNode, format: outFormat)

        audioEngine.prepare()
        do {
            try audioEngine.start()
            needsEngineStart = false
        } catch {
            // Mark for later restart; caller will handle resume paths
            needsEngineStart = true
        }

        // If there is an audio file loaded and we were playing, restart playback
        if playbackState == .playing {
            try? play()
        } else if playbackState == .paused {
            // Keep paused state but ensure metadata and availability are correct
            updateRemoteCommandAvailability()
            updateNowPlayingMetadata()
        }
    }

    internal func canPlayFormat(_ url: URL) -> Bool {
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

    
    // MARK: - Queue Helpers (Shuffle/Repeat)
    internal func peekNextTrackRespectingModes() -> NFT? {
        // Repeat the same track
        if repeatMode == .track, let current = currentNFT {
            return current
        }

        // If we have items queued, either pick first (ordered) or random (shuffle)
        if !nextAudio.tracks.isEmpty {
            if isShuffleEnabled {
                return nextAudio.tracks.randomElement()
            } else {
                return nextAudio.tracks.first
            }
        }

        // If we’re out of items and repeat is playlist, derive a virtual next from history + current
        if repeatMode == .playlist {
            var rebuilt: [NFT] = []
            if let current = currentNFT { rebuilt.append(current) }
            if !previousAudio.tracks.isEmpty { rebuilt.append(contentsOf: previousAudio.tracks) }
            guard !rebuilt.isEmpty else { return nil }
            return isShuffleEnabled ? rebuilt.randomElement() : rebuilt.first
        }

        // No next track and repeat is none
        return nil
    }

    @discardableResult
    internal func dequeueNextTrackRespectingModes() -> NFT? {
        // Repeat the same track (no queue mutation)
        if repeatMode == .track, let current = currentNFT {
            return current
        }

        // If items are present in next queue
        if !nextAudio.tracks.isEmpty {
            if isShuffleEnabled {
                let idx = Int.random(in: 0..<nextAudio.tracks.count)
                return nextAudio.tracks.remove(at: idx)
            } else {
                return nextAudio.tracks.removeFirst()
            }
        }

        // Rebuild next queue from history + current for repeat-playlist
        if repeatMode == .playlist {
            var rebuilt: [NFT] = []
            if let current = currentNFT { rebuilt.append(current) }
            if !previousAudio.tracks.isEmpty { rebuilt.append(contentsOf: previousAudio.tracks) }
            guard !rebuilt.isEmpty else { return nil }

            // Reset queues so we start fresh for the next cycle
            previousAudio.tracks.removeAll()
            nextAudio.tracks = rebuilt

            if isShuffleEnabled {
                let idx = Int.random(in: 0..<nextAudio.tracks.count)
                return nextAudio.tracks.remove(at: idx)
            } else {
                return nextAudio.tracks.removeFirst()
            }
        }

        // Nothing else to play
        return nil
    }
    
    // MARK: - Audio Loading and Playback
    private func loadAudio(from url: URL, title: String?, artist: String?, imageUrl: String?, loadID: UUID) async throws {
        commitPlaybackState(.loading, reason: "loadAudio begin")
        
        guard loadID == activeLoadID else { throw CancellationError() }
        
        // No temp cleanup needed here; cached files persist
        
        let localURL: URL
        
        if AudioEngine.shouldTreatAsRemote(url) {
            let cachedURL = try await self.audioCache.localURL(forRemote: url)
            try Task.checkCancellation()
            guard loadID == activeLoadID else { throw CancellationError() }
            localURL = cachedURL
        } else {
            localURL = url
        }
        
        try Task.checkCancellation()
        guard loadID == activeLoadID else { throw CancellationError() }
        
        do {
            audioFile = try AVAudioFile(forReading: localURL)
            seekPosition = 0
            pausedAt = 0
            commitPlaybackState(.stopped, reason: "loadAudio prepared")
            currentTrack = Track(title: title, artist: artist, duration: self.duration, imageUrl: imageUrl)
            updateNowPlayingMetadata()
        } catch {
            commitPlaybackState(.error, reason: "loadAudio failed")
            lastError = .fileLoadFailed
            throw AudioEngineError.fileLoadFailed
        }
    }
    
    public func play() throws {
        cancelNextPreload()
        cancelDeferredSessionDeactivation()
        
        // AE-011: Idempotent guard
        if playbackState == .playing {
            print("[AE-011] play() no-op: already playing")
            return
        }
        
        // If no audio file is loaded, try to advance to the next queued item
        guard let audioFile = audioFile else {
            commitPlaybackState(.loading, reason: "play() with no file; advancing to next")
            Task { @MainActor in
                await self.playNext()
            }
            return
        }

        if isTesting {
            // In test mode, simulate immediate playback without relying on AVAudioEngine runtime
            currentMixer.volume = 1.0
            nextMixer.volume = 0.0
            commitPlaybackState(.playing, reason: "play() test mode")
            scheduleCrossfadeIfPossible()
            self.triggerPreloadForNextIfNeeded()
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
            commitPlaybackState(.loading, reason: "play() reached end; advancing to next")
            Task { @MainActor in
                await self.playNext()
            }
            return
        }

        currentNode.scheduleSegment(audioFile, startingFrame: startFrame, frameCount: remainingFrames, at: nil) {
            Task { @MainActor in
                // AE-004: Suppress Double Auto-Advance
                if self.suppressAutoAdvanceOnce {
                    self.suppressAutoAdvanceOnce = false
                    return
                }
                if self.playbackState == .playing {
                    self.commitPlaybackState(.stopped, reason: "segment completed")
                    // AE-003: Release file handle before advancing
                    self.audioFile = nil
                    // Auto-advance to next item in the next queue if available
                    await self.playNext()
                }
            }
        }

        currentNode.play()
        // Ensure path gain: enable active mixer, mute inactive
        currentMixer.volume = 1.0
        nextMixer.volume = 0.0
        commitPlaybackState(.playing, reason: "play() scheduled and started")
        scheduleCrossfadeIfPossible()
        self.triggerPreloadForNextIfNeeded()
    }
    
    // Fixed pause implementation - AVAudioPlayerNode doesn't have pause()
    public func pause() {
        // AE-011: Idempotent pause
        guard playbackState == .playing else {
            print("[AE-011] pause() no-op: state=\(playbackState)")
            updateRemoteCommandAvailability()
            updateNowPlayingMetadata()
            return
        }
        pausedAt = currentTime
        playerNodeA.stop()
        playerNodeB.stop()
        commitPlaybackState(.paused, reason: "pause() invoked")
        Task { @MainActor in await cancelAllRampTimers() }
    }
    
    public func resume() throws {
        // AE-011: Idempotent resume
        guard playbackState == .paused else {
            print("[AE-011] resume() no-op: state=\(playbackState)")
            return
        }
        cancelDeferredSessionDeactivation()
        seekPosition = pausedAt
        try play()
    }
    
    private func stop() {
        playerNodeA.stop()
        playerNodeB.stop()
        mixerA.volume = 0.0
        mixerB.volume = 0.0
        seekPosition = 0
        pausedAt = 0
        commitPlaybackState(.stopped, reason: "stop() invoked")
        Task { @MainActor in await cancelAllRampTimers() }
        // AE-004: Defer session deactivation to avoid glitches
        scheduleDeferredSessionDeactivation()
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
        Task { @MainActor in await cancelAllRampTimers() }
        
        // Update seek position
        seekPosition = clampedTime
        pausedAt = clampedTime
        
        // If we were playing, restart from new position immediately and reflect intent in state
        if wasPlaying {
            playbackState = .playing
            try play()
        } else {
            // Only update progress/availability immediately if not resuming playback
            updateNowPlayingMetadata()
            updateRemoteCommandAvailability()
        }
    }

    // MARK: - Coarse Skip Helpers
    public func skipForward(seconds: TimeInterval? = nil) {
        let delta = seconds ?? coarseSkipSeconds
        try? seek(to: currentTime + delta)
    }

    public func skipBackward(seconds: TimeInterval? = nil) {
        let delta = seconds ?? coarseSkipSeconds
        try? seek(to: currentTime - delta)
    }
    
    // MARK: - Playlist Navigation
    @MainActor
    public func playNext() async {
        cancelNextPreload()
        
        // Repeat-track: restart current track from beginning without crossfade
        if repeatMode == .track {
            try? self.seek(to: 0)
            return
        }
        
        // If there's an item queued in Next, crossfade to it if currently playing
        if playbackState == .playing {
            let fadeID = activeLoadID
            // Choose next according to shuffle/repeat rules
            guard let next = dequeueNextTrackRespectingModes() else {
                stop()
                updateRemoteCommandAvailability()
                return
            }
            
            if self.timersDisabled || self.isTesting {
                do {
                    guard let url = next.musicURL else { return }
                    let localURL: URL
                    if AudioEngine.shouldTreatAsRemote(url) {
                        localURL = try await self.audioCache.localURL(forRemote: url)
                    } else {
                        localURL = url
                    }
                    let nextFile = try AVAudioFile(forReading: localURL)
                    if let oldNFT = self.currentNFT { self.previousAudio.tracks.append(oldNFT) }
                    self.audioFile = nextFile
                    self.seekPosition = 0
                    self.pausedAt = 0
                    self.currentNFT = next
                    self.currentTrack = Track(title: next.name, artist: next.artistName, duration: self.duration, imageUrl: next.image?.secureUrl ?? next.image?.originalUrl)
                    self.commitPlaybackState(.playing, reason: "playNext() test path committed")
                    return
                } catch {
                    self.commitPlaybackState(.error, reason: "playNext() test path error")
                    self.lastError = .fileLoadFailed
                    return
                }
            }
            
            // Cancel existing ramp timers to avoid overlap
            await cancelAllRampTimers()
            
            // Immediate crossfade with pre-roll at mixer=0
            updateRemoteCommandAvailability()
            Task { @MainActor in
                do {
                    guard let url = next.musicURL else { return }
                    try self.ensureEngineReadyToPlay()
                    let localURL: URL
                    if AudioEngine.shouldTreatAsRemote(url) {
                        localURL = try await self.audioCache.localURL(forRemote: url)
                    } else {
                        localURL = url
                    }
                    
                    let nextFile: AVAudioFile
                    if let pre = self.preloadedNext, pre.nft.id == next.id, pre.url == localURL {
                        nextFile = pre.file
                    } else {
                        nextFile = try AVAudioFile(forReading: localURL)
                    }
                    
                    guard fadeID == self.activeLoadID else {
                        print("xfade_cancelled_stale {\(fadeID)}")
                        return
                    }
                    self.nextMixer.volume = 0.0
                    self.nextNode.stop()
                    self.nextNode.scheduleFile(nextFile, at: nil, completionHandler: nil)
                    self.nextNode.play()
                    self.suppressAutoAdvanceOnce = true // AE-004: prevent race with completion

                    // Auto-cap fade: min(configured, 30% of current track length)
                    let cappedFade = min(self.crossfadeDuration, 0.3 * self.duration)
                    let d = max(0.05, min(cappedFade, 10.0))
                    self.performCrossfade(duration: d, from: self.currentMixer, to: self.nextMixer)

                    // Removed trailing DispatchQueue.main.asyncAfter to flip roles
                    // The flip will be handled by scheduleCrossfadeIfPossible()
                } catch {
                    print("xfade_cancelled_stale {\(fadeID)}")
                }
            }
            return
        }
        // If not currently playing, load and start normally
        guard let next = dequeueNextTrackRespectingModes() else {
            stop()
            updateRemoteCommandAvailability()
            return
        }
        if let current = currentNFT { previousAudio.tracks.append(current) }
        updateRemoteCommandAvailability()
        await loadAndPlayWithRetry(nft: next)
    }

    @MainActor
    private func playNextSafely() async {
        if nextAudio.tracks.isEmpty || consecutiveFailureCount >= circuitBreakerThreshold {
            stop()
            return
        }
        if let next = dequeueNextTrackRespectingModes() {
            await loadAndPlayWithRetry(nft: next)
        } else {
            stop()
        }
    }

    @MainActor
    public func playPrevious() async {
        cancelNextPreload()
        
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
        updateRemoteCommandAvailability()

        await loadAndPlayWithRetry(nft: previous)
    }

    @MainActor
    private func playPreviousSafely() async {
        if previousAudio.tracks.isEmpty || consecutiveFailureCount >= circuitBreakerThreshold {
            stop()
            return
        }
        let previous = previousAudio.tracks.removeLast()
        await loadAndPlayWithRetry(nft: previous)
    }
    
    // Added beginNewLoad(nft:) overload for actual load and play
    @MainActor
    private func beginNewLoad(nft: NFT) async {
        // Cancel any existing load and establish new active ID
        let loadID = await beginNewLoad()

        guard let url = nft.musicURL else {
            commitPlaybackState(.error, reason: "beginNewLoad(nft:) missing url")
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
        self.commitPlaybackState(.loading, reason: "beginNewLoad(nft:) queued")

        // Detach heavy work off the main actor
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            // Prepare a local URL (download if remote)
            var managedURL: URL?
            do {
                let localURL: URL
                if AudioEngine.shouldTreatAsRemote(url) {
                    localURL = try await self.audioCache.localURL(forRemote: url)
                    managedURL = nil // cached persistently
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

                    // Start playback now that file is ready
                    do { try self.play() } catch {
                        self.commitPlaybackState(.error, reason: "beginNewLoad(nft:) play failed")
                        self.lastError = (error as? AudioEngineError) ?? .fileLoadFailed
                    }
                }
            } catch is CancellationError {
                // Cancelled: nothing to clean when using cache
            } catch {
                // Error: only report if still current
                await MainActor.run {
                    guard loadID == self.activeLoadID else { return }
                    self.commitPlaybackState(.error, reason: "beginNewLoad(nft:) failed")
                    self.lastError = (error as? AudioEngineError) ?? .fileLoadFailed
                }
            }
        }

        currentLoadTask = task
    }
    
    // Note: Replaced implementation with single-flight delegator and test override
    public func loadAndPlay(nft: NFT) async throws {
        cancelNextPreload()
        
        if isTesting {
            // Single-flight: cancel previous and establish new active ID
            let loadID = await beginNewLoad()
            guard let url = nft.musicURL else {
                self.commitPlaybackState(.error, reason: "loadAndPlay test path missing url")
                self.lastError = .fileLoadFailed
                throw AudioEngineError.fileLoadFailed
            }
            // Prepare local URL (download if remote)
            let localURL: URL
            if AudioEngine.shouldTreatAsRemote(url) {
                do {
                    localURL = try await self.audioCache.localURL(forRemote: url)
                } catch {
                    self.commitPlaybackState(.error, reason: "loadAndPlay test path download failure")
                    self.lastError = .downloadFailed
                    throw error
                }
            } else {
                localURL = url
            }
            // Open file
            do {
                let file = try AVAudioFile(forReading: localURL)
                // Apply on main if still current
                guard loadID == self.activeLoadID else { return }
                self.audioFile = file
                self.seekPosition = 0
                self.pausedAt = 0
                self.currentNFT = nft
                self.currentTrack = Track(title: nft.name, artist: nft.artistName, duration: self.duration, imageUrl: nft.image?.secureUrl ?? nft.image?.originalUrl)
                try self.play()
            } catch {
                self.commitPlaybackState(.error, reason: "loadAndPlay test path file open failure")
                self.lastError = .fileLoadFailed
                throw error
            }
            return
        }
        // Production path: retain detached single-flight loader
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
    
    // MARK: - Explicit Teardown
    public func shutdown() {
        print("[AE-013] Shutdown started")
        // Timers: progress + ramps/crossfade
        stopNowPlayingTimer()
        Task { @MainActor in await cancelAllRampTimers() }

        // Debounce task
        routeChangeDebounceTask?.cancel()
        routeChangeDebounceTask = nil

        // Loading/preload tasks and tokens
        currentLoadTask?.cancel(); currentLoadTask = nil
        cancelNextPreload()
        preloadedNext = nil
        activeLoadID = UUID() // invalidate any in-flight metadata/artwork updates
        artworkLoadID = UUID()

        // Observers
        NotificationCenter.default.removeObserver(self)
        if let obs = memoryWarningObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = thermalStateObserver { NotificationCenter.default.removeObserver(obs) }
        memoryWarningObserver = nil
        thermalStateObserver = nil
        cancelDeferredSessionDeactivation()

        // Remote commands: deregister and disable
        if remoteCommandsRegistered {
            remoteCommands.playCommand.removeTarget(nil)
            remoteCommands.pauseCommand.removeTarget(nil)
            remoteCommands.togglePlayPauseCommand.removeTarget(nil)
            remoteCommands.nextTrackCommand.removeTarget(nil)
            remoteCommands.previousTrackCommand.removeTarget(nil)
            remoteCommands.changePlaybackPositionCommand.removeTarget(nil)
            remoteCommands.skipForwardCommand.removeTarget(nil)
            remoteCommands.skipBackwardCommand.removeTarget(nil)
            // Disable commands to avoid stale controls
            remoteCommands.playCommand.isEnabled = false
            remoteCommands.pauseCommand.isEnabled = false
            remoteCommands.togglePlayPauseCommand.isEnabled = false
            remoteCommands.nextTrackCommand.isEnabled = false
            remoteCommands.previousTrackCommand.isEnabled = false
            remoteCommands.changePlaybackPositionCommand.isEnabled = false
            remoteCommands.skipForwardCommand.isEnabled = false
            remoteCommands.skipBackwardCommand.isEnabled = false
            remoteCommandsRegistered = false
        }

        // Stop nodes and engine
        playerNodeA.stop()
        playerNodeB.stop()
        mixerA.volume = 0.0
        mixerB.volume = 0.0
        audioEngine.pause()
        audioEngine.stop()
        audioEngine.reset()
        audioEngine.disconnectNodeOutput(playerNodeA)
        audioEngine.disconnectNodeOutput(playerNodeB)
        audioEngine.disconnectNodeOutput(mixerA)
        audioEngine.disconnectNodeOutput(mixerB)
        audioEngine.detach(playerNodeA)
        audioEngine.detach(playerNodeB)
        audioEngine.detach(mixerA)
        audioEngine.detach(mixerB)

        // Clear Now Playing and per-track state
        nowPlayingCenter.nowPlayingInfo = nil
        nowPlayingInfo = [:]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        audioFile = nil
        currentNFT = nil
        currentTrack = nil
        previousAudio.tracks.removeAll()
        nextAudio.tracks.removeAll()

        // Deactivate session; notify others
        do {
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            // Best-effort; ignore errors
        }

        needsEngineStart = true
        print("[AE-013] Shutdown completed")
    }

    // AE-003: Manual clear for QA/debug
    public func clearCachesAndRelease() {
        cancelNextPreload()
        preloadedNext = nil
        audioFile = nil
        audioCache.clearAll()
    }

    // MARK: - Resource Cleanup
    @MainActor deinit {
        shutdown()
    }

    
    // MARK: - Crossfade Helpers
    
    private func computeCrossfadeTuning() -> (safetyPad: TimeInterval, capFraction: Double) {
        #if os(iOS)
        let thermal = ProcessInfo.processInfo.thermalState
        switch thermal {
        case .nominal:
            return (0.05, 0.30) // 50 ms safety, 30% cap
        case .fair:
            return (0.08, 0.32)
        case .serious:
            return (0.12, 0.35)
        case .critical:
            return (0.15, 0.40) // 150 ms safety, 40% cap
        @unknown default:
            return (0.08, 0.32)
        }
        #else
        // On non-iOS platforms, use conservative defaults
        return (0.08, 0.32)
        #endif
    }
    
    private func scheduleCrossfadeIfPossible() {
        // If there's no upcoming track or no current file, do nothing
        guard let next = self.peekNextTrackRespectingModes() else { return }
        if repeatMode == .track, let current = currentNFT, current.id == next.id { return }
        guard let audioFile = audioFile else { return }
        guard playbackState == .playing else { return }

        // Compute remaining time on the current file from the current seek position
        let sampleRate = audioFile.processingFormat.sampleRate
        let startFrame = AVAudioFramePosition(seekPosition * sampleRate)
        let remainingFrames = max(0, audioFile.length - startFrame)
        let remainingTime = Double(remainingFrames) / sampleRate

        // Account for hardware presentation latency
        let latency = audioEngine.outputNode.presentationLatency

        // Special-case short tracks (<7s): avoid long fades that risk silence
        if self.duration < 7.0 {
            return // play to end without crossfade
        }

        // Auto-cap fade: min(configured, 30% of track length)
        let (_, capFraction) = computeCrossfadeTuning()
        let cappedFade = min(crossfadeDuration, max(0.0, capFraction * (Double(audioFile.length) / sampleRate)))
        let overlap = min(cappedFade, max(0.0, remainingTime))
        guard overlap > 0 else { return }

        let (safety, _) = computeCrossfadeTuning()
        let secondsUntilStart = max(0.0, remainingTime - overlap - safety - latency)

        // Establish a precise hostTime for the next track start and fade start
        let startHostDelta = AVAudioTime.hostTime(forSeconds: secondsUntilStart)
        let fadeStartHostTime = mach_absolute_time() &+ startHostDelta
        let flipHostDelta = AVAudioTime.hostTime(forSeconds: overlap)
        let flipHostTime = fadeStartHostTime &+ flipHostDelta

        let fadeID = activeLoadID

        Task { @MainActor in
            do {
                guard fadeID == self.activeLoadID else { return }
                guard let url = next.musicURL else { return }
                try self.ensureEngineReadyToPlay()

                // Prepare local URL (download if remote) for pre-roll
                let localURL: URL
                if AudioEngine.shouldTreatAsRemote(url) {
                    localURL = try await self.audioCache.localURL(forRemote: url)
                } else {
                    localURL = url
                }

                let nextFile: AVAudioFile
                if let pre = self.preloadedNext, pre.nft.id == next.id, pre.url == localURL {
                    nextFile = pre.file
                } else {
                    nextFile = try AVAudioFile(forReading: localURL)
                }

                // Pre-roll next track on its player; keep its mixer silent
                self.nextMixer.volume = 0.0
                self.nextNode.stop()
                let startTime = AVAudioTime(hostTime: fadeStartHostTime)
                await self.nextNode.scheduleFile(nextFile, at: startTime)
                self.nextNode.play()

                // Cancel any prior timers and schedule the fade start and flip using hostTime
                await self.cancelAllRampTimers()

                // Start crossfade exactly at fadeStartHostTime
                self.scheduleOneShot(atHostTime: fadeStartHostTime, storeIn: &self.crossfadeStartTimer) { [weak self] in
                    guard let self else { return }
                    DispatchQueue.main.async {
                        guard fadeID == self.activeLoadID else { return }
                        self.suppressAutoAdvanceOnce = true
                        self.performCrossfade(duration: overlap, from: self.currentMixer, to: self.nextMixer)
                    }
                }

                // Flip roles exactly at flipHostTime
                self.scheduleOneShot(atHostTime: flipHostTime, storeIn: &self.crossfadeFlipTimer) { [weak self] in
                    guard let self else { return }
                    DispatchQueue.main.async {
                        guard fadeID == self.activeLoadID else { return }
                        // Stop old node and mute its path
                        self.currentNode.stop()
                        self.currentMixer.volume = 0.0

                        // Commit new state
                        if let oldNFT = self.currentNFT { self.previousAudio.tracks.append(oldNFT) }
                        if let idx = self.nextAudio.tracks.firstIndex(where: { $0.id == next.id }) {
                            self.nextAudio.tracks.remove(at: idx)
                        }
                        self.currentNodeIsA.toggle()
                        self.currentMixer.volume = 1.0
                        self.nextMixer.volume = 0.0
                        self.audioFile = nextFile
                        self.seekPosition = 0
                        self.pausedAt = 0
                        self.currentNFT = next
                        self.currentTrack = Track(title: next.name, artist: next.artistName, duration: self.duration, imageUrl: next.image?.secureUrl ?? next.image?.originalUrl)
                        self.commitPlaybackState(.playing, reason: "crossfade flip committed")
                        self.suppressAutoAdvanceOnce = false
                        self.preloadedNext = nil
                    }
                }
            } catch is CancellationError {
                // Stale
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

    // MARK: - Testing helpers (no side effects)
    internal func injectAudioFileForTesting(_ file: AVAudioFile, nft: NFT? = nil) {
        self.audioFile = file
        self.seekPosition = 0
        self.pausedAt = 0
        if let nft {
            self.currentNFT = nft
            self.currentTrack = Track(title: nft.name, artist: nft.artistName, duration: self.duration, imageUrl: nft.image?.secureUrl ?? nft.image?.originalUrl)
        } else {
            self.currentTrack = Track(title: "Test Track", artist: "Test Artist", duration: self.duration, imageUrl: nil)
        }
        self.commitPlaybackState(.stopped, reason: "injectAudioFileForTesting")
        updateRemoteCommandAvailability()
        updateNowPlayingMetadata()
    }
}


extension AudioEngine.Track: Equatable {
    static func == (lhs: AudioEngine.Track, rhs: AudioEngine.Track) -> Bool {
        return lhs.title == rhs.title && lhs.artist == rhs.artist && lhs.duration == rhs.duration && lhs.imageUrl == rhs.imageUrl
    }
}

extension AudioEngine.Track: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(title)
        hasher.combine(artist)
        hasher.combine(duration)
        hasher.combine(imageUrl)
    }
}

