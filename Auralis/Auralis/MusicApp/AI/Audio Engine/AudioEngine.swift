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
    private let progressInterval: TimeInterval = 0.25

    // Audio session observers
    private var audioSessionObservers: [NSObjectProtocol] = []
    private var wasPlayingBeforeInterruption: Bool = false

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
    
    private func publishError(_ category: PlaybackErrorCategory, message: String, context: String) {
        errorState = PlaybackErrorState(category: category, message: message, context: context)
    }

    private func mapAndPublishError(_ error: Error, context: String) {
        // Type-safe handling of AVAudioSession errors first; then fall back to domain/code checks for networking and unknowns.
        var category: PlaybackErrorCategory = .unknown
        let nsError = error as NSError

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
        } else {
            // Fallback to checking the NSError domain
            let nsError = error as NSError
            switch (nsError.domain, nsError.code) {
            case (NSURLErrorDomain, NSURLErrorNotConnectedToInternet),
                 (NSURLErrorDomain, NSURLErrorTimedOut):
                category = .offline
            case (NSURLErrorDomain, _):
                category = .network
            default:
                category = .unknown
            }
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
        // Ensure RCC reflects the latest skip interval
        rcc.unregister()
        rcc.register(skipInterval: coarseSkipSeconds)
        
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
        
        // Ensure availability matches current state after re-registration
        refreshRCCAvailability()
    }

    private func startProgressTimer() {
        // Avoid duplicate timers
        guard progressTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInteractive))
        let intervalNs = UInt64(progressInterval * 1_000_000_000)
        timer.schedule(deadline: .now() + progressInterval, repeating: .nanoseconds(Int(intervalNs)), leeway: .milliseconds(20))
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            // Only advance while actively playing
            if self.playbackState == .playing {
                let delta = self.progressInterval
                let newValue: TimeInterval
                if self.currentDuration > 0 {
                    newValue = min(self.progress + delta, self.currentDuration)
                } else {
                    newValue = max(0, self.progress + delta)
                }
                Task { @MainActor in
                    // Double-check state on main actor before committing
                    if self.playbackState == .playing {
                        self.progress = newValue
                    }
                }
            }
        }
        progressTimer = timer
        timer.resume()
    }

    private func stopProgressTimer() {
        progressTimer?.setEventHandler {}
        progressTimer?.cancel()
        progressTimer = nil
    }

    init() {
        // Wire RCC
        reconfigureRCC()

        // Configure audio session for background playback
        do {
            let av = AVAudioSession.sharedInstance()
            try av.setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetooth])
            try av.setActive(true, options: [])
        } catch {
            // Intentionally avoid crashing; session manager may retry
            self.publishError(.permission, message: "Unable to activate audio session. Check audio permissions and output.", context: "AVAudioSession setActive(true)")
        }

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
                    // Reactivate session and resume where we left off
                    do { try AVAudioSession.sharedInstance().setActive(true, options: []) } catch {
                        self.mapAndPublishError(error, context: "Interruption ended reactivation")
                    }
                    self.controller.resume()
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
            if reason == .oldDeviceUnavailable {
                // Pause when output disappears (e.g., headphone unplug)
                self.controller.pause()
            }
        }
        audioSessionObservers.append(routeObs)

        // Bridge controller snapshot -> façade published vars
        controller.$snapshot.sink { [weak self] snap in
            guard let self else { return }
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

                // Maintain a background-safe progress cadence
                if snap.state == .playing {
                    self.startProgressTimer()
                } else {
                    self.stopProgressTimer()
                }

                // Derive RCC availability: next/prev from queue navigability, scrub/skip from finite duration
                let canNext = snap.canSkipNext
                let canPrev = snap.canSkipPrevious
                self.refreshRCCAvailability(canNext: canNext, canPrevious: canPrev, duration: snap.duration)
            }
        }.store(in: &cancellables)
    }

    // MARK: - Public API (compat)
    func loadAndPlay(nft: NFT) async { await controller.loadAndPlay(nft: nft) }
    
    func play() {
        if currentTrack == nil {
            publishError(.queue, message: "Nothing to play. The queue is empty.", context: "play()")
            return
        }
        controller.play()
    }
    
    func pause() { controller.pause() }
    
    func resume() {
        if currentTrack == nil {
            publishError(.queue, message: "Cannot resume: no current track.", context: "resume()")
            return
        }
        controller.resume()
    }
    
    func seek(to time: TimeInterval) {
        // Validate seekability
        guard currentTrack != nil else {
            publishError(.queue, message: "Cannot seek: no current track.", context: "seek(")
            return
        }
        if currentDuration <= 0 && time > 0 {
            publishError(.unsupported, message: "Seeking is unavailable for this track.", context: "seek(")
            return
        }
        controller.seek(to: time)
        // Clamp to known duration if finite
        if currentDuration > 0 {
            progress = min(max(0, time), currentDuration)
        } else {
            progress = max(0, time)
        }
    }
    
    func skipForward(seconds: TimeInterval? = nil) { 
        controller.skipForward(seconds: seconds)
        let delta = seconds ?? coarseSkipSeconds
        seek(to: progress + delta)
    }
    
    func skipBackward(seconds: TimeInterval? = nil) { 
        controller.skipBackward(seconds: seconds)
        let delta = seconds ?? coarseSkipSeconds
        seek(to: progress - delta)
    }
    
    func playNext() async {
        if currentTrack == nil {
            publishError(.queue, message: "No next track: the queue is empty.", context: "playNext()")
            return
        }
        await controller.playNext()
        progress = 0
    }
    
    func playPrevious() async {
        if currentTrack == nil {
            publishError(.queue, message: "No previous track: the queue is empty.", context: "playPrevious()")
            return
        }
        await controller.playPrevious()
        progress = 0
    }

    func shutdown() {
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

        // Remove audio session observers and deactivate session
        audioSessionObservers.forEach { NotificationCenter.default.removeObserver($0) }
        audioSessionObservers.removeAll()
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            self.mapAndPublishError(error, context: "AVAudioSession setActive(false)")
        }
        
        controller.stop()
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

