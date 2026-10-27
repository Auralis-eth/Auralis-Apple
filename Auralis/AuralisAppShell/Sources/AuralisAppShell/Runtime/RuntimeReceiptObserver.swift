import AuralisCrypto
import AuralisFoundation
import Foundation
import OSLog
import AuralisReceipts
import AuralisRuntime

/// Turns governance events that do not otherwise pass through the governed receipt sink into
/// durable audit receipts. Tool execution events continue to be receipted by `ReceiptStoreSink`,
/// avoiding duplicate receipts for the same action.
public actor RuntimeReceiptObserver {
    public static let subscriberID = "runtime.receipts"
    /// The actor the receipts written here are attributed to. `public` so the host can attribute the
    /// degraded-evidence session it opens on this observer's behalf to the same identity the receipt
    /// would have carried, rather than to a second name for the same writer.
    public static let actor = ActorRef(kind: .workflow, identifier: "runtime.event-observer")
    private static let retainedEventIDLimit = 1_024
    /// How deep ``start()`` scans the receipt ledger for already-receipted event IDs.
    ///
    /// Sized by what the cache actually has to *cover*, not by how full it could theoretically be.
    /// The only events this seed protects against re-receipting are the ones that will be replayed
    /// on reconnect, and replay starts from the last durable checkpoint — which
    /// ``PersistentRuntimeEventCheckpointStore`` coalesces to at most 32 saves or 5 seconds behind
    /// live. So the window that matters is the last few dozen handled events, and only the newest
    /// receipts in it can possibly collide.
    ///
    /// This was 10,000. The loop below stops early once the cache is full, but the *fetch* does not:
    /// every launch materialised and decoded up to ten thousand receipt records with their payloads,
    /// on the path `bootstrap()` awaits — so Mission Control and the first governed call waited on it.
    /// A few hundred covers the replay window many times over at a fraction of the cost; the
    /// checkpoint is what provides correctness here, and the cache is only belt-and-braces for the
    /// crash-between-`handle`-and-`saveCheckpoint` case.
    private static let seedScanLimit = 512
    private static let logger = Logger(subsystem: "com.auralis.runtime", category: "receipt-observer")
    /// Delay before reconnecting after the live stream ends. Also the first retry delay after a
    /// failed receipt write.
    private static let baseRetryDelay: TimeInterval = 1
    /// Ceiling for the failure backoff. The observer never gives up — abandoning the subscription
    /// would stop auditing silently, which is worse than retrying — so the backoff caps rather than
    /// terminates, and a store that recovers is picked up within a minute.
    private static let maximumRetryDelay: TimeInterval = 60

    private let events: @Sendable () async -> AsyncStream<WorkflowEventEnvelope>
    private let store: any ReceiptStore
    private let publisher: any RuntimeEventPublishing
    private let checkpointStore: any RuntimeEventCheckpointStoring
    /// The posture to stamp on the receipts this observer writes. Supplied by ``RuntimeHost`` so a
    /// governance receipt written while the app is in Assist or Operate does not claim `.observe`,
    /// which is what this hardcoded before. `@MainActor @Sendable` (rather than a plain
    /// `ReceiptMode`) because the mode is live state owned by the host and can change while the
    /// observer is running; the same shape `ReceiptStoreSink` uses.
    private let modeProvider: @MainActor @Sendable () -> ReceiptMode
    /// Reports a governance receipt this observer could not write, so the host raises the same
    /// degraded-audit-evidence banner it raises for its own receipt failures.
    ///
    /// Without this the failure was a log line and two properties nothing read. That mattered more
    /// here than anywhere else: this observer is the *only* writer of capability grant, revocation,
    /// and expiry receipts, so an unwritable ledger silently dropped the authority half of the audit
    /// trail while Mission Control went on presenting the runs it authorized as fully evidenced.
    /// The host's own receipt path raised a banner for exactly this; the observer stayed quiet.
    ///
    /// Called once per *distinct* event, not once per attempt. See ``handle(_:)``.
    private let failureReporter: (@Sendable (String?) async -> Void)?
    /// Reused across receipts because `ISO8601DateFormatter` is not cheap to construct and a grant
    /// receipt formats two dates. `seedRoutineAuthority()` grants a lease per installed playbook per
    /// actor on every bootstrap, so constructing one per call put a burst of them on the launch path.
    ///
    /// An instance property rather than a `static let`: the formatter is a reference type and not
    /// `Sendable`, so as static storage it would be unprotected global mutable state. Held here it is
    /// isolated to this actor, which is what makes reusing it safe.
    private let timestampFormatter = ISO8601DateFormatter()
    private var registrationTask: Task<AsyncStream<WorkflowEventEnvelope>?, Never>?
    private var task: Task<Void, Never>?
    private var lifecycleGeneration = 0
    private var retainedEventIDs: [UUID] = []
    private var seenEventIDs: Set<UUID> = []
    public private(set) var persistenceFailureCount = 0
    public private(set) var lastFailedEventID: UUID?
    /// Why the already-receipted cache could not be seeded from the ledger, when it could not be.
    ///
    /// The seed read was a bare `try?`, which is the one thing the rest of this package refuses to
    /// do with a read failure: an unreadable ledger left the cache empty and said nothing anywhere.
    /// That silently removes the exact protection the cache exists for — see ``seedScanLimit``, which
    /// describes it as belt-and-braces for a crash between ``handle(_:)`` and `saveCheckpoint` — so a
    /// replayed event would be receipted a second time, duplicating a governance record in a ledger
    /// whose worth is that it records what actually happened once.
    ///
    /// Recorded rather than propagated because ``start()`` cannot fail. An observer that refused to
    /// start would stop auditing altogether, which is strictly worse than a cache that is merely
    /// cold; the durable checkpoint still provides correctness in the ordinary case.
    public private(set) var seedFailureReason: String?

    /// How many event IDs the de-duplication window currently holds. `internal` and test-only: what
    /// belongs in the window is a correctness property with no observable effect until a replay
    /// happens, so asserting on it directly is the only way to pin it — going through the bus cannot,
    /// since ``RuntimeEventBus/events()`` buffers newest-first and drops under load, so a test could
    /// not guarantee the traffic it published was ever seen.
    var retainedEventIDCount: Int { retainedEventIDs.count }

    public init(
        events: @escaping @Sendable () async -> AsyncStream<WorkflowEventEnvelope>,
        store: any ReceiptStore,
        publisher: any RuntimeEventPublishing,
        checkpointStore: any RuntimeEventCheckpointStoring = InMemoryRuntimeEventCheckpointStore(),
        modeProvider: @escaping @MainActor @Sendable () -> ReceiptMode = { .observe },
        failureReporter: (@Sendable (String?) async -> Void)? = nil
    ) {
        self.events = events
        self.store = store
        self.publisher = publisher
        self.checkpointStore = checkpointStore
        self.modeProvider = modeProvider
        self.failureReporter = failureReporter
    }

    /// Registers the subscription before returning. Repeated calls are idempotent.
    public func start() async {
        guard task == nil else { return }
        let generation = lifecycleGeneration
        let registration: Task<AsyncStream<WorkflowEventEnvelope>?, Never>
        if let registrationTask {
            registration = registrationTask
        } else {
            registration = Task { [weak self] in
                guard let self else { return nil }
                await self.seedSeenEventIDs()
                guard Task.isCancelled == false else { return nil }
                return await self.events()
            }
            registrationTask = registration
        }
        let resolvedStream = await registration.value
        // Cleared before either bail-out below, not after both. A registration that resolved to `nil`
        // is spent — it will hand back `nil` to every future caller — so leaving it in place would
        // make `start()` short-circuit for the life of the observer and stop auditing altogether.
        // Only ``stop()`` can produce that `nil` today, and it clears this itself, so the old
        // ordering was unreachable rather than wrong; this makes it not depend on that.
        if generation == lifecycleGeneration {
            registrationTask = nil
        }
        guard let stream = resolvedStream,
              generation == lifecycleGeneration else { return }
        guard task == nil else { return }
        task = Task { [weak self] in
            var activeStream = stream
            // Grows only while consecutive reconnects are caused by a *failed write*. A stream that
            // simply overflowed is a healthy reconnect and resets it. Without this the two cases
            // shared one fixed one-second delay, so a store that was down for good (disk full, the
            // container gone) was retried once a second for the entire life of the process.
            var failureRetryDelay = Self.baseRetryDelay
            while Task.isCancelled == false {
                var didFailToPersist = false
                for await envelope in activeStream {
                    guard Task.isCancelled == false else { return }
                    guard await self?.handle(envelope) == true else {
                        didFailToPersist = true
                        break
                    }
                    guard Task.isCancelled == false else { return }
                    await self?.checkpointStore.saveCheckpoint(envelope.id, for: Self.subscriberID)
                }
                // A reliable stream is deliberately terminated by the bus when its bounded
                // in-memory buffer overflows. Reconnect from the last durable checkpoint so the
                // persisted history, rather than RAM, supplies the backlog. The same reconnect
                // resumes the event that failed to persist, which was never checkpointed.
                guard Task.isCancelled == false else { return }
                let delay: TimeInterval
                if didFailToPersist {
                    delay = failureRetryDelay
                    failureRetryDelay = min(failureRetryDelay * 2, Self.maximumRetryDelay)
                } else {
                    failureRetryDelay = Self.baseRetryDelay
                    delay = Self.baseRetryDelay
                }
                try? await Task.sleep(for: .seconds(delay))
                guard Task.isCancelled == false else { return }
                guard let nextStream = await self?.events() else { return }
                activeStream = nextStream
            }
        }
    }

    public func stop() {
        lifecycleGeneration += 1
        registrationTask?.cancel()
        registrationTask = nil
        task?.cancel()
        task = nil
    }

    private func handle(_ envelope: WorkflowEventEnvelope) async -> Bool {
        guard !seenEventIDs.contains(envelope.id) else { return true }
        guard let draft = await receiptDraft(for: envelope) else {
            // Deliberately *not* remembered. This used to cache every event it saw, including the
            // overwhelming majority it does not receipt — tool calls, checks, artifacts, workflow
            // blocks — which filled the 1,024-entry window with IDs that need no de-duplication and
            // evicted the capability grant/revoke/expiry IDs the cache exists to protect. On a busy
            // launch the window could turn over before the replay it guards against even happened,
            // so the protection was present in structure and absent in effect.
            //
            // Costs nothing to re-derive: ``receiptDraft(for:)`` is a `switch` that returns `nil` on
            // its default branch, so a replayed non-governance event is rejected as cheaply the
            // second time as the first.
            return true
        }
        let record: ReceiptRecord
        do {
            record = try await store.append(draft)
        } catch {
            // Counted, logged, and reported once per *distinct* event rather than once per attempt.
            // A failure breaks the stream and the reconnect replays from the last checkpoint, which
            // puts the same unwritable event back at the head — so attempt-counting inflated
            // `persistenceFailureCount` (and would inflate the host's `missingReceiptCount`) once a
            // second, forever, describing one lost receipt as thousands. The reconnect is the same
            // event whenever `lastFailedEventID` still matches, which is what makes this the right
            // guard rather than an unbounded set.
            let isFirstAttemptForThisEvent = lastFailedEventID != envelope.id
            lastFailedEventID = envelope.id
            guard isFirstAttemptForThisEvent else { return false }
            persistenceFailureCount += 1
            Self.logger.error("Failed to persist a runtime audit receipt for event \(envelope.id.uuidString, privacy: .public)")
            await failureReporter?(envelope.correlationID)
            return false
        }
        _ = remember(envelope.id)
        await publisher.publish(
            WorkflowEventEnvelope(
                event: .receiptCreated(id: record.id),
                correlationID: envelope.correlationID
            )
        )
        return true
    }

    /// Rebuilds the already-receipted set from the ledger, so a relaunch does not re-receipt an event
    /// that was handled just before the process ended.
    ///
    /// The ordering matters and used to be inverted. `latest(limit:)` returns receipts newest-first
    /// while ``remember(_:)`` evicts the *earliest appended*, so seeding in fetch order filled the
    /// cache with the newest IDs and then evicted exactly those, leaving only the oldest — the
    /// opposite of what dedupe needs. The IDs that matter are the newest: `saveCheckpoint` runs after
    /// `handle`, so a crash in between replays the most recent event, and that is the one the cache
    /// has to recognise. Seeding oldest-first makes the newest the survivors.
    private func seedSeenEventIDs() async {
        let receipts: [ReceiptRecord]
        do {
            receipts = try await store.latest(limit: Self.seedScanLimit)
        } catch {
            seedFailureReason = error.localizedDescription
            Self.logger.error(
                """
                Failed to seed the already-receipted event cache from the receipt ledger; an event \
                receipted just before the last durable checkpoint may be receipted a second time \
                when the stream reconnects: \(error.localizedDescription, privacy: .public)
                """
            )
            return
        }
        var newestFirst: [UUID] = []
        for receipt in receipts {
            guard case let .string(eventID)? = receipt.details.values["runtimeEventID"],
                  let id = UUID(uuidString: eventID) else { continue }
            newestFirst.append(id)
            if newestFirst.count == Self.retainedEventIDLimit { break }
        }
        for id in newestFirst.reversed() {
            _ = remember(id)
        }
    }

    private func remember(_ id: UUID) -> Bool {
        guard seenEventIDs.insert(id).inserted else { return false }
        retainedEventIDs.append(id)
        if retainedEventIDs.count > Self.retainedEventIDLimit {
            seenEventIDs.remove(retainedEventIDs.removeFirst())
        }
        return true
    }

    private func receiptDraft(for envelope: WorkflowEventEnvelope) async -> ReceiptDraft? {
        let kind: String
        let summary: String
        let details: ReceiptPayload

        switch envelope.event {
        case let .capabilityLeaseGranted(lease):
            // Receipted for the same reason revocation is, and previously was not: a grant is the
            // moment authority is *created*, which is the half of the story an auditor most needs.
            // Leaving it out meant the ledger recorded every withdrawal of authority and no issuance
            // of it — so a lease that was granted and then expired appeared in history as an
            // expiry with no origin, and a grant still live appeared nowhere at all.
            kind = "runtime.capability.granted"
            summary = "Capability granted: \(lease.capability.rawValue)"
            details = eventDetails(envelope, values: [
                "capability": .string(lease.capability.rawValue),
                "grantedTo": .string(Self.describe(lease.grantedTo)),
                "reason": .string(lease.reason),
                "grantedAt": .string(timestampFormatter.string(from: lease.grantedAt)),
                "expiresAt": .string(timestampFormatter.string(from: lease.expiresAt)),
                "isCrypto": .bool(CapabilityDomain.isCrypto(lease.capability))
            ])
        case let .capabilityRevoked(capability):
            kind = "runtime.capability.revoked"
            summary = "Capability revoked: \(capability.rawValue)"
            details = eventDetails(envelope, values: ["capability": .string(capability.rawValue)])
        case let .capabilityLeaseExpired(capability):
            kind = "runtime.capability.expired"
            summary = "Capability lease expired: \(capability.rawValue)"
            details = eventDetails(envelope, values: ["capability": .string(capability.rawValue)])
        default:
            // Governed tool outcomes, approvals, checks, artifacts, and workflow blocks already flow
            // through ReceiptStoreSink. receiptCreated must also be ignored to prevent feedback loops.
            return nil
        }

        let actor = Self.actor
        return ReceiptDraft(
            createdAt: envelope.timestamp,
            category: "runtime",
            kind: kind,
            correlationID: envelope.correlationID,
            payload: details,
            actorDetail: actor.receiptActorDetail,
            authorityDetail: nil,
            mode: await modeProvider(),
            summary: summary,
            provenance: "local",
            isSuccess: true
        )
    }

    /// A stable, readable name for the actor a grant was issued to. Identifier first — it is the
    /// stable key — falling back to the kind's display title for `.human`, which carries no
    /// identifier by construction.
    private static func describe(_ actor: ActorRef) -> String {
        actor.identifier ?? actor.kind.displayTitle
    }

    private func eventDetails(
        _ envelope: WorkflowEventEnvelope,
        values: [String: ReceiptJSONValue]
    ) -> ReceiptPayload {
        var resolved = values
        resolved["runtimeEventID"] = .string(envelope.id.uuidString)
        return ReceiptPayload(values: resolved)
    }
}
