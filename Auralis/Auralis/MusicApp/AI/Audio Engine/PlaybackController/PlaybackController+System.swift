import Foundation
import AVFoundation

@MainActor
extension PlaybackController {
    func setupNotifications() {
        let center = NotificationCenter.default
        let obs1 = center.addObserver(forName: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(), queue: .main) { [weak self] note in
            self?.handleInterruption(note)
        }
        let obs2 = center.addObserver(forName: AVAudioSession.routeChangeNotification, object: AVAudioSession.sharedInstance(), queue: .main) { [weak self] note in
            self?.handleRouteChange(note)
        }
        notificationObservers.append(contentsOf: [obs1, obs2])
    }

    func handleInterruption(_ notification: Notification) {
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

    func handleRouteChange(_ notification: Notification) {
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
}
