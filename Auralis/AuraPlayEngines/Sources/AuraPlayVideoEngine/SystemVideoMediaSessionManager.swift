import Foundation

#if canImport(AVFAudio) && (os(iOS) || os(tvOS) || os(visionOS))
import AVFAudio
#if canImport(UIKit)
import UIKit
#endif

public final class SystemVideoMediaSessionManager: VideoMediaSessionManaging, @unchecked Sendable {
    public let events: AsyncStream<VideoMediaSessionEvent>

    private let session: AVAudioSession
    private let notificationCenter: NotificationCenter
    private let continuation: AsyncStream<VideoMediaSessionEvent>.Continuation
    private var interruptionToken: NSObjectProtocol?
    private var backgroundToken: NSObjectProtocol?
    private var terminationToken: NSObjectProtocol?

    public init(session: AVAudioSession = .sharedInstance(), notificationCenter: NotificationCenter = .default) {
        self.session = session
        self.notificationCenter = notificationCenter

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

        #if canImport(UIKit)
        backgroundToken = notificationCenter.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [continuation] _ in
            continuation.yield(.enteredBackground)
        }

        terminationToken = notificationCenter.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [continuation] _ in
            continuation.yield(.willStop)
        }
        #endif
    }

    deinit {
        if let interruptionToken {
            notificationCenter.removeObserver(interruptionToken)
        }
        if let backgroundToken {
            notificationCenter.removeObserver(backgroundToken)
        }
        if let terminationToken {
            notificationCenter.removeObserver(terminationToken)
        }
        continuation.finish()
    }

    public func configureForPlayback() async throws {
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

    public func configureForPlayback() async throws {}
}
#endif
