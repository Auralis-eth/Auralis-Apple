import Foundation
import AVFoundation

@MainActor
extension PlaybackController {
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

    func currentTime() -> TimeInterval {
        guard snapshot.state == .playing, let pt = graph.playerTime() else { return seekPosition }
        return seekPosition + Double(pt.sampleTime) / pt.sampleRate
    }

    func duration(of file: AVAudioFile) -> TimeInterval { Double(file.length) / file.processingFormat.sampleRate }

    func scheduleFromCurrentPosition() {
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

    func applyCurrent(nft: NFT, file: AVAudioFile) {
        // Note: Only call applyCurrent for fresh loads or after crossfade swap commit.
        currentFile = file
        seekPosition = 0
        let track = Track(title: nft.name, artist: nft.artistName, duration: duration(of: file), imageUrl: nft.image?.secureUrl ?? nft.image?.originalUrl)
        snapshot.track = track
        pushNowPlaying()
        updateRemoteCommandStates()
    }
}
