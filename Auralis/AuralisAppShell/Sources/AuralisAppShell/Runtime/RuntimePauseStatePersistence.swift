import Foundation
import OSLog

/// The operator pause state, in the form that survives relaunch.
///
/// `reason` is carried alongside the flag because the paused-state surface shows *why* activity is
/// paused, and a rehydrated pause with no reason would present the kill switch as having been thrown
/// by nobody.
public struct RuntimePauseState: Codable, Equatable, Sendable {
    public var isPaused: Bool
    public var reason: String?

    public init(isPaused: Bool, reason: String? = nil) {
        self.isPaused = isPaused
        self.reason = reason
    }
}

/// Durable backing for the global kill switch.
///
/// ``RuntimeHost/isPaused`` was process memory only, which made the kill switch weaker than it reads.
/// Two consequences, both reachable:
///
/// - A pause did not survive relaunch. `isPaused` starts `false` on every host and nothing read the
///   `runtime.paused` receipt back, so terminating the app was enough to resume operator activity —
///   including a background relaunch the person never saw.
/// - It did not even hold within a live process. `RuntimeBackgroundScheduler.runInBackground()` builds
///   its own `ModelContainer`, and `RuntimeAssembly` keys its host cache on container identity, so the
///   background refresh always got a *second* `RuntimeHost` with its own open ``PauseGate``. A person
///   who paused from Mission Control still had due routines and rituals firing underneath them.
///
/// Only an operator pause is stored. The two pauses the runtime derives for itself each launch are
/// deliberately excluded: the storage-unavailable pause is re-derived from whether the container
/// opens, and the governance-integrity pause from whether registration succeeds — persisting either
/// would report a fault on a launch that did not have it. See ``RuntimeHost/PauseOrigin``.
public protocol RuntimePauseStateStoring: Sendable {
    func load() async -> RuntimePauseState?
    func save(_ state: RuntimePauseState) async
}

/// `UserDefaults`-backed pause state, deliberately *not* in the SwiftData runtime container.
///
/// The kill switch has to be readable when that container is the thing that failed:
/// ``RuntimeHost/persistent(_:)`` returns a paused host precisely because storage is unavailable, and
/// a pause store living inside the unavailable store could not be consulted. Same reasoning that puts
/// the coordination stores in `UserDefaults` (see `SocialCorePersistence`).
public actor UserDefaultsRuntimePauseStateStore: RuntimePauseStateStoring {
    public static let defaultKey = "com.auralis.runtime.pauseState.v1"

    private static let logger = Logger(subsystem: "com.auralis.runtime", category: "pause-state")

    private let defaults: UserDefaults
    private let key: String

    public init(
        defaults: UserDefaults = .standard,
        key: String = UserDefaultsRuntimePauseStateStore.defaultKey
    ) {
        self.defaults = defaults
        self.key = key
    }

    public func load() async -> RuntimePauseState? {
        guard let data = defaults.data(forKey: key) else { return nil }
        do {
            return try JSONDecoder().decode(RuntimePauseState.self, from: data)
        } catch {
            // Fails *closed* on an unreadable payload, unlike the coordination stores that reset to
            // empty: this is a safety control, and "we cannot tell whether the operator paused
            // activity" has to resolve to paused. The reason names the situation so the paused-state
            // surface is not blank.
            Self.logger.error(
                """
                Unreadable runtime pause state; treating the runtime as paused because a kill switch \
                whose state cannot be read must not default to open: \
                \(error.localizedDescription, privacy: .public)
                """
            )
            return RuntimePauseState(
                isPaused: true,
                reason: "The saved pause state could not be read, so operator activity is paused. Resume from Mission Control to clear this."
            )
        }
    }

    public func save(_ state: RuntimePauseState) async {
        do {
            defaults.set(try JSONEncoder().encode(state), forKey: key)
        } catch {
            // Non-throwing by protocol, so logging is the only channel. A dropped write means the
            // pause holds for this process but not the next one.
            Self.logger.error(
                """
                Failed to persist runtime pause state (isPaused: \(state.isPaused, privacy: .public)); \
                the kill switch will not survive relaunch: \(error.localizedDescription, privacy: .public)
                """
            )
        }
    }
}
