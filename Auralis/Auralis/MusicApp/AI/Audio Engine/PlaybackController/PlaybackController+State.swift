import Foundation
import AVFoundation

public enum PlaybackError: Equatable {
    case activationFailed
    case fileUnreadable
    case networkUnavailable
    case unknown
}

@MainActor
extension PlaybackController {
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

    @discardableResult
    func commitState(_ state: PlaybackState) -> Bool {
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

    func handleFatalError(_ category: PlaybackError) {
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
}

