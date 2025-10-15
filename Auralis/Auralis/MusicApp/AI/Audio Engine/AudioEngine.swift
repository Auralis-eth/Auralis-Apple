//
//  AudioEngine.swift
//  Auralis
//
//  Refactored: Thin façade over modular playback stack.
//

import Foundation
import AVFoundation
import AVFAudio
import MediaPlayer
import Combine

@MainActor
final class AudioEngine: ObservableObject {
    // Published state exposed to UI
    @Published var currentTrack: Track? = nil
    @Published var playbackState: PlaybackState = .stopped
    @Published var progress: TimeInterval = 0

    // Error surfacing to UI
    enum PlaybackErrorCategory: Equatable {
        case permission
        case network
        case offline
        case decoding
        case queue
        case unsupported
        case unknown
    }
    struct PlaybackErrorState: Equatable {
        let category: PlaybackErrorCategory
        let message: String
        let context: String
    }
    @Published var errorState: PlaybackErrorState? = nil

    // User prefs
    @Published var isShuffleEnabled: Bool = false { didSet { queue.isShuffleEnabled = isShuffleEnabled } }
    @Published var repeatMode: QueueManager.RepeatMode = .none { didSet { queue.repeatMode = repeatMode } }
    @Published var coarseSkipSeconds: TimeInterval = 10 { didSet { reconfigureRCC() } }

    // Combine subscriptions
    private var cancellables = Set<AnyCancellable>()

    private var currentDuration: TimeInterval = 0

    // Background-safe progress ticker
    private var progressTimer: DispatchSourceTimer? = nil

    // Configurable progress cadence (runtime adjustable)
    @Published var progressUpdateInterval: TimeInterval = 0.25 { didSet { rearmProgressTimer() } }
    // If nil, a sensible default leeway is derived from interval (50–100ms window)
    @Published var progressUpdateLeeway: TimeInterval? = nil { didSet { rearmProgressTimer() } }

    private func computedLeeway() -> DispatchTimeInterval {
        // Default: 40% of interval, clamped to [50ms, 100ms]
        let base = max(0.0, progressUpdateInterval) * 0.4
        let clamped = min(0.100, max(0.050, base))
        let leewaySeconds = progressUpdateLeeway ?? clamped
        let ms = Int((leewaySeconds * 1000.0).rounded())
        return .milliseconds(ms)
    }

    // Audio session observers
    private var audioSessionObservers: [NSObjectProtocol] = []
    private var wasPlayingBeforeInterruption: Bool = false
    private var pausedDueToRouteChange: Bool = false

    // Centralized audio session state
    private var isSessionConfigured: Bool = false
    private var isSessionActive: Bool = false
    private var didSessionInitFail: Bool = false

    // Services
    private let graph = AudioGraph()
    private let session = AudioSessionManager()
    private lazy var preloader = Preloader()
    private var queue = QueueManager()
    private lazy var crossfade = CrossfadeCoordinator(graph: graph)
    private let nowPlaying = NowPlayingService()
    private lazy var controller = PlaybackController(graph: graph,
                                                     session: session,
                                                     preloader: preloader,
                                                     queue: queue,
                                                     crossfade: crossfade,
                                                     nowPlaying: nowPlaying,
                                                     crossfadeSeconds: 2.0,
                                                     skipInterval: coarseSkipSeconds)

    // RCC
    private let rcc = RemoteCommandService()
    
    // Cache last-known availability to avoid gaps during RCC reconfig
    private var lastCanNext: Bool = false
    private var lastCanPrevious: Bool = false
    private var lastRCCSkipInterval: TimeInterval? = nil

    // MARK: - Centralized Audio Session Ownership
    private func configureAndActivateSessionWithRetry(maxAttempts: Int = 3) {
        guard !didSessionInitFail else { return }
        let av = AVAudioSession.sharedInstance()
        var lastError: Error?
        for attempt in 1...maxAttempts {
            do {
                if !isSessionConfigured {
                    try av.setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetooth])
                    isSessionConfigured = true
                }
                if !isSessionActive {
                    try av.setActive(true, options: [])
                    isSessionActive = true
                }
                // Success
                return
            } catch {
                lastError = error
                // Exponential backoff: 0.2s, 0.4s, 0.8s
                let delay = pow(2.0, Double(attempt - 1)) * 0.2
                Thread.sleep(forTimeInterval: delay)
            }
        }
        didSessionInitFail = true
        if let err = lastError {
            self.mapAndPublishError(err, context: "audioSession configureAndActivate")
        } else {
            self.publishError(.permission, message: "Unable to activate audio session. Check audio permissions and output.", context: "audioSession configureAndActivate")
        }
    }

    private func activateSessionIfNeeded(context: String) {
        guard !didSessionInitFail else { return }
        if isSessionActive { return }
        let av = AVAudioSession.sharedInstance()
        do {
            try av.setActive(true, options: [])
            isSessionActive = true
        } catch {
            self.mapAndPublishError(error, context: context)
        }
    }

    private func attemptResumeWithVerification(context: String, delay: TimeInterval = 0.4) {
        // Ensure we have something to resume
        guard currentTrack != nil else { return }
        // Reactivate session if needed
        activateSessionIfNeeded(context: context)
        // First attempt: resume
        controller.resume()
        // Verify after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            if self.playbackState != .playing {
                // Fallback attempt: explicit play
                self.controller.play()
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self = self else { return }
                    if self.playbackState != .playing {
                        // Surface a non-fatal error; state is preserved and user can retry
                        self.publishError(.queue, message: "Failed to resume playback after interruption/route change.", context: context)
                    }
                }
            }
        }
    }

    private func deactivateSessionIfActive() {
        guard isSessionActive else { return }
        let av = AVAudioSession.sharedInstance()
        do {
            try av.setActive(false, options: [.notifyOthersOnDeactivation])
            isSessionActive = false
        } catch {
            self.mapAndPublishError(error, context: "audioSession setActive false")
        }
    }
    
    private func deactivateSessionIfActiveWithRetry(maxAttempts: Int = 3) {
        guard isSessionActive else { return }
        let av = AVAudioSession.sharedInstance()
        var lastError: Error?
        for attempt in 1...maxAttempts {
            do {
                try av.setActive(false, options: [.notifyOthersOnDeactivation])
                isSessionActive = false
                return
            } catch {
                lastError = error
                // Exponential backoff: 0.1s, 0.2s, 0.4s
                let delay = pow(2.0, Double(attempt - 1)) * 0.1
                Thread.sleep(forTimeInterval: delay)
            }
        }
        if let err = lastError {
            // Surface deactivation error rather than failing silently
            self.mapAndPublishError(err, context: "audioSession setActive false (retry)")
        }
    }

    private func ensureOperational(_ context: String) -> Bool {
        if didSessionInitFail {
            publishError(.permission, message: "Audio session unavailable. Check device audio settings and permissions.", context: context)
            return false
        }
        return true
    }

    private func publishError(_ category: PlaybackErrorCategory, message: String, context: String) {
        errorState = PlaybackErrorState(category: category, message: message, context: context)
    }

    private func mapAndPublishError(_ error: Error, context: String) {
        // Comprehensive mapping across AVError, AVAudioSession, URLError, Cocoa file/decoding, and app-internal fallbacks.
        var category: PlaybackErrorCategory = .unknown
        let nsError = error as NSError

        // Fast-path: Network-related errors
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .timedOut:
                category = .offline
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .networkConnectionLost, .secureConnectionFailed, .badServerResponse, .dataNotAllowed:
                category = .network
            default:
                category = .network
            }
            publishError(category, message: error.localizedDescription, context: context)
            return
        }

        // Attempt to interpret as a typed AVAudioSession error first (rare but future-proof if thrown as such).
        if let avError = error as? AVError {
            switch avError.code {
            case .deviceNotConnected:
                category = .unknown // or create .audioSession if needed
            case .fileFormatNotRecognized, .fileFailedToParse:
                category = .decoding
            case .contentIsNotAuthorized, .contentIsProtected:
                category = .permission
            case .noDataCaptured, .diskFull:
                category = .unknown
            case .invalidSourceMedia, .decoderNotFound:
                category = .decoding
            case .unsupportedOutputSettings, .encoderNotFound:
                category = .unsupported
            case .deviceIsNotAvailableInBackground:
                category = .unknown
            default:
                category = .unknown
            }
        } else if nsError.domain == NSOSStatusErrorDomain {
            if let avErrorCode = AVAudioSession.ErrorCode(rawValue: nsError.code) {
                switch avErrorCode {
                case .cannotStartRecording:
                    category = .permission  // Often related to permission or configuration issues preventing recording
                case .isBusy, .cannotInterruptOthers, .siriIsRecording:
                    category = .queue  // Device or session is busy or in use
                case .incompatibleCategory, .cannotStartPlaying:
                    category = .unsupported
                case .mediaServicesFailed, .missingEntitlement:
                    category = .unknown
                // Add other specific AVAudioSession.ErrorCode cases as needed
                default:
                    category = .unknown
                }
            } else {
                category = .unknown
            }
        } else if nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case NSFileReadNoSuchFileError, NSFileNoSuchFileError, NSFileReadUnknownError:
                category = .network // or decoding depending on source; treat as network/missing asset when remote-backed
            case NSFileReadInapplicableStringEncodingError, NSFileReadCorruptFileError:
                category = .decoding
            case NSFileReadNoPermissionError, NSFileWriteNoPermissionError:
                category = .permission
            case NSFileWriteOutOfSpaceError:
                category = .unknown
            default:
                category = .unsupported
            }
        } else if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet, NSURLErrorTimedOut:
                category = .offline
            case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed, NSURLErrorNetworkConnectionLost, NSURLErrorSecureConnectionFailed, NSURLErrorBadServerResponse, NSURLErrorDataNotAllowed:
                category = .network
            default:
                category = .network
            }
        } else if nsError.domain == AVFoundationErrorDomain {
            // Treat remaining AVFoundation errors as decoding/unsupported based on code ranges
            if let avError = error as? AVError {
                switch avError.code {
                case .fileFormatNotRecognized, .fileFailedToParse, .invalidSourceMedia, .decoderNotFound:
                    category = .decoding
                case .unsupportedOutputSettings, .encoderNotFound:
                    category = .unsupported
                default:
                    category = .queue
                }
            } else {
                category = .queue
            }
        } else {
            // Heuristic: Prefer queue-related category for app-internal failures
            category = .queue
        }

        // Use the original error's localized description for messaging.
        publishError(category, message: error.localizedDescription, context: context)
    }

    func clearError() { errorState = nil }

    private func refreshRCCAvailability(canNext: Bool? = nil, canPrevious: Bool? = nil, duration: TimeInterval? = nil) {
        let hasTrack = (currentTrack != nil) && (playbackState != .stopped)
        let dur = duration ?? currentDuration
        let canScrub = hasTrack && dur > 0
        let canSkip = canScrub // coarse skip only valid for finite-duration tracks
        // If explicit next/prev were provided (e.g., from a fresh snapshot), use them; otherwise be conservative.
        let next = canNext ?? false
        let prev = canPrevious ?? false
        rcc.setAvailability(canNext: next, canPrevious: prev, canSkip: canSkip, canScrub: canScrub)
    }

    private func reconfigureRCC() {
        // If the interval hasn't changed, avoid unregister/register churn
        if let last = lastRCCSkipInterval, last == coarseSkipSeconds {
            // Just ensure closures are wired and availability is refreshed with last-known state
            rcc.onPlay = { [weak self] in self?.play() }
            rcc.onPause = { [weak self] in self?.pause() }
            rcc.onToggle = { [weak self] in
                guard let self else { return }
                if self.playbackState == .playing { self.pause() } else { self.play() }
            }
            rcc.onNext = { [weak self] in Task { await self?.playNext() } }
            rcc.onPrevious = { [weak self] in Task { await self?.playPrevious() } }
            rcc.onSeek = { [weak self] t in self?.seek(to: t) }
            rcc.onSkipForward = { [weak self] d in self?.skipForward(seconds: d) }
            rcc.onSkipBackward = { [weak self] d in self?.skipBackward(seconds: d) }
            // Restore availability immediately using last-known state
            refreshRCCAvailability(canNext: lastCanNext, canPrevious: lastCanPrevious, duration: currentDuration)
            return
        }

        // Otherwise, perform a controlled re-registration with minimal gap
        rcc.unregister()
        rcc.register(skipInterval: coarseSkipSeconds)
        lastRCCSkipInterval = coarseSkipSeconds
        
        // Re-wire closures
        rcc.onPlay = { [weak self] in self?.play() }
        rcc.onPause = { [weak self] in self?.pause() }
        rcc.onToggle = { [weak self] in
            guard let self else { return }
            if self.playbackState == .playing { self.pause() } else { self.play() }
        }
        rcc.onNext = { [weak self] in Task { await self?.playNext() } }
        rcc.onPrevious = { [weak self] in Task { await self?.playPrevious() } }
        rcc.onSeek = { [weak self] t in self?.seek(to: t) }
        rcc.onSkipForward = { [weak self] d in self?.skipForward(seconds: d) }
        rcc.onSkipBackward = { [weak self] d in self?.skipBackward(seconds: d) }

        // Immediately reflect current availability using last-known queue state and duration
        refreshRCCAvailability(canNext: lastCanNext, canPrevious: lastCanPrevious, duration: currentDuration)
    }

    private func startProgressTimer() {
        // Avoid duplicate timers
        guard progressTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        let intervalNs = UInt64(progressUpdateInterval * 1_000_000_000)
        timer.schedule(deadline: .now() + progressUpdateInterval,
                       repeating: .nanoseconds(Int(intervalNs)),
                       leeway: computedLeeway())
        timer.setEventHandler { [weak self] in
            guard let _ = self else { return }
            // Cadence timer intentionally does not mutate progress. Authoritative updates come from controller snapshots.
        }
        progressTimer = timer
        timer.resume()
    }

    private func stopProgressTimer() {
        progressTimer?.setEventHandler {}
        progressTimer?.cancel()
        progressTimer = nil
    }

    private func rearmProgressTimer() {
        // Only rearm if a timer is currently active (to avoid starting it in stopped state)
        let wasRunning = (progressTimer != nil)
        if wasRunning { stopProgressTimer() }
        if wasRunning { startProgressTimer() }
    }

    init() {
        // Wire RCC
        reconfigureRCC()

        // Configure audio session for background playback with retry
        configureAndActivateSessionWithRetry(maxAttempts: 3)

        // Observe interruptions to survive calls/alarms
        let intObs = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let self = self else { return }
            guard let info = note.userInfo,
                  let typeRaw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }
            switch type {
            case .began:
                // Record if we were playing and pause gracefully
                self.wasPlayingBeforeInterruption = (self.playbackState == .playing)
                if self.wasPlayingBeforeInterruption {
                    self.controller.pause()
                }
            case .ended:
                let shouldResume = (info[AVAudioSessionInterruptionOptionKey] as? UInt).map { AVAudioSession.InterruptionOptions(rawValue: $0).contains(.shouldResume) } ?? false
                if self.wasPlayingBeforeInterruption && shouldResume {
                    self.attemptResumeWithVerification(context: "audioSession reactivationAfterInterruption")
                }
                self.wasPlayingBeforeInterruption = false
            @unknown default:
                break
            }
        }
        audioSessionObservers.append(intObs)

        // Observe route changes (e.g., headphones unplugged)
        let routeObs = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            guard let self = self else { return }
            guard let reasonRaw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw) else { return }
            switch reason {
            case .oldDeviceUnavailable:
                // Pause when output disappears (e.g., headphone unplug)
                self.controller.pause()
                self.pausedDueToRouteChange = true
            case .newDeviceAvailable, .routeConfigurationChange, .categoryChange, .override:
                // Attempt to resume if we paused due to a prior route change
                if self.pausedDueToRouteChange {
                    self.attemptResumeWithVerification(context: "audioSession resumeAfterRouteChange")
                    self.pausedDueToRouteChange = false
                }
            default:
                break
            }
        }
        audioSessionObservers.append(routeObs)

        // Bridge controller snapshot -> façade published vars
        controller.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snap in
                guard let self = self else { return }
                self.playbackState = snap.state
                self.currentTrack = snap.track

                // Keep a copy of duration for clamping
                self.currentDuration = snap.duration

                // Reset progress and availability when no track or stopped
                if snap.track == nil || snap.state == .stopped {
                    self.progress = 0
                    self.stopProgressTimer()
                    self.refreshRCCAvailability(canNext: false, canPrevious: false, duration: 0)
                } else {
                    // Drive progress from authoritative playback time (elapsed)
                    let elapsed = snap.elapsed
                    if self.currentDuration > 0 {
                        self.progress = min(max(0, elapsed), self.currentDuration)
                    } else {
                        self.progress = max(0, elapsed)
                    }
                    
                    // Ensure cadence timer is running while we have an active track
                    self.startProgressTimer()

                    // Derive RCC availability: next/prev from queue navigability, scrub/skip from finite duration
                    let canNext = snap.canSkipNext
                    let canPrev = snap.canSkipPrevious
                    // Update last-known RCC state to avoid gaps during reconfiguration
                    self.lastCanNext = canNext
                    self.lastCanPrevious = canPrev
                    self.refreshRCCAvailability(canNext: canNext, canPrevious: canPrev, duration: snap.duration)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Public API (compat)
    func loadAndPlay(nft: NFT) async {
        guard ensureOperational("loadAndPlay") else { return }
        do {
            try await controller.loadAndPlay(nft: nft)
        } catch {
            let details = String(describing: nft)
            self.mapAndPublishError(error, context: "loadAndPlay nft=\(details)")
        }
    }
    
    func play() {
        guard ensureOperational("play") else { return }
        if currentTrack == nil {
            publishError(.queue, message: "Nothing to play. The queue is empty.", context: "play")
            return
        }
        activateSessionIfNeeded(context: "audioSession activate for play")
        controller.play()
    }
    
    func pause() { controller.pause() }
    
    func resume() {
        guard ensureOperational("resume") else { return }
        if currentTrack == nil {
            publishError(.queue, message: "Cannot resume: no current track.", context: "resume")
            return
        }
        activateSessionIfNeeded(context: "audioSession activate for resume")
        controller.resume()
    }
    
    func seek(to time: TimeInterval) {
        // Validate seekability
        guard currentTrack != nil else {
            publishError(.queue, message: "Cannot seek: no current track.", context: "seek")
            return
        }
        // Always allow seeking to zero (and clamp negatives to zero) even for unknown durations
        if time <= 0 {
            controller.seek(to: 0)
            return
        }
        // For positive seeks, require a known finite duration
        if currentDuration <= 0 {
            publishError(.unsupported, message: "Seeking is unavailable for this track.", context: "seek")
            return
        }
        controller.seek(to: time)
    }
    
    func skipForward(seconds: TimeInterval? = nil) { 
        let delta = seconds ?? coarseSkipSeconds
        controller.skipForward(seconds: delta)
    }
    
    func skipBackward(seconds: TimeInterval? = nil) { 
        let delta = seconds ?? coarseSkipSeconds
        controller.skipBackward(seconds: delta)
    }
    
    func playNext() async {
        guard ensureOperational("playNext") else { return }
        if currentTrack == nil {
            publishError(.queue, message: "No next track: the queue is empty.", context: "playNext")
            return
        }
        do {
            try await controller.playNext()
        } catch {
            self.mapAndPublishError(error, context: "playNext")
        }
    }
    
    func playPrevious() async {
        guard ensureOperational("playPrevious") else { return }
        if currentTrack == nil {
            publishError(.queue, message: "No previous track: the queue is empty.", context: "playPrevious")
            return
        }
        do {
            try await controller.playPrevious()
        } catch {
            self.mapAndPublishError(error, context: "playPrevious")
        }
    }

    func shutdown() {
        // Stop playback pipeline first to halt in-flight operations
        controller.stop()
        
        // Cancel Combine subscriptions
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
        // Stop background progress timer
        stopProgressTimer()
        rcc.unregister()
        
        // Cancel crossfade timers to prevent lingering callbacks
        crossfade.cancel()
        
        // Clear RCC closures to break retain cycles
        rcc.onPlay = nil
        rcc.onPause = nil
        rcc.onToggle = nil
        rcc.onNext = nil
        rcc.onPrevious = nil
        rcc.onSeek = nil
        rcc.onSkipForward = nil
        rcc.onSkipBackward = nil
        
        // Reset published and internal state to pristine stopped condition
        playbackState = .stopped
        currentTrack = nil
        progress = 0
        currentDuration = 0
        rcc.setAvailability(canNext: false, canPrevious: false, canSkip: false, canScrub: false)

        // Remove audio session observers and deactivate session with retry
        audioSessionObservers.forEach { NotificationCenter.default.removeObserver($0) }
        audioSessionObservers.removeAll()
        deactivateSessionIfActiveWithRetry(maxAttempts: 3)
    }

    func clearCachesAndRelease() {
        Task { await AudioFileCache.shared.clearAll() }
    }
    
    @MainActor
    deinit {
        // Guarantee robust cleanup on deallocation (idempotent)
        shutdown()
    }
}

