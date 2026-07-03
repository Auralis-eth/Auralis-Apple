import Foundation

#if canImport(AVFAudio) && (os(iOS) || os(tvOS) || os(visionOS))
import AVFAudio

public final class SystemVideoMediaSessionManager: VideoMediaSessionManaging, @unchecked Sendable {
    public let events: AsyncStream<VideoMediaSessionEvent>

    private let session: AVAudioSession
    private let continuation: AsyncStream<VideoMediaSessionEvent>.Continuation
    private var interruptionToken: NSObjectProtocol?

    public init(session: AVAudioSession = .sharedInstance(), notificationCenter: NotificationCenter = .default) {
        self.session = session

        var continuation: AsyncStream<VideoMediaSessionEvent>.Continuation!
        self.events = AsyncStream { continuation = $0 }
        self.continuation = continuation

        interruptionToken = notificationCenter.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { [continuation] notification in
            Self.handleInterruption(notification, continuation: continuation)
        }
    }

    deinit {
        if let interruptionToken {
            NotificationCenter.default.removeObserver(interruptionToken)
        }
        continuation.finish()
    }

    public func configureForVideoPlayback() async throws {
        try session.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay, .allowBluetoothA2DP])
        try session.setActive(true)
    }

    private static func handleInterruption(
        _ notification: Notification,
        continuation: AsyncStream<VideoMediaSessionEvent>.Continuation
    ) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else {
            return
        }

        switch type {
        case .began:
            continuation.yield(.shouldPause)
        case .ended:
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
            if options.contains(.shouldResume) {
                continuation.yield(.interruptionEndedShouldResume)
            }
        @unknown default:
            break
        }
    }
}
#else
public final class SystemVideoMediaSessionManager: VideoMediaSessionManaging, @unchecked Sendable {
    public let events: AsyncStream<VideoMediaSessionEvent>
    private let continuation: AsyncStream<VideoMediaSessionEvent>.Continuation

    public init() {
        var continuation: AsyncStream<VideoMediaSessionEvent>.Continuation!
        self.events = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    deinit {
        continuation.finish()
    }

    public func configureForVideoPlayback() async throws {}
}
#endif
