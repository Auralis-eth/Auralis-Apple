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

    private var desiredAvailability: (next: Bool, previous: Bool, skip: Bool, scrub: Bool) = (false, false, false, false)

    private var playToken: Any?
    private var pauseToken: Any?
    private var toggleToken: Any?
    private var nextToken: Any?
    private var previousToken: Any?
    private var seekToken: Any?
    private var skipForwardToken: Any?
    private var skipBackwardToken: Any?

    // Captures the enablement state of commands before this service modifies them
    private var previousEnabled: (play: Bool, pause: Bool, toggle: Bool, next: Bool, previous: Bool, seek: Bool, skipForward: Bool, skipBackward: Bool)?

    // Tracks the last play/pause state we exposed while registered (R20)
    private var lastIsPlaying: Bool?

    // Snapshot of skip intervals before this service modifies them (R22)
    private var previousSkipIntervals: (forward: [NSNumber]?, backward: [NSNumber]?)?
    // Tracks the last intervals we set while registered (R22)
    private var lastSkipIntervals: (forward: [NSNumber]?, backward: [NSNumber]?)?

    public var onPlay: (() -> Void)?
    public var onPause: (() -> Void)?
    public var onToggle: (() -> Void)?
    public var onNext: (() -> Void)?
    public var onPrevious: (() -> Void)?
    public var onSeek: ((TimeInterval) -> Void)?
    public var onSkipForward: ((TimeInterval) -> Void)?
    public var onSkipBackward: ((TimeInterval) -> Void)?

    /// Runs before `onPlay`. Return `.success` to indicate handling is complete and skip `onPlay`.
    /// Return `.noSuchContent` when there is no current item to play.
    ///
    /// Example:
    /// ```swift
    /// service.onPlayStatus = { hasCurrentItem ? .success : .noSuchContent }
    /// ```
    public var onPlayStatus: (() -> MPRemoteCommandHandlerStatus)?

    /// Runs before `onPause`. Return `.success` to skip `onPause`.
    /// Return `.noSuchContent` if there is no content to pause.
    public var onPauseStatus: (() -> MPRemoteCommandHandlerStatus)?

    /// Runs before `onToggle`. Return `.success` to skip `onToggle`.
    /// Return `.noSuchContent` when no current item exists.
    public var onToggleStatus: (() -> MPRemoteCommandHandlerStatus)?

    /// Runs before `onNext`. Return `.success` to skip `onNext`.
    /// Return `.noSuchContent` if there is no next item.
    public var onNextStatus: (() -> MPRemoteCommandHandlerStatus)?

    /// Runs before `onPrevious`. Return `.success` to skip `onPrevious`.
    /// Return `.noSuchContent` if there is no previous item.
    public var onPreviousStatus: (() -> MPRemoteCommandHandlerStatus)?

    /// Runs before `onSeek` with the target time. Return `.success` to skip `onSeek`.
    /// Return `.noSuchContent` when no current item exists.
    public var onSeekStatus: ((TimeInterval) -> MPRemoteCommandHandlerStatus)?

    /// Runs before `onSkipForward` with the interval. Return `.success` to skip `onSkipForward`.
    /// Return `.noSuchContent` when no current item exists.
    public var onSkipForwardStatus: ((TimeInterval) -> MPRemoteCommandHandlerStatus)?

    /// Runs before `onSkipBackward` with the interval. Return `.success` to skip `onSkipBackward`.
    /// Return `.noSuchContent` when no current item exists.
    public var onSkipBackwardStatus: ((TimeInterval) -> MPRemoteCommandHandlerStatus)?

    public init() {}

    /// Registers remote command handlers.
    /// - Parameter skipInterval: Preferred skip interval in seconds. Values less than 1s are clamped to 1s.
    ///   The service stores handler tokens so that only its handlers are removed on `unregister()`.
    public func register(skipInterval: TimeInterval) {
        guard !registered else { return }
        let clampedSkipInterval = max(1.0, skipInterval)
        registered = true

        // Capture prior enablement to restore on teardown (R16)
        previousEnabled = (
            play: center.playCommand.isEnabled,
            pause: center.pauseCommand.isEnabled,
            toggle: center.togglePlayPauseCommand.isEnabled,
            next: center.nextTrackCommand.isEnabled,
            previous: center.previousTrackCommand.isEnabled,
            seek: center.changePlaybackPositionCommand.isEnabled,
            skipForward: center.skipForwardCommand.isEnabled,
            skipBackward: center.skipBackwardCommand.isEnabled
        )

        // Snapshot current skip intervals to restore on teardown (R22)
        previousSkipIntervals = (
            forward: center.skipForwardCommand.preferredIntervals,
            backward: center.skipBackwardCommand.preferredIntervals
        )

        center.playCommand.isEnabled = true
        playToken = center.playCommand.addTarget { [weak self] _ in
            if let st = self?.onPlayStatus?() { return st }
            if let cb = self?.onPlay { cb(); return .success }
            return .noSuchContent
        }
        center.pauseCommand.isEnabled = false
        pauseToken = center.pauseCommand.addTarget { [weak self] _ in
            if let st = self?.onPauseStatus?() { return st }
            if let cb = self?.onPause { cb(); return .success }
            return .noSuchContent
        }
        center.togglePlayPauseCommand.isEnabled = true
        toggleToken = center.togglePlayPauseCommand.addTarget { [weak self] _ in
            if let st = self?.onToggleStatus?() { return st }
            if let cb = self?.onToggle { cb(); return .success }
            return .noSuchContent
        }
        // center.nextTrackCommand.isEnabled = true  // removed eager enablement
        nextToken = center.nextTrackCommand.addTarget { [weak self] _ in
            if let st = self?.onNextStatus?() { return st }
            if let cb = self?.onNext { cb(); return .success }
            return .noSuchContent
        }
        // center.previousTrackCommand.isEnabled = true  // removed eager enablement
        previousToken = center.previousTrackCommand.addTarget { [weak self] _ in
            if let st = self?.onPreviousStatus?() { return st }
            if let cb = self?.onPrevious { cb(); return .success }
            return .noSuchContent
        }
        // center.changePlaybackPositionCommand.isEnabled = true  // removed eager enablement
        seekToken = center.changePlaybackPositionCommand.addTarget { [weak self] e in
            guard let e = e as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            if let st = self?.onSeekStatus?(e.positionTime) { return st }
            if let cb = self?.onSeek { cb(e.positionTime); return .success }
            return .noSuchContent
        }
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: clampedSkipInterval)]
        // Track what we set (R22)
        lastSkipIntervals = (
            forward: center.skipForwardCommand.preferredIntervals,
            backward: center.skipBackwardCommand.preferredIntervals
        )
        // center.skipForwardCommand.isEnabled = true  // removed eager enablement
        skipForwardToken = center.skipForwardCommand.addTarget { [weak self] e in
            guard let e = e as? MPSkipIntervalCommandEvent else { return .commandFailed }
            if let st = self?.onSkipForwardStatus?(e.interval) { return st }
            if let cb = self?.onSkipForward { cb(e.interval); return .success }
            return .noSuchContent
        }
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: clampedSkipInterval)]
        lastSkipIntervals = (
            forward: center.skipForwardCommand.preferredIntervals,
            backward: center.skipBackwardCommand.preferredIntervals
        )
        // center.skipBackwardCommand.isEnabled = true  // removed eager enablement
        skipBackwardToken = center.skipBackwardCommand.addTarget { [weak self] e in
            guard let e = e as? MPSkipIntervalCommandEvent else { return .commandFailed }
            if let st = self?.onSkipBackwardStatus?(e.interval) { return st }
            if let cb = self?.onSkipBackward { cb(e.interval); return .success }
            return .noSuchContent
        }

        // Apply staged availability once handlers are in place
        setAvailability(canNext: desiredAvailability.next,
                        canPrevious: desiredAvailability.previous,
                        canSkip: desiredAvailability.skip,
                        canScrub: desiredAvailability.scrub)
    }

    public func setAvailability(canNext: Bool, canPrevious: Bool, canSkip: Bool, canScrub: Bool) {
        desiredAvailability = (canNext, canPrevious, canSkip, canScrub)
        guard registered else { return } // avoid exposing controls without handlers
        center.nextTrackCommand.isEnabled = canNext
        center.previousTrackCommand.isEnabled = canPrevious
        center.skipForwardCommand.isEnabled = canSkip
        center.skipBackwardCommand.isEnabled = canSkip
        center.changePlaybackPositionCommand.isEnabled = canScrub
    }

    /// Update preferred skip intervals for forward/backward commands while registered.
    /// Values less than 1s are clamped to 1s.
    public func updateSkipInterval(_ interval: TimeInterval) {
        guard registered else { return }
        let clamped = max(1.0, interval)
        center.skipForwardCommand.preferredIntervals  = [NSNumber(value: clamped)]
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: clamped)]
        lastSkipIntervals = (
            forward: center.skipForwardCommand.preferredIntervals,
            backward: center.skipBackwardCommand.preferredIntervals
        )
    }

    /// Applies safe defaults in one call (R18). Call this immediately after `register`.
    /// - Parameters:
    ///   - isPlaying: Current playback state used to set play/pause enablement.
    ///   - availability: Tuple of booleans controlling next/previous/skip/scrub enablement.
    ///     Equivalent to calling `setPlaybackState(isPlaying:)` then `setAvailability(…)`.
    public func applyInitialState(
        isPlaying: Bool,
        availability: (next: Bool, previous: Bool, skip: Bool, scrub: Bool)
    ) {
        setPlaybackState(isPlaying: isPlaying)
        setAvailability(
            canNext: availability.next,
            canPrevious: availability.previous,
            canSkip: availability.skip,
            canScrub: availability.scrub
        )
    }

    /// Toggle Play/Pause command enablement based on playback state.
    public func setPlaybackState(isPlaying: Bool) {
        guard registered else { return }
        lastIsPlaying = isPlaying
        center.playCommand.isEnabled  = !isPlaying
        center.pauseCommand.isEnabled =  isPlaying
        // togglePlayPause can remain enabled regardless of state
    }

    public func unregister() {
        guard registered else { return }
        center.playCommand.removeTarget(playToken)
        center.pauseCommand.removeTarget(pauseToken)
        center.togglePlayPauseCommand.removeTarget(toggleToken)
        center.nextTrackCommand.removeTarget(nextToken)
        center.previousTrackCommand.removeTarget(previousToken)
        center.changePlaybackPositionCommand.removeTarget(seekToken)
        center.skipForwardCommand.removeTarget(skipForwardToken)
        center.skipBackwardCommand.removeTarget(skipBackwardToken)

        if let prev = previousEnabled {
            // Compute expected states based on what this service last set (R16b)
            let expectedPlayEnabled: Bool  = (lastIsPlaying.map { !$0 }) ?? true
            let expectedPauseEnabled: Bool = (lastIsPlaying.map {  $0 }) ?? false
            let expectedToggleEnabled: Bool = true
            let expectedNextEnabled: Bool = desiredAvailability.next
            let expectedPreviousEnabled: Bool = desiredAvailability.previous
            let expectedSeekEnabled: Bool = desiredAvailability.scrub
            let expectedSkipEnabled: Bool = desiredAvailability.skip

            // Only restore if current still matches what we last set; otherwise, leave as-is
            if center.playCommand.isEnabled == expectedPlayEnabled { center.playCommand.isEnabled = prev.play }
            if center.pauseCommand.isEnabled == expectedPauseEnabled { center.pauseCommand.isEnabled = prev.pause }
            if center.togglePlayPauseCommand.isEnabled == expectedToggleEnabled { center.togglePlayPauseCommand.isEnabled = prev.toggle }
            if center.nextTrackCommand.isEnabled == expectedNextEnabled { center.nextTrackCommand.isEnabled = prev.next }
            if center.previousTrackCommand.isEnabled == expectedPreviousEnabled { center.previousTrackCommand.isEnabled = prev.previous }
            if center.changePlaybackPositionCommand.isEnabled == expectedSeekEnabled { center.changePlaybackPositionCommand.isEnabled = prev.seek }
            if center.skipForwardCommand.isEnabled == expectedSkipEnabled { center.skipForwardCommand.isEnabled = prev.skipForward }
            if center.skipBackwardCommand.isEnabled == expectedSkipEnabled { center.skipBackwardCommand.isEnabled = prev.skipBackward }
        }

        if let prevIntervals = previousSkipIntervals, let lastSet = lastSkipIntervals {
            // Only restore if current still matches what we last set (R22)
            let currentFwd = center.skipForwardCommand.preferredIntervals
            let currentBack = center.skipBackwardCommand.preferredIntervals
            if let lastFwd = lastSet.forward, currentFwd == lastFwd, let prevFwd = prevIntervals.forward {
                center.skipForwardCommand.preferredIntervals = prevFwd
            }
            if let lastBack = lastSet.backward, currentBack == lastBack, let prevBack = prevIntervals.backward {
                center.skipBackwardCommand.preferredIntervals = prevBack
            }
        }

        playToken = nil
        pauseToken = nil
        toggleToken = nil
        nextToken = nil
        previousToken = nil
        seekToken = nil
        skipForwardToken = nil
        skipBackwardToken = nil

        previousEnabled = nil
        previousSkipIntervals = nil
        lastSkipIntervals = nil

        registered = false
    }

    deinit {
        // Copy references and tokens locally to avoid capturing `self` in the Task
        let center = self.center
        let playToken = self.playToken
        let pauseToken = self.pauseToken
        let toggleToken = self.toggleToken
        let nextToken = self.nextToken
        let previousToken = self.previousToken
        let seekToken = self.seekToken
        let skipForwardToken = self.skipForwardToken
        let skipBackwardToken = self.skipBackwardToken
        let previousEnabled = self.previousEnabled
        let desiredAvailability = self.desiredAvailability
        let lastIsPlaying = self.lastIsPlaying
        let previousSkipIntervals = self.previousSkipIntervals
        let lastSkipIntervals = self.lastSkipIntervals

        guard registered else { return }
        center.playCommand.removeTarget(playToken)
        center.pauseCommand.removeTarget(pauseToken)
        center.togglePlayPauseCommand.removeTarget(toggleToken)
        center.nextTrackCommand.removeTarget(nextToken)
        center.previousTrackCommand.removeTarget(previousToken)
        center.changePlaybackPositionCommand.removeTarget(seekToken)
        center.skipForwardCommand.removeTarget(skipForwardToken)
        center.skipBackwardCommand.removeTarget(skipBackwardToken)

        if let prev = previousEnabled {
            let expectedPlayEnabled: Bool  = (lastIsPlaying.map { !$0 }) ?? true
            let expectedPauseEnabled: Bool = (lastIsPlaying.map {  $0 }) ?? false
            let expectedToggleEnabled: Bool = true
            let expectedNextEnabled: Bool = desiredAvailability.next
            let expectedPreviousEnabled: Bool = desiredAvailability.previous
            let expectedSeekEnabled: Bool = desiredAvailability.scrub
            let expectedSkipEnabled: Bool = desiredAvailability.skip

            if center.playCommand.isEnabled == expectedPlayEnabled { center.playCommand.isEnabled = prev.play }
            if center.pauseCommand.isEnabled == expectedPauseEnabled { center.pauseCommand.isEnabled = prev.pause }
            if center.togglePlayPauseCommand.isEnabled == expectedToggleEnabled { center.togglePlayPauseCommand.isEnabled = prev.toggle }
            if center.nextTrackCommand.isEnabled == expectedNextEnabled { center.nextTrackCommand.isEnabled = prev.next }
            if center.previousTrackCommand.isEnabled == expectedPreviousEnabled { center.previousTrackCommand.isEnabled = prev.previous }
            if center.changePlaybackPositionCommand.isEnabled == expectedSeekEnabled { center.changePlaybackPositionCommand.isEnabled = prev.seek }
            if center.skipForwardCommand.isEnabled == expectedSkipEnabled { center.skipForwardCommand.isEnabled = prev.skipForward }
            if center.skipBackwardCommand.isEnabled == expectedSkipEnabled { center.skipBackwardCommand.isEnabled = prev.skipBackward }
        }

        if let prevIntervals = previousSkipIntervals, let lastSet = lastSkipIntervals {
            let currentFwd = center.skipForwardCommand.preferredIntervals
            let currentBack = center.skipBackwardCommand.preferredIntervals
            if let lastFwd = lastSet.forward, currentFwd == lastFwd, let prevFwd = prevIntervals.forward {
                center.skipForwardCommand.preferredIntervals = prevFwd
            }
            if let lastBack = lastSet.backward, currentBack == lastBack, let prevBack = prevIntervals.backward {
                center.skipBackwardCommand.preferredIntervals = prevBack
            }
        }
    }
}

