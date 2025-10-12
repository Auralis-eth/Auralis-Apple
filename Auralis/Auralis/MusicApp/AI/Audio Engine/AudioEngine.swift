//
//  AudioEngine.swift
//  Auralis
//
//  Refactored: Thin façade over modular playback stack.
//

import Foundation
import AVFoundation
import MediaPlayer

@MainActor
final class AudioEngine: ObservableObject {
    // Published state exposed to UI
    @Published var currentTrack: Track? = nil
    @Published var playbackState: PlaybackState = .stopped
    @Published var progress: TimeInterval = 0

    // User prefs
    @Published var isShuffleEnabled: Bool = false { didSet { queue.isShuffleEnabled = isShuffleEnabled } }
    @Published var repeatMode: QueueManager.RepeatMode = .none { didSet { queue.repeatMode = repeatMode } }
    @Published var coarseSkipSeconds: TimeInterval = 10

    // Progress tracking
    private var progressTimer: Timer? = nil
    private var currentDuration: TimeInterval = 0

    private func startProgressTimer() {
        stopProgressTimer()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard self.playbackState == .playing else { return }
            // Increment progress while playing; clamp to duration if finite (>0)
            let next = self.progress + 0.2
            if self.currentDuration > 0 {
                self.progress = min(next, self.currentDuration)
            } else {
                self.progress = max(0, next)
            }
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

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

    init() {
        // Wire RCC
        rcc.register(skipInterval: coarseSkipSeconds)
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

        // Bridge controller snapshot -> façade published vars
        controller.$snapshot.sink { [weak self] snap in
            guard let self else { return }
            self.playbackState = snap.state
            self.currentTrack = snap.track

            // Keep a copy of duration for clamping
            self.currentDuration = snap.duration

            // Reset progress when track changes or when stopped
            if snap.track == nil || snap.state == .stopped {
                self.progress = 0
            }

            // Manage timer based on playback state
            if snap.state == .playing {
                self.startProgressTimer()
            } else {
                self.stopProgressTimer()
            }

            let canNext = snap.canSkipNext
            let canPrev = snap.canSkipPrevious
            self.rcc.setAvailability(canNext: canNext, canPrevious: canPrev, canSkip: (snap.duration > 0), canScrub: (snap.duration > 0))
        }
    }

    // MARK: - Public API (compat)
    func loadAndPlay(nft: NFT) async { await controller.loadAndPlay(nft: nft) }
    func play() { controller.play() }
    func pause() { controller.pause() }
    func resume() { controller.resume() }
    func seek(to time: TimeInterval) { 
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
        await controller.playNext()
        progress = 0
    }
    func playPrevious() async { 
        await controller.playPrevious()
        progress = 0
    }

    func shutdown() {
        rcc.unregister()
        try? session.deactivate()
        controller.stop()
        stopProgressTimer()
    }

    func clearCachesAndRelease() {
        Task { await AudioFileCache.shared.clearAll() }
    }
}

