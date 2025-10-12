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

/// Manages an `AVAudioSession` and exposes audio session events as an `AsyncStream`.
///
/// Lifecycle
/// - The manager automatically removes observers and finishes its `events` stream on deallocation.
///   There is no explicit close method; tie the manager’s lifetime to the owner that consumes events.
/// - To stop observing, cancel the task that iterates `events` and release the manager (allow it to deinit).
/// - After deallocation, no further events are delivered.
@MainActor
public final class AudioSessionManager {
    private let session: AudioSessioning
    private var continuation: AsyncStream<AudioSessionEvent>.Continuation?
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?

    /// A non-lazy AsyncStream of audio session events.
    ///
    /// Initialization
    /// - Important: The stream and its continuation are created up-front using
    ///   `AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(64))`. This guarantees that
    ///   notifications posted before any consumer starts iterating are buffered rather
    ///   than dropped, and that the continuation exists before observers are registered,
    ///   avoiding race conditions and leaks.
    ///
    /// Single-consumer semantics
    /// - Note: `AsyncStream` is a single-consumer sequence. Iterating this stream from
    ///   multiple tasks concurrently is unsupported and can lead to undefined behavior
    ///   (missed or duplicated events). If you need to deliver events to multiple parts
    ///   of your app, use one of these patterns:
    ///   - Create a single Task that iterates `events` and fan-out to multiple listeners
    ///     via your own broadcaster (e.g., an `actor` that holds subscriber closures or
    ///     `AsyncStream` continuations).
    ///   - Bridge into an existing app-wide event bus (e.g., `NotificationCenter`) or
    ///     a Combine subject if your app already uses Combine. Avoid assuming `AsyncStream`
    ///     performs multicast on its own—it does not.
    ///
    /// Buffering policy and backpressure
    /// - This stream uses a bounded buffer: `.bufferingNewest(64)`. When producers outpace
    ///   the consumer, the oldest buffered events are dropped to keep the most recent 64.
    ///   Rationale:
    ///   - Audio session events represent state transitions where the latest state is most
    ///     relevant (e.g., the most recent route change).
    ///   - A bounded buffer prevents unbounded memory growth and potential OOM during event
    ///     floods or CPU spikes.
    /// - Guidance:
    ///   - Start consuming promptly after creating the manager (e.g., launch a dedicated
    ///     Task that iterates for the lifetime of the owner).
    ///   - Keep the consumer running; avoid long pauses in iteration.
    ///   - Coalesce or derive state in your handler (e.g., treat multiple route changes as
    ///     transitions toward a final observable state).
    ///   - If you must guarantee that every event is observed, consider an alternative
    ///     transport (e.g., your own queue with backpressure) or increase the buffer size
    ///     after evaluating memory trade-offs.
    ///   - For telemetry, consider instrumenting the consumer to detect gaps in expected
    ///     sequences (e.g., noticing a jump in derived state) and log potential drops.
    ///
    /// Example consumption
    /// ```swift
    /// var manager: AudioSessionManager? = AudioSessionManager()
    /// let eventsTask = Task {
    ///     guard let manager else { return }
    ///     for await event in manager.events {
    ///         // handle event
    ///     }
    /// }
    /// // ... later, during teardown
    /// eventsTask.cancel()
    /// manager = nil // allow deinit to perform cleanup
    /// ```
    public private(set) var events: AsyncStream<AudioSessionEvent>

    public init(session: AudioSessioning = DefaultAudioSession()) {
        self.session = session

        // Create the stream and continuation up-front to avoid races and dropped events.
        let (stream, continuation) = AsyncStream<AudioSessionEvent>.makeStream(bufferingPolicy: .bufferingNewest(64))
        self.events = stream
        self.continuation = continuation
        assert(self.continuation != nil, "AudioSessionManager invariant: continuation must be set before registering observers")

        // Ensure observers are removed when the stream terminates.
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in
                self?.removeObservers()
                self?.continuation = nil
            }
        }

        // Register observers only after the continuation exists so early events are buffered.
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] n in
            self?.handleInterruption(n)
        }

        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] n in
            self?.handleRouteChange(n)
        }
    }

    public func configureAndActivate() throws {
        try session.setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetoothA2DP])
        try session.setActive(true)
    }

    /// Deactivates the audio session.
    ///
    /// This method calls `AVAudioSession.setActive(false, options:)` and may throw
    /// errors originating from `AVAudioSession` (NSError domain `AVAudioSessionErrorDomain`).
    /// Common scenarios include:
    /// - The session is busy or mid-transition (e.g., during an interruption or route change).
    /// - Deactivation conflicts with system policy (e.g., other audio is currently taking priority).
    /// - The session was never activated, or activation state is out of sync.
    ///
    /// Error handling guidance:
    /// - Prefer `try?` when deactivation is best-effort (e.g., on teardown or backgrounding). Log failures.
    /// - Use `do/catch` when you need to react (e.g., retry later after an interruption ends).
    /// - Avoid `try!` because failures can occur legitimately at runtime.
    ///
    /// Parameters:
    /// - notifyOthers: When true, uses `.notifyOthersOnDeactivation` so other apps can resume audio.
    ///
    /// Discussion:
    /// Deactivation can fail transiently (e.g., `.isBusy`). If deactivation is important to UX,
    /// consider retrying after handling `AudioSessionEvent.interruptionEnded(shouldResume:)` or after
    /// route changes settle. If it’s non-critical, swallow with `try?` and continue.
    ///
    /// Examples:
    /// Best-effort deactivation (teardown/backgrounding):
    /// ```swift
    /// try? audioSessionManager.deactivate()
    /// ```
    /// React and retry when appropriate:
    /// ```swift
    /// do {
    ///     try audioSessionManager.deactivate()
    /// } catch {
    ///     // Log and optionally retry later, e.g., after an interruption ends
    /// }
    /// ```
    /// Avoid force-try in production:
    /// ```swift
    /// // try! audioSessionManager.deactivate() // Not recommended; failures can be legitimate.
    /// ```
    public func deactivate(notifyOthers: Bool = true) throws {
        try session.setActive(false, options: notifyOthers ? [.notifyOthersOnDeactivation] : [])
    }

    private func handleInterruption(_ n: Notification) {
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

    private func handleRouteChange(_ n: Notification) {
        let info = n.userInfo ?? [:]
        let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
        let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) ?? .unknown
        let previous = info[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription
        continuation?.yield(.routeChanged(reason: reason, previous: previous))
    }

    /// Removes all NotificationCenter observers registered by this manager.
    ///
    /// Safe to call multiple times. If observers are already removed, this is a no-op.
    /// After removal, both `interruptionObserver` and `routeChangeObserver` are set to nil.
    /// Ensures no dangling observers remain registered.
    private func removeObservers() {
        if let token = interruptionObserver {
            NotificationCenter.default.removeObserver(token)
            interruptionObserver = nil
        }
        if let token = routeChangeObserver {
            NotificationCenter.default.removeObserver(token)
            routeChangeObserver = nil
        }
    }

    @MainActor deinit {
        // Automatic lifecycle cleanup: remove observers and finish the stream on deallocation.
        // Tie the manager’s lifetime to the owner that consumes events.
        removeObservers()
        continuation?.finish()
        continuation = nil
    }
}
