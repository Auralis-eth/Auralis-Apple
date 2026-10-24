import Foundation
import PlaybookCore
import RuntimeCore

/// P1-SOCIAL-102 — Ritual / Routine Engine.
///
/// A ritual is a *named, reusable bundle of routines* — the point where Auralis becomes experiential
/// rather than transactional ("morning review", "sesh prep", "weekly reflection"). It composes
/// existing `Playbook`s under one intent and one trigger; it does not execute anything itself. Running
/// stays in `SchedulingEngine`, so all the existing governance (authority envelope, receipts,
/// performance) applies unchanged. This is deliberately bounded and read-mostly (Phase 1 scope).

/// The built-in ritual archetypes. User-defined rituals use ``RitualKind/custom``.
public enum RitualKind: String, Equatable, Sendable, Codable, CaseIterable {
    case morningReview
    case seshPrep
    case listeningFlow
    case weeklyReflection
    case communityGathering
    case collaborativeListening
    case custom

    public var displayName: String {
        switch self {
        case .morningReview: return "Morning Review"
        case .seshPrep: return "Sesh Prep"
        case .listeningFlow: return "Listening Flow"
        case .weeklyReflection: return "Weekly Reflection"
        case .communityGathering: return "Community Gathering"
        case .collaborativeListening: return "Collaborative Listening"
        case .custom: return "Custom Ritual"
        }
    }

    /// Whether the ritual is inherently multi-participant (drives a shared session by default).
    public var isCollaborative: Bool {
        switch self {
        case .communityGathering, .collaborativeListening: return true
        default: return false
        }
    }
}

public enum RitualCalendarFrequency: String, Equatable, Sendable, Codable {
    case daily
    case weekly
}

/// Calendar semantics for human routines. `weekday` follows `Calendar` (1 = Sunday...7 = Saturday)
/// and is required for weekly schedules. The time-zone identifier is persisted so DST transitions are
/// calculated by Foundation rather than approximated with elapsed seconds.
public struct RitualCalendarSchedule: Equatable, Sendable, Codable {
    public let frequency: RitualCalendarFrequency
    public let hour: Int
    public let minute: Int
    public let weekday: Int?
    public let timeZoneIdentifier: String

    public init(
        frequency: RitualCalendarFrequency,
        hour: Int,
        minute: Int = 0,
        weekday: Int? = nil,
        timeZoneIdentifier: String = TimeZone.autoupdatingCurrent.identifier
    ) {
        self.frequency = frequency
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
        self.weekday = weekday.map { min(max($0, 1), 7) }
        self.timeZoneIdentifier = TimeZone(identifier: timeZoneIdentifier)?.identifier
            ?? TimeZone.autoupdatingCurrent.identifier
    }

    private enum CodingKeys: String, CodingKey {
        case frequency, hour, minute, weekday, timeZoneIdentifier
    }

    /// Decodes through ``init(frequency:hour:minute:weekday:timeZoneIdentifier:)`` so its clamps run.
    ///
    /// The conformance was synthesized, which assigns the stored properties directly and bypasses
    /// every bound above — the same decode-boundary hole `SocialEvent.clampedForStorage` exists to
    /// close for the wire types, here on the persistence path. A `RitualDefinition` is reloaded from
    /// ``RitualPersistedState/customRituals`` on every launch, so a payload carrying `hour: 99` or
    /// `weekday: 0` survived a relaunch intact and then made `RitualEngine.mostRecentOccurrence`
    /// ask `Calendar` for a date component that can never match. The ritual silently never became
    /// due again, with nothing surfaced anywhere: `isDue` reads a `nil` occurrence as "not due".
    ///
    /// Clamping on the way in restores the documented contract — hour `0...23`, minute `0...59`,
    /// weekday `1...7` — rather than leaving a schedule that is unsatisfiable by construction. An
    /// unknown `timeZoneIdentifier` already falls back to the current zone through the same
    /// initializer.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            frequency: try container.decode(RitualCalendarFrequency.self, forKey: .frequency),
            hour: try container.decode(Int.self, forKey: .hour),
            minute: try container.decodeIfPresent(Int.self, forKey: .minute) ?? 0,
            weekday: try container.decodeIfPresent(Int.self, forKey: .weekday),
            timeZoneIdentifier: try container.decodeIfPresent(String.self, forKey: .timeZoneIdentifier)
                ?? TimeZone.autoupdatingCurrent.identifier
        )
    }
}

/// Stable identity for one scheduled calendar occurrence. Persisting completed occurrences prevents a
/// duplicate background-task delivery after relaunch from repeating work that already reached a terminal
/// successful or partially successful result.
public struct RitualOccurrenceID: Hashable, Sendable, Codable {
    public let ritualID: String
    public let scheduledAt: Date

    public init(ritualID: String, scheduledAt: Date) {
        self.ritualID = ritualID
        self.scheduledAt = scheduledAt
    }
}

/// A named ritual: an intent plus the ordered playbooks it runs under one trigger.
public struct RitualDefinition: Identifiable, Equatable, Sendable, Codable {
    public let id: String
    public let kind: RitualKind
    public let name: String
    public let summary: String
    public let trigger: PlaybookTrigger
    public let calendarSchedule: RitualCalendarSchedule?
    /// The playbooks this ritual runs, in order. IDs resolve against the app's `PlaybookStore`.
    public let playbookIDs: [String]
    public let createdBy: ActorRef
    public var isEnabled: Bool

    public init(
        id: String,
        kind: RitualKind,
        name: String,
        summary: String,
        trigger: PlaybookTrigger,
        calendarSchedule: RitualCalendarSchedule? = nil,
        playbookIDs: [String],
        createdBy: ActorRef = .system,
        isEnabled: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.summary = summary
        self.trigger = trigger
        self.calendarSchedule = calendarSchedule
        self.playbookIDs = playbookIDs
        self.createdBy = createdBy
        self.isEnabled = isEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, name, summary, trigger, calendarSchedule, playbookIDs, createdBy, isEnabled
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = try container.decode(RitualKind.self, forKey: .kind)
        name = try container.decode(String.self, forKey: .name)
        summary = try container.decode(String.self, forKey: .summary)
        trigger = try container.decode(PlaybookTrigger.self, forKey: .trigger)
        calendarSchedule = try container.decodeIfPresent(RitualCalendarSchedule.self, forKey: .calendarSchedule)
        playbookIDs = try container.decode([String].self, forKey: .playbookIDs)
        createdBy = try container.decodeIfPresent(ActorRef.self, forKey: .createdBy) ?? .system
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
    }
}

/// The built-in ritual catalog. Playbook IDs are conventional; a ritual runs whichever of them the
/// `PlaybookStore` actually has installed, so an incomplete catalog degrades gracefully.
public enum RitualCatalog {
    public static let all: [RitualDefinition] = [
        RitualDefinition(
            id: "ritual.morning-review",
            kind: .morningReview,
            name: RitualKind.morningReview.displayName,
            summary: "Start-of-day brief: overnight changes, pending approvals, and a research brief.",
            trigger: .schedule(intervalSeconds: 86_400),
            calendarSchedule: RitualCalendarSchedule(frequency: .daily, hour: 8),
            playbookIDs: ["research.brief", "onchain.watch"]
        ),
        RitualDefinition(
            id: "ritual.sesh-prep",
            kind: .seshPrep,
            name: RitualKind.seshPrep.displayName,
            summary: "Prepare a listening session from local preferences and recent activity.",
            trigger: .manual,
            playbookIDs: ["music.autoOrganize"]
        ),
        RitualDefinition(
            id: "ritual.listening-flow",
            kind: .listeningFlow,
            name: RitualKind.listeningFlow.displayName,
            summary: "A continuous listening flow that adapts to the current context.",
            trigger: .manual,
            playbookIDs: ["music.autoOrganize"]
        ),
        RitualDefinition(
            id: "ritual.weekly-reflection",
            kind: .weeklyReflection,
            name: RitualKind.weeklyReflection.displayName,
            summary: "End-of-week reflection artifact summarizing the week's receipts and outcomes.",
            trigger: .schedule(intervalSeconds: 604_800),
            calendarSchedule: RitualCalendarSchedule(frequency: .weekly, hour: 17, weekday: 6),
            playbookIDs: ["research.brief", "artifact.maintenance"]
        ),
        RitualDefinition(
            id: "ritual.community-gathering",
            kind: .communityGathering,
            name: RitualKind.communityGathering.displayName,
            summary: "A shared gathering: collaborative approvals over a shared session context.",
            trigger: .manual,
            playbookIDs: ["community.gathering"]
        ),
        RitualDefinition(
            id: "ritual.collaborative-listening",
            kind: .collaborativeListening,
            name: RitualKind.collaborativeListening.displayName,
            summary: "A shared listening flow with an AuraPlay organization plan and collaborative session.",
            trigger: .manual,
            playbookIDs: ["music.autoOrganize"]
        )
    ]
}

/// Tracks ritual definitions, their enabled state, and each ritual's last-run time. Mission Control's
/// ritual surface observes this. Backed by an injected ``RitualStatePersisting`` so enabled toggles,
/// user-defined rituals, and last-run timestamps survive relaunch (the default is ephemeral).
public actor RitualStore {
    private var rituals: [String: RitualDefinition]
    private var lastRuns: [String: Date] = [:]
    private var completedOccurrenceIDs: Set<RitualOccurrenceID> = []
    private let persistence: any RitualStatePersisting
    private let maxCompletedOccurrenceCount: Int
    private var hydrated = false
    private var hydration: Task<Void, Never>?
    private var lastWrite: Task<Void, Never>?
    private var runningRitualIDs: Set<String> = []

    public init(
        seed: [RitualDefinition] = RitualCatalog.all,
        persistence: any RitualStatePersisting = EphemeralRitualStatePersistence(),
        maxCompletedOccurrenceCount: Int = 512
    ) {
        // `uniquingKeysWith:` rather than `uniqueKeysWithValues:`, for the reason spelled out on
        // `SocialEventLogStore.pendingOutbound()`: the latter *traps* on a duplicate key, and `seed`
        // is a public parameter. Uniqueness held only by the invariant that `RitualCatalog.all` has
        // distinct ids, so any caller supplying a catalog of its own — a test fixture, or a future
        // merge of built-ins with user-authored rituals — turned a data problem into a crash at
        // construction. Last one wins, matching `upsert(_:)`.
        rituals = Dictionary(seed.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        self.persistence = persistence
        self.maxCompletedOccurrenceCount = max(1, maxCompletedOccurrenceCount)
    }

    /// Overlays persisted user intent onto the seeded catalog on first access. The catalog stays the
    /// authoritative source of ritual *structure*; persistence only supplies enabled-state, last-run
    /// timestamps, and any custom rituals.
    ///
    /// Single-flighted through ``hydration`` rather than guarded by a flag set before the load. This
    /// actor is reentrant across the `await` on `persistence.load()`, and `hydrated` used to be set
    /// *before* that suspension — so every caller arriving during the load skipped hydration and ran
    /// against the seeded, pre-load state. `setEnabled`/`recordRun` then persisted a snapshot whose
    /// `lastRuns` was empty (losing `lastRuns` makes an already-completed ritual run again, with a
    /// duplicate notification), and the load's write-back afterwards discarded their in-memory change.
    /// Joiners await the task that performs the *apply*, so "the task completed" and "the store is
    /// hydrated" are the same event.
    private func ensureHydrated() async {
        if hydrated { return }
        if let hydration { return await hydration.value }

        let task = Task { await self.hydrate() }
        hydration = task
        await task.value
        hydration = nil
    }

    /// Loads persisted state and applies it. Runs on this actor inside the single-flight task, so
    /// `hydrated` is only true once the applied state is visible.
    private func hydrate() async {
        let state = await persistence.load()
        for custom in state.customRituals where rituals[custom.id] == nil {
            rituals[custom.id] = custom
        }
        for (id, var ritual) in rituals {
            ritual.isEnabled = state.enabledIDs.contains(id)
            rituals[id] = ritual
        }
        lastRuns = state.lastRuns
        completedOccurrenceIDs = state.completedOccurrenceIDs
        trimCompletedOccurrences()
        hydrated = true
    }

    /// Writes the whole ritual payload through to `persistence`, chained behind any write already in
    /// flight — the same ordering guarantee as `SocialEventLogStore.commit(_:)`, for the same reason.
    ///
    /// Hydration makes the read-modify-write atomic on this actor, but every save still replaces the
    /// *entire* payload, so correctness also depends on the saves landing in the order they were
    /// committed in memory. Two concurrent writes snapshot the payload before and after a change; if
    /// the earlier, slower save completes last the change is gone on disk while memory still shows
    /// it. The lost field decides behaviour: a dropped `completedOccurrenceIDs` entry means
    /// `beginRun` no longer refuses an occurrence that was already handled, so a scheduled ritual
    /// re-fires after relaunch and notifies a second time, and a dropped `lastRuns` entry makes an
    /// already-completed ritual due again.
    private func persist() async {
        let enabledIDs = Set(rituals.values.filter(\.isEnabled).map(\.id))
        let custom = rituals.values.filter { $0.kind == .custom }.sorted { $0.id < $1.id }
        let value = RitualPersistedState(
            enabledIDs: enabledIDs,
            customRituals: custom,
            lastRuns: lastRuns,
            completedOccurrenceIDs: completedOccurrenceIDs
        )
        let previous = lastWrite
        let write = Task { [persistence] in
            await previous?.value
            await persistence.save(value)
        }
        lastWrite = write
        await write.value
        // Only the newest write clears the chain, so a burst collapses to one link rather than
        // retaining every task that ever ran.
        if lastWrite == write { lastWrite = nil }
    }

    public func all() async -> [RitualDefinition] {
        await ensureHydrated()
        return rituals.values.sorted { $0.name < $1.name }
    }

    public func ritual(id: String) async -> RitualDefinition? {
        await ensureHydrated()
        return rituals[id]
    }

    public func enabled() async -> [RitualDefinition] {
        await all().filter(\.isEnabled)
    }

    public func upsert(_ ritual: RitualDefinition) async {
        await ensureHydrated()
        rituals[ritual.id] = ritual
        await persist()
    }

    public func setEnabled(id: String, _ enabled: Bool) async {
        await ensureHydrated()
        guard var ritual = rituals[id] else { return }
        ritual.isEnabled = enabled
        rituals[id] = ritual
        await persist()
    }

    /// The last time the given ritual ran, or `nil` if it has never run. Drives scheduled due-checks.
    public func lastRun(id: String) async -> Date? {
        await ensureHydrated()
        return lastRuns[id]
    }

    /// Records that a ritual ran, so scheduled triggers can compute their next due time.
    public func recordRun(id: String, at date: Date = .now) async {
        await ensureHydrated()
        lastRuns[id] = date
        await persist()
    }

    /// Atomically claims a ritual occurrence. This prevents a background refresh and a foreground
    /// "Run now" action from executing the same ritual at the same time.
    public func beginRun(id: String) async -> Bool {
        await beginRun(id: id, occurrenceID: nil)
    }

    /// Atomically claims a run and rejects an occurrence already completed by an earlier process.
    public func beginRun(id: String, occurrenceID: RitualOccurrenceID?) async -> Bool {
        await ensureHydrated()
        if let occurrenceID, completedOccurrenceIDs.contains(occurrenceID) {
            return false
        }
        guard rituals[id] != nil, runningRitualIDs.insert(id).inserted else { return false }
        return true
    }

    /// Releases a claim acquired by ``beginRun(id:)``. Claims are intentionally process-local; after
    /// termination there is no in-flight task left to protect.
    public func finishRun(id: String) {
        runningRitualIDs.remove(id)
    }

    /// Releases a run claim and durably records a successfully handled scheduled occurrence.
    public func finishRun(
        id: String,
        occurrenceID: RitualOccurrenceID?,
        completed: Bool
    ) async {
        // Hydrate before the `persist()` below: writing from an un-hydrated store would rewrite the
        // whole payload from the seeded catalog, erasing persisted `lastRuns`, enabled toggles, and
        // custom rituals. `beginRun` hydrates, so in the normal claim/release flow this is already
        // satisfied; it is the persisting write, not the caller ordering, that has to be safe.
        await ensureHydrated()
        runningRitualIDs.remove(id)
        guard completed, let occurrenceID else { return }
        completedOccurrenceIDs.insert(occurrenceID)
        trimCompletedOccurrences()
        await persist()
    }

    private func trimCompletedOccurrences() {
        guard completedOccurrenceIDs.count > maxCompletedOccurrenceCount else { return }
        completedOccurrenceIDs = Set(
            completedOccurrenceIDs
                .sorted { $0.scheduledAt > $1.scheduledAt }
                .prefix(maxCompletedOccurrenceCount)
        )
    }

    /// Erases the record of what the rituals have *done*, for the privacy reset (MC-Device-012):
    /// last-run timestamps, handled scheduled occurrences, and any in-process run claims.
    ///
    /// Ritual *structure* is deliberately untouched — the catalog, each ritual's enabled state, and
    /// user-authored custom rituals are configuration, not a record of activity, exactly as installed
    /// playbooks are left alone by ``RuntimeHost/resetAllHistory()``. Clearing the last-run times does
    /// make every scheduled ritual immediately due again, which is the correct reading of a device
    /// with no history: nothing has run yet.
    public func resetRunHistory() async {
        // Hydrate first, then clear. The reset preserves ritual *structure*, so it must not write
        // through from an un-hydrated store — that would erase the user's enabled toggles and custom
        // rituals along with the history. Hydration completes before the clear, so nothing it loaded
        // can survive it, and `hydrated` stays true afterwards so no later access re-reads the
        // payload this just erased.
        await ensureHydrated()
        lastRuns.removeAll()
        completedOccurrenceIDs.removeAll()
        runningRitualIDs.removeAll()
        await persist()
    }
}

/// Pure, read-only ritual scheduling helper. It decides *which* rituals are due and *which* of their
/// playbooks should run — the caller (the runtime host / `SchedulingEngine`) does the actual running.
public enum RitualEngine {
    /// Whether an enabled ritual is due to run, mirroring the playbook trigger semantics.
    public static func isDue(
        _ ritual: RitualDefinition,
        lastRun: Date?,
        now: Date = .now,
        staleSignal: Bool = false,
        approvalPendingSignal: Bool = false
    ) -> Bool {
        guard ritual.isEnabled else { return false }
        if let schedule = ritual.calendarSchedule {
            guard let occurrence = mostRecentOccurrence(for: schedule, at: now) else { return false }
            return lastRun.map { $0 < occurrence } ?? true
        }
        switch ritual.trigger {
        case .manual:
            return false
        case let .schedule(interval):
            guard let lastRun else { return true }
            return now.timeIntervalSince(lastRun) >= interval
        case .event(.artifactStale):
            return staleSignal
        case .event(.approvalPendingTooLong):
            return approvalPendingSignal
        case let .maintenance(interval):
            guard let lastRun else { return true }
            return now.timeIntervalSince(lastRun) >= interval
        }
    }

    public static func mostRecentOccurrence(
        for schedule: RitualCalendarSchedule,
        at now: Date
    ) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: schedule.timeZoneIdentifier) ?? .autoupdatingCurrent
        var components = DateComponents()
        components.hour = schedule.hour
        components.minute = schedule.minute
        components.second = 0
        if schedule.frequency == .weekly {
            components.weekday = schedule.weekday ?? 2
        }
        return calendar.nextDate(
            after: now,
            matching: components,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .backward
        )
    }

    /// The ordered playbook IDs a due ritual should run. Empty when the ritual is not due.
    public static func plannedPlaybookIDs(
        for ritual: RitualDefinition,
        lastRun: Date?,
        now: Date = .now
    ) -> [String] {
        isDue(ritual, lastRun: lastRun, now: now) ? ritual.playbookIDs : []
    }

    /// Filters `rituals` down to those due to run now, given a per-ritual last-run lookup. The caller
    /// (the runtime host driven by the background scheduler) runs whichever this returns.
    public static func dueRituals(
        from rituals: [RitualDefinition],
        lastRun: (RitualDefinition) -> Date?,
        now: Date = .now,
        staleSignal: Bool = false,
        approvalPendingSignal: Bool = false
    ) -> [RitualDefinition] {
        rituals.filter { ritual in
            isDue(
                ritual,
                lastRun: lastRun(ritual),
                now: now,
                staleSignal: staleSignal,
                approvalPendingSignal: approvalPendingSignal
            )
        }
    }
}
