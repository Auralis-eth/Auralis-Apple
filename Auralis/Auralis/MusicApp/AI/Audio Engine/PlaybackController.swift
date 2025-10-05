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

    public init(graph: AudioGraph,
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
            
        }
        do {
            let file = try await openFile(for: nft)
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

    public func resume() { guard snapshot.state == .paused else { return }; play() }

    public func seek(to time: TimeInterval) {
        guard let file = currentFile else { return }
        let d = duration(of: file)
        seekPosition = max(0, min(time, d))
        if snapshot.state == .playing { play() } else { pushNowPlaying() }
    }

    public func skipForward(seconds: TimeInterval? = nil) { seek(to: currentTime() + (seconds ?? skipInterval)) }
    public func skipBackward(seconds: TimeInterval? = nil) { seek(to: currentTime() - (seconds ?? skipInterval)) }

    public func playNext() async {
        await cancelCrossfade()
        // use self.queue directly
        if snapshot.state == .playing, let next = self.queue.dequeueNext() {
            // Try preloaded consume first
            if let url = next.musicURL, let pre = await preloader.consumeIfMatches(nft: next, url: url) {
                applyCurrent(nft: next, file: pre)
                try? graph.ensureStarted()
                graph.setNextPathVolume(0)
                graph.scheduleFileOnNext(pre, at: nil)
                graph.playNext()
                crossfade.scheduleCrossfade(currentFile: currentFile!, nextFile: pre, overlap: cappedCrossfade(), startDelay: 0)
                return
            }
            // Fallback: load and crossfade immediately
            if let url = next.musicURL {
                do {
                    let file = try await openURL(url)
                    applyCurrent(nft: next, file: file)
                    try? graph.ensureStarted()
                    graph.setNextPathVolume(0)
                    graph.scheduleFileOnNext(file, at: nil)
                    graph.playNext()
                    crossfade.scheduleCrossfade(currentFile: currentFile!, nextFile: file, overlap: cappedCrossfade(), startDelay: 0)
                } catch { commitState(.error) }
            }
        } else {
            if let next = self.queue.dequeueNext() { await loadAndPlay(nft: next) } else { stop() }
        }
    }

    public func playPrevious() async {
        // use self.queue directly
        // Simple previous: restart track if >1s else pop previous from queue
        if currentTime() > 1.0 { seek(to: 0); return }
        if !self.queue.previous.tracks.isEmpty {
            let prev = self.queue.previous.tracks.removeLast()
            if let current = self.queue.current { self.queue.pushToFrontOfNext(current) }
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
                await self.playNext()
            }
        })
    }

    private func applyCurrent(nft: NFT, file: AVAudioFile) {
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
        Task { await preloader.preload(nft: next, url: url) }
    }

    private func openFile(for nft: NFT) async throws -> AVAudioFile {
        guard let url = nft.musicURL else { throw URLError(.badURL) }
        return try await openURL(url)
    }

    private func openURL(_ url: URL) async throws -> AVAudioFile {
        let local: URL
        if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            local = try await AudioFileCache.shared.localURL(forRemote: url)
        } else { local = url }
        return try AVAudioFile(forReading: local)
    }

    private func cancelCrossfade() async { crossfade.cancel() }

    private func cappedCrossfade() -> TimeInterval { min(crossfadeSeconds, max(0, (snapshot.track?.duration ?? 0) * 0.3)) }
}
