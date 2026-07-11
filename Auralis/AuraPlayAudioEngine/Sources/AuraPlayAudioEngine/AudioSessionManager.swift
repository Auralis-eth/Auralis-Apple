import Foundation

#if os(iOS) || os(tvOS) || os(watchOS)
import AVFoundation

public final class AudioSessionManager: AudioSessionManaging, @unchecked Sendable {
    private let session: AVAudioSession
    private let notificationCenter: NotificationCenter
    private let eventsBroadcast = AsyncBroadcast<AudioSessionEvent>()
    private var observerTokens: [NSObjectProtocol] = []

    public var events: AsyncStream<AudioSessionEvent> {
        eventsBroadcast.stream()
    }

    public init(
        session: AVAudioSession = AVAudioSession.sharedInstance(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.session = session
        self.notificationCenter = notificationCenter
        installObservers()
    }

    deinit {
        observerTokens.forEach(notificationCenter.removeObserver)
        eventsBroadcast.finish()
    }

    public func configure() async throws {
        try session.setCategory(
            .playback,
            mode: .default,
            policy: .longFormAudio,
            options: [.allowBluetoothA2DP, .allowAirPlay]
        )
    }

    public func activate() async throws {
        try session.setActive(true)
    }

    public func deactivate() async throws {
        try session.setActive(false)
    }

    public func configureForSpokenAudio() async throws {
        try session.setCategory(
            .playback,
            mode: .spokenAudio,
            policy: .longFormAudio,
            options: [.allowBluetoothA2DP, .allowAirPlay]
        )
    }

    public func setSupportsMultichannelContent(_ supports: Bool) async throws {
        try session.setSupportsMultichannelContent(supports)
    }

    public func currentSpatialAudioEnabled() async -> Bool {
        currentSpatialAudioEnabledValue()
    }

    private func installObservers() {
        let routeToken = notificationCenter.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: nil
        ) { [weak self] notification in
            self?.handleRouteChange(notification)
        }

        let interruptionToken = notificationCenter.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: nil
        ) { [weak self] notification in
            self?.handleInterruption(notification)
        }

        let spatialToken = notificationCenter.addObserver(
            forName: AVAudioSession.spatialPlaybackCapabilitiesChangedNotification,
            object: session,
            queue: nil
        ) { [weak self] notification in
            self?.handleSpatialPlaybackCapabilitiesChanged(notification)
        }

        observerTokens = [routeToken, interruptionToken, spatialToken]
    }

    private func handleRouteChange(_ notification: Notification) {
        guard
            let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
        else {
            return
        }

        switch reason {
        case .oldDeviceUnavailable:
            eventsBroadcast.yield(.shouldPause)
            eventsBroadcast.yield(.spatialAudioEnabledChanged(currentSpatialAudioEnabledValue()))
        case .newDeviceAvailable:
            eventsBroadcast.yield(.routeAvailable)
            eventsBroadcast.yield(.spatialAudioEnabledChanged(currentSpatialAudioEnabledValue()))
        default:
            break
        }
    }

    private func handleSpatialPlaybackCapabilitiesChanged(_ notification: Notification) {
        let isEnabled = notification.userInfo?[AVAudioSessionSpatialAudioEnabledKey] as? Bool
            ?? currentSpatialAudioEnabledValue()
        eventsBroadcast.yield(.spatialAudioEnabledChanged(isEnabled))
    }

    private func currentSpatialAudioEnabledValue() -> Bool {
        session.currentRoute.outputs.contains { $0.isSpatialAudioEnabled }
    }

    private func handleInterruption(_ notification: Notification) {
        guard
            let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else {
            return
        }

        switch type {
        case .began:
            eventsBroadcast.yield(.interruptionBegan)
        case .ended:
            let optionValue = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionValue)
            let shouldResume = options.contains(.shouldResume)

            do {
                try session.setActive(true)
            } catch {
                eventsBroadcast.yield(.interruptionEnded(shouldResume: false))
                return
            }

            eventsBroadcast.yield(.interruptionEnded(shouldResume: shouldResume))
        @unknown default:
            break
        }
    }
}
#else
public final class AudioSessionManager: AudioSessionManaging, @unchecked Sendable {
    public var events: AsyncStream<AudioSessionEvent> {
        eventsBroadcast.stream()
    }

    private let eventsBroadcast = AsyncBroadcast<AudioSessionEvent>()

    public init() {
    }

    deinit {
        eventsBroadcast.finish()
    }

    public func configure() async throws {}
    public func activate() async throws {}
    public func deactivate() async throws {}
    public func setSupportsMultichannelContent(_ supports: Bool) async throws {}
    public func currentSpatialAudioEnabled() async -> Bool { false }
}
#endif
