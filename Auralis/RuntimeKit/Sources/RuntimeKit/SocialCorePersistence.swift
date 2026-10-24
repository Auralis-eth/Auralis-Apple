import Foundation
import OSLog
import SocialCore

/// `UserDefaults`-backed persistence for the human-coordination stores (P1-SOCIAL-101/102), so shared
/// sessions, ritual enabled-state, and last-run timestamps survive relaunch. These live in RuntimeKit
/// rather than `SocialCore` to keep that package a pure, storage-free domain leaf. Each payload is
/// JSON-encoded under one key; a corrupt payload resets to empty rather than crashing.

/// Where a failed encode is reported.
///
/// `SocialEventLogPersisting.save(_:)` and its siblings are non-throwing, so a store that cannot
/// encode its snapshot has no channel to tell its caller — the mutation returns as if it had been
/// written and the next launch silently reads the previous snapshot. That is the one outcome
/// `RuntimeHost.persistent(...)` singles out as unacceptable for the *outbound relay queue*: work a
/// person asked to publish would sit unsent with nothing anywhere saying so.
///
/// Logging is the only reporting channel these signatures leave. It is the same posture
/// ``ReceiptStoreSink`` takes for its artifact backlink: when a failure genuinely cannot be
/// propagated, record it rather than discard it.
private let socialPersistenceLogger = Logger(
    subsystem: "com.auralis.runtime",
    category: "social-persistence"
)

/// Observable health for the non-throwing SocialCore persistence seams.
public enum SocialPersistenceHealth: Equatable, Sendable {
    case healthy
    case quarantined(reason: String)
}

/// The recovery seam for a quarantined coordination store.
///
/// Quarantine is a deliberate refusal: a store that could not decode its payload will not overwrite
/// it, because the bytes may be a forward-compatible snapshot from a newer build rather than
/// garbage. But the refusal has to be *escapable*, and on its own it is not. ``quarantine(_:error:)``
/// copies the payload aside and leaves the original key in place, so the next launch decodes the
/// same bytes and quarantines again — permanently, with every `save` refused for the life of the
/// installation.
///
/// Three consequences, all reachable and none of them visible without this protocol:
///
/// - Ritual enabled-state stops persisting. `RitualStore.ensureHydrated` derives `isEnabled` from
///   the loaded state, so an empty fallback brings every ritual up disabled; turning one on works
///   in-process and is gone on relaunch.
/// - ``RuntimeHost/resetAllHistory()`` silently fails for the coordination stores. `reset()` writes
///   an empty snapshot, which is a `save` like any other, so the privacy reset leaves the payload on
///   disk *and* the `.quarantine` copy beside it — carrying session titles and the CAIP-10 accounts
///   of everyone who took part, which is the data that reset exists to erase.
/// - The pending outbound relay queue never becomes durable.
///
/// Naming health and discard at a protocol lets ``RuntimeHost`` report all three on one observable
/// banner and clear them together, so the only way out is a person's explicit decision rather than
/// an implicit overwrite.
/// `AnyObject` because ``SharedCoordinationStores`` keys its one-store-per-backing memo on the
/// backing's *identity*. A value-type backing would get a fresh identity on every box, so it would
/// silently key a fresh store per call — reintroducing the two-stores-over-one-key clobber that memo
/// exists to prevent (F-23). All three conformers are already actors; this makes the requirement
/// enforced rather than assumed.
public protocol SocialPersistenceQuarantining: AnyObject, Sendable {
    /// What this store holds, named for the recovery banner.
    var quarantineDisplayName: String { get }
    func persistenceHealth() async -> SocialPersistenceHealth
    /// Discards the unreadable payload *and* the quarantined copy, returning the store to healthy.
    func discardQuarantinedPayload() async
}

/// Durable backing for shared sessions and their collaborative approvals.
/// Actor isolation serializes quarantine state and writes around the thread-safe `UserDefaults` reference.
public actor UserDefaultsSharedSessionPersistence: SharedSessionPersisting, SocialPersistenceQuarantining {
    public static let defaultKey = "social.sharedSessions.v1"
    public static let quarantineSuffix = ".quarantine"

    public nonisolated var quarantineDisplayName: String { "Shared sessions" }

    private let defaults: UserDefaults
    private let key: String
    private var health: SocialPersistenceHealth = .healthy

    public init(defaults: UserDefaults = .standard, key: String = UserDefaultsSharedSessionPersistence.defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    public func load() async -> [SharedSession] {
        guard let data = defaults.data(forKey: key) else { return [] }
        do {
            return try JSONDecoder().decode([SharedSession].self, from: data)
        } catch {
            quarantine(data, error: error)
            return []
        }
    }

    public func save(_ sessions: [SharedSession]) async {
        guard case .healthy = health else {
            socialPersistenceLogger.error("Refused to overwrite quarantined shared-session persistence.")
            return
        }
        do {
            defaults.set(try JSONEncoder().encode(sessions), forKey: key)
        } catch {
            socialPersistenceLogger.error(
                """
                Failed to persist \(sessions.count, privacy: .public) shared session(s); \
                this installation will read the previous snapshot on relaunch: \
                \(error.localizedDescription, privacy: .public)
                """
            )
        }
    }

    public func persistenceHealth() -> SocialPersistenceHealth { health }

    /// Explicitly discards an unreadable payload so a caller can start fresh after informing the user.
    ///
    /// A no-op on a healthy store, and that guard is load-bearing rather than defensive. The three
    /// backings quarantine *independently*, but the recovery is one button in Mission Control wired
    /// to ``RuntimeHost/discardQuarantinedCoordinationState()``, which calls this on every
    /// registered persistence. Without the guard, discarding one unreadable ritual payload also
    /// deleted the healthy shared sessions and the healthy social event log — including the pending
    /// outbound relay queue, i.e. work a person had asked to publish — while the confirmation
    /// dialog promised it would only remove what this version cannot read.
    public func discardQuarantinedPayload() {
        guard case .quarantined = health else { return }
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: key + Self.quarantineSuffix)
        health = .healthy
    }

    /// Idempotent: `load()` deliberately reports what is actually on disk rather than short-circuiting
    /// on `health`, so an already-quarantined store re-decodes and lands here again — once per launch
    /// at minimum, since `RuntimeHost.refreshCoordinationPersistenceHealth()` forces a load. Without
    /// this guard each of those rewrote the same bytes to the same key and logged the same fault, on a
    /// path `bootstrap()` awaits. The first quarantine is the one that matters; the rest are noise.
    private func quarantine(_ data: Data, error: Error) {
        guard case .healthy = health else { return }
        defaults.set(data, forKey: key + Self.quarantineSuffix)
        health = .quarantined(reason: error.localizedDescription)
        socialPersistenceLogger.error("Quarantined unreadable shared-session persistence: \(error.localizedDescription, privacy: .public)")
    }
}

/// Durable backing for ritual enabled-state, custom rituals, and last-run timestamps.
/// Actor isolation serializes quarantine state and writes around the thread-safe `UserDefaults` reference.
public actor UserDefaultsRitualStatePersistence: RitualStatePersisting, SocialPersistenceQuarantining {
    public static let defaultKey = "social.ritualState.v1"
    public static let quarantineSuffix = ".quarantine"

    public nonisolated var quarantineDisplayName: String { "Rituals" }

    private let defaults: UserDefaults
    private let key: String
    private var health: SocialPersistenceHealth = .healthy

    public init(defaults: UserDefaults = .standard, key: String = UserDefaultsRitualStatePersistence.defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    public func load() async -> RitualPersistedState {
        guard let data = defaults.data(forKey: key) else { return RitualPersistedState() }
        do {
            return try JSONDecoder().decode(RitualPersistedState.self, from: data)
        } catch {
            quarantine(data, error: error)
            return RitualPersistedState()
        }
    }

    public func save(_ state: RitualPersistedState) async {
        guard case .healthy = health else {
            socialPersistenceLogger.error("Refused to overwrite quarantined ritual persistence.")
            return
        }
        do {
            defaults.set(try JSONEncoder().encode(state), forKey: key)
        } catch {
            socialPersistenceLogger.error(
                """
                Failed to persist ritual state; enabled toggles and last-run times will read as \
                the previous snapshot on relaunch, so a ritual may re-fire: \
                \(error.localizedDescription, privacy: .public)
                """
            )
        }
    }

    public func persistenceHealth() -> SocialPersistenceHealth { health }

    /// A no-op on a healthy store; see the note on
    /// ``UserDefaultsSharedSessionPersistence/discardQuarantinedPayload()`` for why that guard is
    /// load-bearing — one Mission Control button discards all three backings at once.
    public func discardQuarantinedPayload() {
        guard case .quarantined = health else { return }
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: key + Self.quarantineSuffix)
        health = .healthy
    }

    /// Idempotent: `load()` deliberately reports what is actually on disk rather than short-circuiting
    /// on `health`, so an already-quarantined store re-decodes and lands here again — once per launch
    /// at minimum, since `RuntimeHost.refreshCoordinationPersistenceHealth()` forces a load. Without
    /// this guard each of those rewrote the same bytes to the same key and logged the same fault, on a
    /// path `bootstrap()` awaits. The first quarantine is the one that matters; the rest are noise.
    private func quarantine(_ data: Data, error: Error) {
        guard case .healthy = health else { return }
        defaults.set(data, forKey: key + Self.quarantineSuffix)
        health = .quarantined(reason: error.localizedDescription)
        socialPersistenceLogger.error("Quarantined unreadable ritual persistence: \(error.localizedDescription, privacy: .public)")
    }
}

/// Durable backing for Social v1 sync event logs, invites, replay cursors, and the pending outbound queue.
/// Actor isolation serializes quarantine state and writes around the thread-safe `UserDefaults` reference.
public actor UserDefaultsSocialEventLogPersistence: SocialEventLogPersisting, SocialPersistenceQuarantining {
    public static let defaultKey = "social.eventLog.v1"
    public static let quarantineSuffix = ".quarantine"

    public nonisolated var quarantineDisplayName: String { "Social event log" }

    private let defaults: UserDefaults
    private let key: String
    private var health: SocialPersistenceHealth = .healthy

    public init(defaults: UserDefaults = .standard, key: String = UserDefaultsSocialEventLogPersistence.defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    public func load() async -> SocialEventLogSnapshot {
        guard let data = defaults.data(forKey: key) else { return SocialEventLogSnapshot() }
        do {
            return try JSONDecoder().decode(SocialEventLogSnapshot.self, from: data)
        } catch {
            quarantine(data, error: error)
            return SocialEventLogSnapshot()
        }
    }

    public func save(_ snapshot: SocialEventLogSnapshot) async {
        guard case .healthy = health else {
            socialPersistenceLogger.error("Refused to overwrite quarantined social event-log persistence.")
            return
        }
        do {
            defaults.set(try JSONEncoder().encode(snapshot), forKey: key)
        } catch {
            // The most consequential of the three: this snapshot carries the pending outbound relay
            // queue, so a dropped write means events a person asked to publish are neither sent nor
            // recoverable on the next launch.
            socialPersistenceLogger.error(
                """
                Failed to persist the social event log; the pending outbound relay queue was not \
                written and will read as the previous snapshot on relaunch: \
                \(error.localizedDescription, privacy: .public)
                """
            )
        }
    }

    public func persistenceHealth() -> SocialPersistenceHealth { health }

    /// A no-op on a healthy store; see the note on
    /// ``UserDefaultsSharedSessionPersistence/discardQuarantinedPayload()`` for why that guard is
    /// load-bearing — one Mission Control button discards all three backings at once.
    public func discardQuarantinedPayload() {
        guard case .quarantined = health else { return }
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: key + Self.quarantineSuffix)
        health = .healthy
    }

    /// Idempotent: `load()` deliberately reports what is actually on disk rather than short-circuiting
    /// on `health`, so an already-quarantined store re-decodes and lands here again — once per launch
    /// at minimum, since `RuntimeHost.refreshCoordinationPersistenceHealth()` forces a load. Without
    /// this guard each of those rewrote the same bytes to the same key and logged the same fault, on a
    /// path `bootstrap()` awaits. The first quarantine is the one that matters; the rest are noise.
    private func quarantine(_ data: Data, error: Error) {
        guard case .healthy = health else { return }
        defaults.set(data, forKey: key + Self.quarantineSuffix)
        health = .quarantined(reason: error.localizedDescription)
        socialPersistenceLogger.error("Quarantined unreadable social event-log persistence: \(error.localizedDescription, privacy: .public)")
    }
}
