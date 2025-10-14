import Foundation
import AVFoundation
import Combine

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
    private var currentFile: AVAudioFile?
    private var seekPosition: TimeInterval = 0

    // Transition / advance control
    private var nextPending: (nft: NFT, file: AVAudioFile)?
    private var isAdvancing: Bool = false
    private var advanceSequence: Int = 0
    private var crossfadeSwapWorkItem: DispatchWorkItem?

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
    }

    // MARK: - Public API
    func loadAndPlay(nft: NFT) async {
        await cancelCrossfade()
        do {
            try session.configureAndActivate()
        } catch {
            // Session activation failure; continue and let playback attempt proceed. Errors will surface in playback.
        }
        do {
            let file = try await openFile(for: nft)
            // Fresh load: no crossfade path. Apply immediately as current.
            nextPending = nil
            applyCurrent(nft: nft, file: file)
            try graph.ensureStarted()
            scheduleFromCurrentPosition()
            graph.playCurrent()
            commitState(.playing)
            pushNowPlaying()
            maybePreloadNext()
        } catch {
            commitState(.error)
        }
    }

    public func play() {
        guard snapshot.state != .playing else { return }
        if currentFile == nil, let next = queue.peekNext() { Task { await loadAndPlay(nft: next) } ; return }
        try? graph.ensureStarted()
        scheduleFromCurrentPosition()
        graph.playCurrent()
        commitState(.playing)
        pushNowPlaying()
    }

    public func pause() {
        guard snapshot.state == .playing else { return }
        seekPosition = currentTime()
        graph.currentPlayer.stop(); graph.nextPlayer.stop()
        commitState(.paused)
        pushNowPlaying()
    }

    public func resume() {
        guard snapshot.state == .paused else { return }
        // Cancel any crossfade and ensure a clean graph before resuming
        Task { await cancelCrossfade() }
        graph.currentPlayer.stop(); graph.nextPlayer.stop()
        try? graph.ensureStarted()
        scheduleFromCurrentPosition()
        graph.playCurrent()
        commitState(.playing)
        pushNowPlaying()
    }

    public func seek(to time: TimeInterval) {
        guard let file = currentFile else { return }
        let d = duration(of: file)
        seekPosition = max(0, min(time, d))

        if snapshot.state == .playing {
            // Cancel crossfade and clear any scheduled playback to avoid overlap
            Task { await cancelCrossfade() }
            graph.currentPlayer.stop(); graph.nextPlayer.stop()
            try? graph.ensureStarted()
            scheduleFromCurrentPosition()
            graph.playCurrent()
            commitState(.playing)
            pushNowPlaying()
        } else {
            // Paused or stopped: just update Now Playing with new elapsed time
            pushNowPlaying()
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
                    commitState(.error)
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
            let work = DispatchWorkItem { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    // Ensure this commit corresponds to the latest advance request
                    guard self.advanceSequence == seq else { return }
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
        commitState(.playing)
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
        } else {
            seek(to: 0)
        }
    }

    public func stop() {
        graph.currentPlayer.stop(); graph.nextPlayer.stop()
        graph.setCurrentPathVolume(0); graph.setNextPathVolume(0)
        currentFile = nil
        seekPosition = 0
        commitState(.stopped)
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
        let frames = AVAudioFrameCount(max(0, file.length - startFrame))
        if frames == 0 { return }
        graph.scheduleFile(file, onCurrentAt: nil, completion: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.currentFile = nil
                // Use serialized advance to avoid re-entrancy
                await self.playNext()
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
    }

    private func pushNowPlaying() {
        let rate = snapshot.state == .playing ? 1.0 : 0.0
        nowPlaying.setMetadata(title: snapshot.track?.title, artist: snapshot.track?.artist, duration: snapshot.track?.duration ?? 0, elapsed: currentTime(), rate: rate)
        nowPlaying.setArtwork(from: snapshot.track?.imageUrl)
        nowPlaying.updateProgress(elapsed: currentTime(), rate: rate, duration: snapshot.track?.duration ?? 0)
    }

    private func commitState(_ state: PlaybackState) {
        snapshot.state = state
        snapshot.elapsed = currentTime()
        snapshot.duration = snapshot.track?.duration ?? 0
        snapshot.canSkipNext = (self.queue.peekNext() != nil)
        snapshot.canSkipPrevious = (!self.queue.previous.tracks.isEmpty || currentTime() > 1.0)
    }

    private func maybePreloadNext() {
        guard let next = queue.peekNext(), let url = next.musicURL else { return }
        Task { try? await preloader.preload(nft: next, url: url) }
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

    private func cancelCrossfade() async { crossfade.cancel() }

    private func cappedCrossfade() -> TimeInterval { min(crossfadeSeconds, max(0, (snapshot.track?.duration ?? 0) * 0.3)) }
}
