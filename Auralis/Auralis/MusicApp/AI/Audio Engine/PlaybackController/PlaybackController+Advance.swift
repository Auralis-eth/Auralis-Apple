import Foundation
import AVFoundation

@MainActor
extension PlaybackController {
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
    
    func commitPendingSwap() {
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

    func cancelPendingSwap() {
        // Invalidate any scheduled swap work and clear pending state
        crossfadeSwapWorkItem?.cancel()
        crossfadeSwapWorkItem = nil
        nextPending = nil
        // Bump the swap sequence so any already queued work items will no-op
        swapSequence &+= 1
        // Ensure future advances are not blocked by a canceled swap
        isAdvancing = false
    }

    func cancelCrossfade() async {
        // First invalidate controller-side pending swap to prevent late commits
        cancelPendingSwap()
        // Then cancel coordinator work; assumed to stop ramps promptly
        await crossfade.cancel()
    }

    func cappedCrossfade() -> TimeInterval { min(crossfadeSeconds, max(0, (snapshot.track?.duration ?? 0) * 0.3)) }
}
