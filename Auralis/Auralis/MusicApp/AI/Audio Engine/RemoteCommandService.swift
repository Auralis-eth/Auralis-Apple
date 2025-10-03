import Foundation
import MediaPlayer

public protocol NowPlayingCentering {
    var nowPlayingInfo: [String: Any]? { get set }
}

public struct DefaultNowPlayingCenter: NowPlayingCentering {
    public init() {}
    public var center: MPNowPlayingInfoCenter { MPNowPlayingInfoCenter.default() }
    public var nowPlayingInfo: [String : Any]? {
        get { center.nowPlayingInfo }
        set { center.nowPlayingInfo = newValue }
    }
}

@MainActor
public final class RemoteCommandService {
    private let center = MPRemoteCommandCenter.shared()
    private var registered = false

    public var onPlay: (() -> Void)?
    public var onPause: (() -> Void)?
    public var onToggle: (() -> Void)?
    public var onNext: (() -> Void)?
    public var onPrevious: (() -> Void)?
    public var onSeek: ((TimeInterval) -> Void)?
    public var onSkipForward: ((TimeInterval) -> Void)?
    public var onSkipBackward: ((TimeInterval) -> Void)?

    public init() {}

    public func register(skipInterval: TimeInterval) {
        guard !registered else { return }
        registered = true
        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in self?.onPlay?(); return .success }
        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in self?.onPause?(); return .success }
        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in self?.onToggle?(); return .success }
        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { [weak self] _ in self?.onNext?(); return .success }
        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { [weak self] _ in self?.onPrevious?(); return .success }
        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { [weak self] e in
            guard let e = e as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.onSeek?(e.positionTime)
            return .success
        }
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: skipInterval)]
        center.skipForwardCommand.isEnabled = true
        center.skipForwardCommand.addTarget { [weak self] e in
            guard let e = e as? MPSkipIntervalCommandEvent else { return .commandFailed }
            self?.onSkipForward?(e.interval)
            return .success
        }
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: skipInterval)]
        center.skipBackwardCommand.isEnabled = true
        center.skipBackwardCommand.addTarget { [weak self] e in
            guard let e = e as? MPSkipIntervalCommandEvent else { return .commandFailed }
            self?.onSkipBackward?(e.interval)
            return .success
        }
    }

    public func setAvailability(canNext: Bool, canPrevious: Bool, canScrub: Bool) {
        center.nextTrackCommand.isEnabled = canNext
        center.previousTrackCommand.isEnabled = canPrevious
        center.changePlaybackPositionCommand.isEnabled = canScrub
        center.skipForwardCommand.isEnabled = canScrub
        center.skipBackwardCommand.isEnabled = canScrub
    }

    public func unregister() {
        guard registered else { return }
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)
        center.nextTrackCommand.removeTarget(nil)
        center.previousTrackCommand.removeTarget(nil)
        center.changePlaybackPositionCommand.removeTarget(nil)
        center.skipForwardCommand.removeTarget(nil)
        center.skipBackwardCommand.removeTarget(nil)
        registered = false
    }
}
