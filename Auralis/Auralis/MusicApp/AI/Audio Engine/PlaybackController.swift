import Foundation
import AVFoundation
import Combine
import MediaPlayer

public enum PlaybackError: Equatable {
    case activationFailed
    case fileUnreadable
    case networkUnavailable
    case unknown
}

@MainActor
public final class PlaybackController: ObservableObject {
    // Dependencies
    private let graph: AudioGraph
    private let session: AudioSessionManager
    private let preloader: Preloader
    private var queue: QueueManager
    private let crossfade: CrossfadeCoordinator
    private let nowPlaying: NowPlayingService

    // Config
    private let crossfadeSeconds: TimeInterval
    private let skipInterval: TimeInterval

    // State
    @Published public private(set) var snapshot: PlaybackSnapshot
    @Published public private(set) var lastError: PlaybackError? = nil
    private var currentFile: AVAudioFile?
    private var seekPosition: TimeInterval = 0

    // Transition / advance control
    private var nextPending: (nft: NFT, file: AVAudioFile)?
    private var isAdvancing: Bool = false
    private var advanceSequence: Int = 0
    private var crossfadeSwapWorkItem: DispatchWorkItem?
    private var swapSequence: Int = 0

    // System integration state
    private var wasPlayingBeforeInterruption: Bool = false
    private var notificationObservers: [NSObjectProtocol] = []
    private var preloadTasks: [Task<Void, Never>] = []

    // Remote command center state
    private var remoteCommandTokens: [(command: MPRemoteCommand, token: Any)] = []
    private var remoteCommandsRegistered: Bool = false

    internal init(graph: AudioGraph,
                session: AudioSessionManager,
                preloader: Preloader,
                queue: QueueManager,
                crossfade: CrossfadeCoordinator,
                nowPlaying: NowPlayingService,
                crossfadeSeconds: TimeInterval = 2.0,
                skipInterval: TimeInterval = 10.0) {
        self.graph = graph
        self.session = session
        self.preloader = preloader
        self.queue = queue
        self.crossfade = crossfade
        self.nowPlaying = nowPlaying
        self.crossfadeSeconds = crossfadeSeconds
        self.skipInterval = skipInterval
        self.snapshot = PlaybackSnapshot(state: .stopped, track: nil, elapsed: 0, duration: 0, canSkipNext: false, canSkipPrevious: false)
        setupNotifications()
        setupRemoteCommands()
        updateRemoteCommandStates()
    }

    deinit {
        for obs in notificationObservers {
            NotificationCenter.default.removeObserver(obs)
        }
        notificationObservers.removeAll()
        for t in preloadTasks { t.cancel() }
        preloadTasks.removeAll()

        // Remove remote command targets to avoid duplicate handlers and leaks
        for (command, token) in remoteCommandTokens {
            command.removeTarget(token)
        }
        remoteCommandTokens.removeAll()
        remoteCommandsRegistered = false
    }

    /*
     State Machine — Allowed transitions
       Stopped -> Playing, Paused, Error, Stopped (no-op)
       Playing -> Paused, Stopped, Error, Playing (no-op)
       Paused  -> Playing, Stopped, Error, Paused (no-op)
       Error   -> Stopped, Playing (retry), Error (no-op)
     All state changes must go through `commitState(_:)` which enforces the graph.
    */
    private func canTransition(from: PlaybackState, to: PlaybackState) -> Bool {
        switch (from, to) {
        case (.stopped, .playing), (.stopped, .paused), (.stopped, .error), (.stopped, .stopped):
            return true
        case (.playing, .paused), (.playing, .stopped), (.playing, .error), (.playing, .playing):
            return true
        case (.paused, .playing), (.paused, .stopped), (.paused, .error), (.paused, .paused):
            return true
        case (.error, .stopped), (.error, .playing), (.error, .error):
            return true
        default:
            return false
        }
    }

    // MARK: - Public API
    func loadAndPlay(nft: NFT) async {
        await cancelCrossfade()
        do {
            try session.configureAndActivate()
        } catch {
            handleFatalError(.activationFailed)
            return
        }
        do {
            let file = try await openFile(for: nft)
            // Fresh load: no crossfade path. Apply immediately as current.
            nextPending = nil
            applyCurrent(nft: nft, file: file)
            try graph.ensureStarted()
            scheduleFromCurrentPosition()
            graph.playCurrent()
            if !commitState(.playing) { print("[PlaybackController] commitState(.playing) rejected in loadAndPlay") }
            pushNowPlaying()
            maybePreloadNext()
        } catch {
            let category = categorizePlaybackError(error)
            handleFatalError(category)
        }
    }

    public func play() {
        guard snapshot.state != .playing else { return }
        if currentFile == nil, let next = queue.peekNext() { Task { await loadAndPlay(nft: next) } ; return }
        try? graph.ensureStarted()
        scheduleFromCurrentPosition()
        graph.playCurrent()
        if !commitState(.playing) { print("[PlaybackController] commitState(.playing) rejected in play()") }
        pushNowPlaying()
        maybePreloadNext()
    }

    public func pause() {
        guard snapshot.state == .playing else { return }
        seekPosition = currentTime()
        Task { @MainActor in
            await cancelCrossfade()
            graph.currentPlayer.stop(); graph.nextPlayer.stop()
            cancelPendingSwap()
            if !commitState(.paused) { print("[PlaybackController] commitState(.paused) rejected in pause()") }
            pushNowPlaying()
        }
    }

    public func resume() {
        guard snapshot.state == .paused else { return }
        Task { @MainActor in
            await cancelCrossfade()
            graph.currentPlayer.stop(); graph.nextPlayer.stop()
            try? graph.ensureStarted()
            scheduleFromCurrentPosition()
            graph.playCurrent()
            if !commitState(.playing) { print("[PlaybackController] commitState(.playing) rejected in resume()") }
            pushNowPlaying()
        }
    }

    public func seek(to time: TimeInterval) {
        guard let file = currentFile else { return }
        let d = duration(of: file)
        seekPosition = max(0, min(time, d))
        cancelPendingSwap()

        if snapshot.state == .playing {
            Task { @MainActor in
                await cancelCrossfade()
                graph.currentPlayer.stop(); graph.nextPlayer.stop()
                try? graph.ensureStarted()
                scheduleFromCurrentPosition()
                graph.playCurrent()
                if !commitState(.playing) { print("[PlaybackController] commitState(.playing) rejected in seek()") }
                pushNowPlaying()
            }
        } else {
            // Paused or stopped: just update Now Playing with new elapsed time
            pushNowPlaying()
            maybePreloadNext()
        }
    }

    public func skipForward(seconds: TimeInterval? = nil) { seek(to: currentTime() + (seconds ?? skipInterval)) }
    public func skipBackward(seconds: TimeInterval? = nil) { seek(to: currentTime() - (seconds ?? skipInterval)) }

    public func playNext() async {
        await cancelCrossfade()

        // Ensure single serialized advance
        guard !isAdvancing else { return }
        isAdvancing = true
        advanceSequence &+= 1
        let seq = advanceSequence

        defer {
            // Do not reset isAdvancing here if we scheduled a crossfade swap; it will be reset on swap/commit.
            // If no crossfade path is taken, ensure we reset below.
        }

        // If currently playing, attempt crossfade into next
        if snapshot.state == .playing, let next = self.queue.dequeueNext() {
            // Load or consume preloaded next without altering currentFile yet
            var nextFile: AVAudioFile?
            if let url = next.musicURL, let pre = await preloader.consume(nft: next, url: url) {
                nextFile = pre
            } else if let url = next.musicURL {
                do {
                    nextFile = try await openURL(url)
                } catch {
                    let category = categorizePlaybackError(error)
                    handleFatalError(category)
                    isAdvancing = false
                    return
                }
            }

            guard let outgoing = self.currentFile, let incoming = nextFile else {
                // If we cannot crossfade (no outgoing or no incoming), fall back to a direct load and play
                isAdvancing = false
                let fallback = self.queue.current ?? next
                await loadAndPlay(nft: fallback)
                return
            }

            // Prepare next on graph without swapping our model state yet
            do { try graph.ensureStarted() } catch { /* ignore and try to proceed */ }
            graph.setNextPathVolume(0)
            graph.scheduleFileOnNext(incoming, at: nil)
            graph.playNext()

            // Schedule crossfade safely without force unwraps
            let overlap = cappedCrossfade()
            crossfade.scheduleCrossfade(currentFile: outgoing, nextFile: incoming, overlap: overlap, startDelay: 0)

            // Record pending swap and schedule commit after overlap
            nextPending = (nft: next, file: incoming)
            crossfadeSwapWorkItem?.cancel()
            let currentSwapSeq = swapSequence
            let work = DispatchWorkItem { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    // Ensure this commit corresponds to the latest advance request and swap state
                    guard self.advanceSequence == seq, self.swapSequence == currentSwapSeq else { return }
                    self.commitPendingSwap()
                }
            }
            crossfadeSwapWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + overlap, execute: work)
            // isAdvancing will be reset in commitPendingSwap
            return
        }

        // Not currently playing or no next available: load next or stop
        if let next = self.queue.dequeueNext() {
            isAdvancing = false
            await loadAndPlay(nft: next)
        } else {
            isAdvancing = false
            stop()
        }
    }
    
    private func commitPendingSwap() {
        defer { isAdvancing = false }
        guard let pending = nextPending else { return }
        // Apply new current and clear pending
        applyCurrent(nft: pending.nft, file: pending.file)
        nextPending = nil
        if !commitState(.playing) { print("[PlaybackController] commitState(.playing) rejected in commitPendingSwap()") }
        pushNowPlaying()
        maybePreloadNext()
    }

    public func playPrevious() async {
        // use self.queue directly
        // Simple previous: restart track if >1s else pop previous from queue
        if currentTime() > 1.0 { seek(to: 0); return }
        if !self.queue.previous.tracks.isEmpty {
            // Pop previous safely; if structure changes in QueueManager, this guard prevents crashes
            let prev = self.queue.previous.tracks.removeLast()
            if let current = self.queue.current {
                self.queue.pushToFrontOfNext(current)
            }
            await loadAndPlay(nft: prev)
            pushNowPlaying()
        } else {
            seek(to: 0)
        }
    }

    public func stop() {
        Task { @MainActor in
            await cancelCrossfade()
            graph.currentPlayer.stop(); graph.nextPlayer.stop()
            graph.setCurrentPathVolume(0); graph.setNextPathVolume(0)
            currentFile = nil
            seekPosition = 0
            cancelPendingSwap()
            if !commitState(.stopped) { print("[PlaybackController] commitState(.stopped) rejected in stop()") }
            pushNowPlaying()
            clearNowPlaying()
            do {
                try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            } catch {
                print("[PlaybackController] AVAudioSession setActive(false) failed in stop(): \(error)")
            }
            lastError = nil
            for t in preloadTasks { t.cancel() }
            preloadTasks.removeAll()
            updateRemoteCommandStates()
        }
    }

    // MARK: - Helpers
    private func currentTime() -> TimeInterval {
        guard snapshot.state == .playing, let pt = graph.playerTime() else { return seekPosition }
        return seekPosition + Double(pt.sampleTime) / pt.sampleRate
    }

    private func duration(of file: AVAudioFile) -> TimeInterval { Double(file.length) / file.processingFormat.sampleRate }

    private func scheduleFromCurrentPosition() {
        guard let file = currentFile else { return }
        let sr = file.processingFormat.sampleRate
        let startFrame = AVAudioFramePosition(seekPosition * sr)
        // If seek is at or beyond the end, advance without scheduling to avoid zero-frame loops
        if startFrame >= file.length {
            self.currentFile = nil
            Task { @MainActor in
                await self.playNext()
                self.pushNowPlaying()
            }
            return
        }
        let remaining = file.length - startFrame
        if remaining <= 0 { return }
        let frames = AVAudioFrameCount(remaining)
        graph.scheduleFile(file, onCurrentAt: nil, completion: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                // If a crossfade swap is pending or scheduled, do not also advance on completion.
                guard self.nextPending == nil, self.crossfadeSwapWorkItem == nil else { return }
                self.currentFile = nil
                await self.playNext()
                self.pushNowPlaying()
            }
        })
    }

    private func applyCurrent(nft: NFT, file: AVAudioFile) {
        // Note: Only call applyCurrent for fresh loads or after crossfade swap commit.
        currentFile = file
        seekPosition = 0
        let track = Track(title: nft.name, artist: nft.artistName, duration: duration(of: file), imageUrl: nft.image?.secureUrl ?? nft.image?.originalUrl)
        snapshot.track = track
        pushNowPlaying()
        updateRemoteCommandStates()
    }

    private func pushNowPlaying() {
        let rate = snapshot.state == .playing ? 1.0 : 0.0
        nowPlaying.setMetadata(title: snapshot.track?.title, artist: snapshot.track?.artist, duration: snapshot.track?.duration ?? 0, elapsed: currentTime(), rate: rate)
        nowPlaying.setArtwork(from: snapshot.track?.imageUrl)
        nowPlaying.updateProgress(elapsed: currentTime(), rate: rate, duration: snapshot.track?.duration ?? 0)
    }

    @discardableResult
    private func commitState(_ state: PlaybackState) -> Bool {
        let from = snapshot.state
        guard canTransition(from: from, to: state) else {
            print("[PlaybackController] Invalid state transition: \(from) -> \(state)")
            return false
        }
        snapshot.state = state
        snapshot.elapsed = currentTime()
        snapshot.duration = snapshot.track?.duration ?? 0
        snapshot.canSkipNext = (self.queue.peekNext() != nil)
        snapshot.canSkipPrevious = (!self.queue.previous.tracks.isEmpty || currentTime() > 1.0)
        if state != .error { lastError = nil }
        updateRemoteCommandStates()
        return true
    }

    private func handleFatalError(_ category: PlaybackError) {
        Task { @MainActor in
            await cancelCrossfade()
            lastError = category
            graph.currentPlayer.stop(); graph.nextPlayer.stop()
            graph.setCurrentPathVolume(0); graph.setNextPathVolume(0)
            currentFile = nil
            seekPosition = 0
            cancelPendingSwap()
            if !commitState(.error) { print("[PlaybackController] commitState(.error) rejected in handleFatalError") }
            pushNowPlaying()
            clearNowPlaying()
            do {
                try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            } catch {
                print("[PlaybackController] AVAudioSession setActive(false) failed in error state: \(error)")
            }
            updateRemoteCommandStates()
        }
    }

    private func maybePreloadNext() {
        guard let next = queue.peekNext(), let url = next.musicURL else { return }
        let task: Task<Void, Never> = Task { _ = try? await preloader.preload(nft: next, url: url) }
        preloadTasks.append(task)
    }

    private func openFile(for nft: NFT) async throws -> AVAudioFile {
        guard let url = nft.musicURL else { throw URLError(.badURL) }
        return try await openURL(url)
    }

    private func openURL(_ url: URL) async throws -> AVAudioFile {
        return try await Task.detached(priority: .userInitiated) { () -> AVAudioFile in
            let local: URL
            if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
                // Perform cache lookup off the main actor
                let resolved = try await AudioFileCache.shared.localURL(forRemote: url)
                local = resolved
            } else {
                local = url
            }
            return try AVAudioFile(forReading: local)
        }.value
    }

    // Map underlying errors to PlaybackError categories for accurate UX
    private func categorizePlaybackError(_ error: Error) -> PlaybackError {
        // Prefer network categorization for URL-related failures
        if let urlErr = error as? URLError { return .networkUnavailable }
        let nsErr = error as NSError
        if nsErr.domain == NSURLErrorDomain { return .networkUnavailable }
        // AVAudioFile and file IO typically surface as Cocoa/OSStatus errors; treat as unreadable
        // Fallback to unknown if nothing matches
        return .fileUnreadable
    }

    // Centralized cancellation for any pending crossfade swap and advancement lock
    private func cancelPendingSwap() {
        // Invalidate any scheduled swap work and clear pending state
        crossfadeSwapWorkItem?.cancel()
        crossfadeSwapWorkItem = nil
        nextPending = nil
        // Bump the swap sequence so any already queued work items will no-op
        swapSequence &+= 1
        // Ensure future advances are not blocked by a canceled swap
        isAdvancing = false
    }

    private func cancelCrossfade() async {
        // First invalidate controller-side pending swap to prevent late commits
        cancelPendingSwap()
        // Then cancel coordinator work; assumed to stop ramps promptly
        await crossfade.cancel()
    }

    private func cappedCrossfade() -> TimeInterval { min(crossfadeSeconds, max(0, (snapshot.track?.duration ?? 0) * 0.3)) }

    // MARK: - System Integration Helpers
    private func setupNotifications() {
        let center = NotificationCenter.default
        let obs1 = center.addObserver(forName: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(), queue: .main) { [weak self] note in
            self?.handleInterruption(note)
        }
        let obs2 = center.addObserver(forName: AVAudioSession.routeChangeNotification, object: AVAudioSession.sharedInstance(), queue: .main) { [weak self] note in
            self?.handleRouteChange(note)
        }
        notificationObservers.append(contentsOf: [obs1, obs2])
    }

    private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            wasPlayingBeforeInterruption = (snapshot.state == .playing)
            if wasPlayingBeforeInterruption {
                pause()
            }
        case .ended:
            let shouldResume = (info[AVAudioSessionInterruptionOptionKey] as? UInt).map { AVAudioSession.InterruptionOptions(rawValue: $0).contains(.shouldResume) } ?? false
            if shouldResume, wasPlayingBeforeInterruption {
                do {
                    try session.configureAndActivate()
                    // Only resume if we still have a valid file; otherwise try to load the next item
                    if currentFile != nil {
                        resume()
                    } else if let next = queue.peekNext() {
                        Task { @MainActor in await self.loadAndPlay(nft: next) }
                    }
                } catch {
                    // If we cannot reactivate, remain paused and surface the error state
                    handleFatalError(.activationFailed)
                }
            }
            wasPlayingBeforeInterruption = false
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard let info = notification.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }
        // Common policy: if old device became unavailable (e.g., headphones unplugged), pause.
        if reason == .oldDeviceUnavailable {
            if snapshot.state == .playing {
                pause()
            }
        }
    }

    private func setupRemoteCommands() {
        // Ensure idempotent registration across controller lifecycles
        if remoteCommandsRegistered {
            updateRemoteCommandStates()
            return
        }

        let center = MPRemoteCommandCenter.shared()

        let playToken = center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.play() }
            return .success
        }
        remoteCommandTokens.append((command: center.playCommand, token: playToken))

        let pauseToken = center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        remoteCommandTokens.append((command: center.pauseCommand, token: pauseToken))

        let nextToken = center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in await self?.playNext() }
            return .success
        }
        remoteCommandTokens.append((command: center.nextTrackCommand, token: nextToken))

        let prevToken = center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in await self?.playPrevious() }
            return .success
        }
        remoteCommandTokens.append((command: center.previousTrackCommand, token: prevToken))

        let scrubToken = center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: e.positionTime) }
            return .success
        }
        remoteCommandTokens.append((command: center.changePlaybackPositionCommand, token: scrubToken))

        remoteCommandsRegistered = true
        updateRemoteCommandStates()
    }

    private func updateRemoteCommandStates() {
        let center = MPRemoteCommandCenter.shared()
        // Play is enabled when not already playing and we have something to play
        center.playCommand.isEnabled = (snapshot.state != .playing) && (currentFile != nil || queue.peekNext() != nil)
        // Pause is enabled only when currently playing
        center.pauseCommand.isEnabled = (snapshot.state == .playing)
        // Next/previous reflect queue and elapsed logic
        center.nextTrackCommand.isEnabled = snapshot.canSkipNext
        center.previousTrackCommand.isEnabled = snapshot.canSkipPrevious
        // Scrubbing only when there is a current or loaded track
        center.changePlaybackPositionCommand.isEnabled = (snapshot.track != nil)
    }

    private func clearNowPlaying() {
        // Neutralize metadata/artwork/progress to avoid stale system surfaces
        nowPlaying.setMetadata(title: nil, artist: nil, duration: 0, elapsed: 0, rate: 0)
        nowPlaying.setArtwork(from: nil)
        nowPlaying.updateProgress(elapsed: 0, rate: 0, duration: 0)
    }
}
