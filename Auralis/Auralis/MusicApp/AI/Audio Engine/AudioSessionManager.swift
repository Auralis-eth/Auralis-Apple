import Foundation
import AVFoundation

public protocol AudioSessioning {
    func setCategory(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode, options: AVAudioSession.CategoryOptions) throws
    func setActive(_ active: Bool) throws
    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws
    var currentRoute: AVAudioSessionRouteDescription { get }
}

public struct DefaultAudioSession: AudioSessioning {
    private var session: AVAudioSession { AVAudioSession.sharedInstance() }
    public init() {}
    public func setCategory(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode, options: AVAudioSession.CategoryOptions) throws { try session.setCategory(category, mode: mode, options: options) }
    public func setActive(_ active: Bool) throws { try session.setActive(active) }
    public func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws { try session.setActive(active, options: options) }
    public var currentRoute: AVAudioSessionRouteDescription { session.currentRoute }
}

public enum AudioSessionEvent: Sendable {
    case interruptionBegan
    case interruptionEnded(shouldResume: Bool)
    case routeChanged(reason: AVAudioSession.RouteChangeReason, previous: AVAudioSessionRouteDescription?)
}

@MainActor
public final class AudioSessionManager {
    private let session: AudioSessioning
    private var continuation: AsyncStream<AudioSessionEvent>.Continuation?
    public private(set) lazy var events: AsyncStream<AudioSessionEvent> = {
        AsyncStream { continuation in
            self.continuation = continuation
        }
    }()

    public init(session: AudioSessioning = DefaultAudioSession()) {
        self.session = session
        NotificationCenter.default.addObserver(self, selector: #selector(handleInterruption(_:)), name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleRouteChange(_:)), name: AVAudioSession.routeChangeNotification, object: nil)
    }

    public func configureAndActivate() throws {
        try session.setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetoothA2DP])
        try session.setActive(true)
    }

    public func deactivate(notifyOthers: Bool = true) {
        try? session.setActive(false, options: notifyOthers ? [.notifyOthersOnDeactivation] : [])
    }

    @objc private func handleInterruption(_ n: Notification) {
        guard let info = n.userInfo,
              let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            continuation?.yield(.interruptionBegan)
        case .ended:
            let optRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optRaw)
            continuation?.yield(.interruptionEnded(shouldResume: options.contains(.shouldResume)))
        @unknown default: break
        }
    }

    @objc private func handleRouteChange(_ n: Notification) {
        let info = n.userInfo ?? [:]
        let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
        let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) ?? .unknown
        let previous = info[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription
        continuation?.yield(.routeChanged(reason: reason, previous: previous))
    }
}
