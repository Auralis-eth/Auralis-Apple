import CryptoKit
import Foundation
import OSLog
import ReceiptsCore
import RuntimeCore
import SwiftData
import AuralisFoundation

public struct ReceiptIntegrityVerificationResult: Equatable, Sendable {
    /// Three genuinely different answers, because collapsing them costs the user their audit trail.
    ///
    /// The distinction that matters is **"this device cannot vouch for these rows"** versus **"these
    /// rows have been altered"**. Two ordinary events produce the former: upgrading an install whose
    /// receipts predate provenance signing, and restoring to a new device — the signing key and the
    /// integrity heads are both `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, so neither survives a
    /// transfer while the SwiftData store does. Reporting either as tampering marks an honest ledger
    /// invalid, and because ``ReceiptPersistenceStore/exportAll()`` refuses on an invalid verdict, the
    /// only recovery a user has is destroying the history they were trying to export.
    public enum Status: Equatable, Sendable {
        /// Fully verified: every row chain-consistent and signed by this device's current identity.
        case verified
        /// Structurally intact, but not attestable by this device — an unsigned prefix from before
        /// signing existed, rows signed by a previous identity, or missing local anchors after a
        /// restore. Readable and exportable; just not provable from here.
        case unattested
        /// Genuinely inconsistent: a broken chain, a sequence gap, a removed or substituted
        /// signature, or a head that disagrees with a present anchor.
        case tampered
    }

    public let status: Status
    /// The reason for a non-``Status/verified`` verdict, whatever its severity.
    public let failureReason: String?
    /// What the ledger high-water mark suggests about receipts removed from the *end* of the ledger,
    /// or `nil` when it suggests nothing.
    ///
    /// **Advisory. Never reflected in ``status`` or ``isFullyAttested``** — that independence is the
    /// whole reason this is a separate field rather than another entry in ``failureReason``. The mark
    /// is an unauthenticated Keychain item whose absence is also uninformative (a device restore has
    /// no `ThisDeviceOnly` state), so it cannot carry a verdict in either direction: gating on its
    /// presence downgraded honest restored ledgers, and gating on its content offered a guarantee that
    /// dissolves against anyone able to write the Keychain. See
    /// ``ReceiptIntegrity/completenessAdvisory(sequenceIDs:highWaterMark:completenessUnconfirmed:)``
    /// for the full argument.
    ///
    /// Surface it to a person or a log as a *suggestion to investigate*. Do not gate trust on it, and
    /// do not treat its absence as confirmation that nothing was removed.
    public let completenessAdvisory: String?

    /// `false` only for ``Status/tampered``: *this device found nothing that contradicts the ledger*.
    ///
    /// **Not a statement that the history is genuine, and not sufficient to decide whether to trust
    /// it.** The chain hash is an unkeyed SHA-256, so anyone who can write both the SwiftData store
    /// and the Keychain can delete the signing key and the anchors, rewrite every row, and produce a
    /// ledger that reads `.unattested` — which this accepts, because that state is genuinely
    /// indistinguishable from an ordinary device restore. Refusing `.unattested` is what left
    /// upgraded and restored installs unable to export the history they had, so accepting it is the
    /// right trade; the consequence is that local validity cannot mean provenance.
    ///
    /// Provenance is established by ``ReceiptProvenanceVerifier/verify(_:trustedSignerFingerprint:)``
    /// against a fingerprint pinned through a separate channel. That check *does* catch the rewrite
    /// above. Use this only to gate a local export; use ``isFullyAttested`` to say anything to a
    /// person about trust.
    public var isValid: Bool { status != .tampered }

    /// `true` only when this device can cryptographically vouch for every row — the property a trust
    /// surface should show.
    ///
    /// **Deliberately independent of ``completenessAdvisory``.** It says every row *present* is
    /// chain-consistent and signed by this device's current identity. It does **not** claim the rows
    /// present are all the rows there ever were: nothing available locally can establish that against
    /// an attacker who can write the Keychain, so folding the high-water mark in here would have
    /// dressed a best-effort heuristic up as a cryptographic guarantee. A surface that cares about
    /// removal has to show the advisory alongside this, not instead of it.
    ///
    /// Has no reader today, and that is a known gap rather than an oversight: there is no receipt
    /// export or attestation feature yet, and the console reads history through
    /// ``ReceiptStore/allRecords()``, which deliberately performs no verification. Whoever builds
    /// that surface should read this and not ``isValid``, and should surface the advisory too.
    public var isFullyAttested: Bool { status == .verified }

    public static let valid = ReceiptIntegrityVerificationResult(
        status: .verified,
        failureReason: nil,
        completenessAdvisory: nil
    )

    /// Intact but not provable from this device. Not a failure.
    public static func unattested(_ reason: String) -> ReceiptIntegrityVerificationResult {
        ReceiptIntegrityVerificationResult(
            status: .unattested,
            failureReason: reason,
            completenessAdvisory: nil
        )
    }

    public static func invalid(_ reason: String) -> ReceiptIntegrityVerificationResult {
        ReceiptIntegrityVerificationResult(
            status: .tampered,
            failureReason: reason,
            completenessAdvisory: nil
        )
    }

    /// Attaches the mark's observation to a verdict already decided without it.
    ///
    /// Separate from the factories so the ordering is enforced by shape: the verdict is computed
    /// first, and this only ever adds a note to it. There is no path by which an advisory can change
    /// a `status`.
    public func withCompletenessAdvisory(_ advisory: String?) -> ReceiptIntegrityVerificationResult {
        ReceiptIntegrityVerificationResult(
            status: status,
            failureReason: failureReason,
            completenessAdvisory: advisory
        )
    }
}

public enum ReceiptProvenanceExportError: Error, Equatable, Sendable {
    case integrityFailure(String)
    case unsupportedFormat
}

/// A persistence failure where the original operation and its compensating recovery both failed.
/// Callers must treat this as degraded receipt integrity rather than as an ordinary append failure,
/// because the database and trusted integrity-head store may no longer agree.
///
/// What the resulting ledger reads as, measured rather than assumed (see
/// `appendCompensationFailureIsReported`): **`.unattested`, and still exportable.** The row survived
/// and the anchor still names its immediate parent, so this lands in the one-row crash window the
/// anchor check tolerates; the heal it attempts then fails too, and that is reported as a reason
/// rather than a verdict. Earlier comments here claimed `.tampered` for the whole ledger — it is
/// worth being precise, because `.tampered` would mean a person could not export the history this
/// error is warning them about.
///
/// Reset has no case here: it deletes rows before touching the anchors, so neither of its failure
/// points needs a compensating write that could itself fail.
public enum ReceiptPersistenceConsistencyError: LocalizedError, Equatable, Sendable {
    case appendCompensationFailed(headStoreError: String, receiptRollbackError: String)
    /// The ledger's top sequence number leaves no room to allocate the next one.
    ///
    /// Unreachable honestly — it needs `Int.max` receipts — so in practice it means the `sequenceID`
    /// column of a row, or the high-water mark, has been corrupted or forged. Raised as an error
    /// because the alternative was a **trap**: allocation is `max(highestOnDisk, mark) + 1`, so a
    /// single row edited to `Int.max` made every subsequent append overflow and kill the process.
    /// Measured with SwiftData write access alone, no Keychain and no signing key: `SIGTRAP` on the
    /// next `append`, permanently — a corrupted column denying the whole audit trail, and a crash in
    /// front of the person, which is the same failure shape a non-finite `createdAt` once had on the
    /// verify path.
    ///
    /// `verifyIntegrity()` reports such a ledger `.tampered` (the chain hash commits to `sequenceID`),
    /// so the condition is already visible through the verdict; this exists so the write path says it
    /// too instead of aborting.
    case sequenceAllocationOutOfRange(highest: Int)

    public var errorDescription: String? {
        switch self {
        case let .appendCompensationFailed(headStoreError, receiptRollbackError):
            return "Receipt integrity-head update failed (\(headStoreError)), and the persisted receipt could not be rolled back (\(receiptRollbackError))."
        case let .sequenceAllocationOutOfRange(highest):
            return "The receipt ledger's highest sequence number (\(highest)) leaves no room to allocate another, so this ledger's sequence column has been altered."
        }
    }
}

public struct ReceiptHeadRestorationError: LocalizedError, Equatable, Sendable {
    public let failures: [String]

    public var errorDescription: String? {
        "One or more receipt integrity heads could not be restored: \(failures.joined(separator: "; "))."
    }
}

/// Supplies the signer fingerprint through a channel separate from the exported ledger. A verifier
/// must pin this value before accepting an export; trusting the fingerprint embedded in that same
/// export proves consistency, not origin.
public protocol ReceiptProvenanceTrustAnchorProviding: Sendable {
    func provenanceTrustAnchor() async throws -> ReceiptProvenanceTrustAnchor
}

/// The ledger operations that acquire the lock. Carried in the task-local marker and in
/// ``ReceiptLedgerReentrancyError`` so a refusal names both ends of the nesting rather than only
/// reporting that one happened.
enum ReceiptLedgerOperation: String, Sendable {
    case append
    case resetAll
    case verifyIntegrity
    case exportAll
    case restoreHeads
}

/// A receipt ledger operation refused because the task tree attempting it is already inside a live
/// ledger-lock body on the same store, where waiting would be waiting on itself.
///
/// Internal rather than public, and that is enough: it escapes to cross-module callers as
/// `any Error`, which is all the best-effort recorders that swallow it ever read. Tests inside this
/// package name it through `@testable`.
struct ReceiptLedgerReentrancyError: LocalizedError, Equatable, Sendable {
    let attemptedOperation: ReceiptLedgerOperation
    let enclosingOperation: ReceiptLedgerOperation

    var errorDescription: String? {
        "A receipt ledger \(attemptedOperation.rawValue) was attempted from inside a \(enclosingOperation.rawValue) that still holds the ledger lock, so it was refused rather than left to wait on itself."
    }
}

/// Identifies the acquisition that owns the current task tree: which acquisition, on which store,
/// doing what.
///
/// A bare `Bool` could not distinguish any of the three, and all three turned out to matter. The
/// task-local is process-wide while ``ReceiptPersistenceStore`` is memoized *per `ModelContainer`*
/// (see ``ReceiptStores/persistenceStore(for:)``), so a boolean let one store's body speak for every
/// other store's queue. And task-locals are inherited by unstructured `Task {}`, so a boolean set
/// inside a body outlived that body in any task spawned from it — including, via a
/// `modelContext.save()` notification, work with no relationship to receipts at all.
///
/// ``acquisitionID`` is a `UUID` rather than the `Int` token the tail chain uses, and it is the
/// field the liveness check keys on. The tail token restarts at zero per store and `storeID` is an
/// address that the allocator reuses once a store deallocates, so the pair is not unique over the
/// life of the process: a marker carried out of a since-deallocated store could name a live
/// acquisition in a new store that happened to land on the same address with the same token, and
/// the append would be refused for a self-wait that does not exist. Improbable in an app, routine
/// in a test suite that builds a store per case and starts every token sequence at 1. A UUID costs
/// one allocation per ledger operation, on a path that already accepts a P-256 signature.
private struct LedgerLockContext: Sendable {
    let acquisitionID: UUID
    let storeID: ObjectIdentifier
    let operation: ReceiptLedgerOperation
}

/// Marks the task tree currently running a ledger-lock body, so re-entering the lock from inside one
/// is caught at the call site instead of deadlocking. See ``ReceiptPersistenceStore/withLedgerLock(_:_:)``.
private enum LedgerLock {
    @TaskLocal static var context: LedgerLockContext?
}

/// Conformance is hand-rolled rather than synthesized by `@ModelActor` on purpose. That macro adds a
/// public `init(modelContainer:)` which initializes only the executor and the container, so it can
/// only exist if every other stored property carries a default — and a defaulted signer is exactly
/// the footgun described on ``signer``. Writing the two requirements out keeps this actor's
/// initializer the only way in.
public actor ReceiptPersistenceStore: ModelActor {
    /// `internal`, like ``signer``, so the verify-and-export half in this actor's other file can
    /// report the same degraded-integrity states this one does.
    static let logger = Logger(subsystem: "Auralis", category: "ReceiptPersistenceStore")

    public nonisolated let modelExecutor: any ModelExecutor
    public nonisolated let modelContainer: ModelContainer

    /// Whether ``StoredReceipt/accountKey`` has been backfilled for pre-column rows in this store.
    private var didBackfillAccountKeys = false
    /// `internal`, not `private`, only so the verify-and-export half can live in
    /// `ReceiptPersistenceStore+Verification.swift`. Nothing outside this actor's two files reads it.
    let integrityHeadStore: any ReceiptIntegrityHeadStoring
    /// Required, and deliberately without a default.
    ///
    /// `SoftwareReceiptSigner()` mints a *fresh random* key per instance, so defaulting to one
    /// silently turned attestation off: every row would be signed by a key that no longer exists
    /// after relaunch, ``verifyIntegrity()`` would never match a row against the current identity,
    /// and `currentIdentitySeen` would stay empty. That set is also what makes a missing Keychain
    /// anchor count as tampering, so the default did not merely weaken attestation — it disabled the
    /// anchor check, and a rewritten ledger with deleted anchors read as `.unattested`, which
    /// `isValid` accepts and `exportAll()` happily exports.
    ///
    /// A test that does not care about provenance should pass an explicit `SoftwareReceiptSigner()`;
    /// production passes ``ReceiptSignerFactory/deviceSigner()``.
    ///
    /// `internal` for the same reason as ``integrityHeadStore``: the export path lives in this actor's
    /// other file.
    let signer: any ReceiptSigning
    /// The external witness. See ``ReceiptLedgerWitnessing`` for why local state alone could not
    /// deliver the three properties this buys.
    ///
    /// Defaulted to ``UnconfiguredReceiptLedgerWitness``, and that default is safe in a way the
    /// defaulted signer never was: it *throws*, so verification reports the ledger as unwitnessed
    /// rather than quietly treating "nobody is watching" as "nobody objects".
    ///
    /// `internal` for the same reason as ``signer`` — the verify-and-export half lives in this
    /// actor's other file.
    let witness: any ReceiptLedgerWitnessing

    /// The tail of the ledger-mutation chain: a task that finishes exactly when the most recently
    /// enqueued `append`/`resetAll` finishes. Tagged with a token because `Task` is a struct with no
    /// identity to compare, so "am I still the tail?" has to be asked of the token.
    ///
    /// See ``withLedgerLock(_:_:)`` for why the chain exists at all.
    private struct LedgerTail {
        let token: Int
        let task: Task<Void, Never>
    }

    private var ledgerTail: LedgerTail?
    private var nextLedgerToken = 0

    /// Acquisitions whose body is running right now.
    ///
    /// This is what makes an inherited marker checkable rather than merely present. A marker naming
    /// an acquisition that is no longer in here belonged to a body that has already finished, so the
    /// task carrying it can acquire the lock like any other caller — it queues behind the tail and
    /// waits for nothing it owns.
    ///
    /// **Membership must track the body exactly, not the surrounding `withLedgerLock` call.** The
    /// refusal condition is "a marker is present *and* names a live acquisition", and the marker
    /// escapes its body — that is the premise the whole liveness check exists to handle. So an
    /// acquisition that stays registered after its body returns makes an escaped marker name a live
    /// acquisition with no body behind it, and the escaped task's append is refused for a self-wait
    /// that is over. Registration therefore brackets ``runLedgerBody(_:_:)``, with no suspension
    /// point between the insert and the marker going up, or between the marker coming down and the
    /// remove.
    private var liveLedgerAcquisitions: Set<UUID> = []

    /// Test seam for the bracketing rule above: the invariant is "empty once no body is running",
    /// and the window it guards against is a scheduling race that cannot be observed deterministically
    /// from outside. Reading the set directly is what makes that pinnable instead of flaky.
    var liveLedgerAcquisitionsForTesting: Set<UUID> { liveLedgerAcquisitions }

    #if DEBUG
    /// Makes the compensating row delete in ``performAppend(_:)`` fail, so the
    /// ``ReceiptPersistenceConsistencyError/appendCompensationFailed`` path is reachable. `DEBUG`
    /// only, so it cannot exist in a release binary.
    private var compensationFailureForTesting: Error?

    func setCompensationFailureForTesting(_ error: Error?) {
        compensationFailureForTesting = error
    }
    #endif

    public init(
        modelContainer: ModelContainer,
        integrityHeadStore: any ReceiptIntegrityHeadStoring = KeychainReceiptIntegrityHeadStore(),
        signer: any ReceiptSigning,
        witness: any ReceiptLedgerWitnessing = UnconfiguredReceiptLedgerWitness()
    ) {
        let modelContext = ModelContext(modelContainer)
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: modelContext)
        self.modelContainer = modelContainer
        self.integrityHeadStore = integrityHeadStore
        self.signer = signer
        self.witness = witness
    }

    /// Runs `body` once every ledger mutation already enqueued has finished, in the order callers
    /// arrived. Modelled on `RuntimeKit.CorrelationGate.withLock(_:_:)`, minus the per-key chain:
    /// there is one receipt chain, so there is one queue.
    ///
    /// **Why this is needed even though this is an actor.** An actor serializes only *between*
    /// suspension points. ``append(_:)`` reads the account's latest receipt, derives its
    /// `accountSequenceID` and `previousReceiptHash` from it, and only then awaits
    /// `signer.sign(_:)` before inserting the row. A second append entering during that signature
    /// read the *same* latest row and minted a **duplicate `accountSequenceID` chained off the same
    /// previous hash**. Because rows are signed and immutable, nothing could repair it afterwards:
    /// ``verifyIntegrity()`` reported the ledger invalid from then on, and since ``exportAll()`` is
    /// gated on integrity, a person could never export their own provenance again. Measured: six
    /// concurrent appends produced "invalid account sequence".
    ///
    /// The store really is shared — ``ReceiptStores/persistenceStore(for:)`` memoizes one per
    /// `ModelContainer`, and the governed pipeline sink, the account and ENS recorders, the ritual
    /// coordinator, and both `RuntimeHost`s in the process all append through it.
    ///
    /// Serializing rather than reserving the sequence in-actor is deliberate: a hash chain *is* a
    /// serial structure, and a reservation would have to be unwound if the signature that follows it
    /// failed — while any append that had already chained off the reserved hash would be left
    /// pointing at a row that was never written. P-256 signing is sub-millisecond and receipt volume
    /// is low, so the queue costs nothing worth the alternative's failure mode.
    ///
    /// **This lock is not reentrant.** A body that calls back into `append`/`resetAll`/`verifyIntegrity`
    /// through their public entry points waits on itself forever. Anything that needs to compose two
    /// locked operations calls the `performX()` halves inside a single acquisition, which is why they
    /// exist as separate methods. Re-entry is refused with ``ReceiptLedgerReentrancyError`` rather
    /// than trapped or left to hang — see the guard below for the exact condition.
    ///
    /// Plain row reads (``latest(limit:)``, ``receipts(forCorrelationID:limit:)``, ``allRecords()``)
    /// stay outside: they check no invariant across a suspension, so a row arriving mid-read only
    /// means the caller saw a slightly older ledger.
    ///
    /// ``verifyIntegrity()`` and ``exportAll()`` do *not* stay outside, though they did until the
    /// races below were found. Both compare a row snapshot against the Keychain anchors across two
    /// suspensions (`signer.publicKeyRepresentation()` and `loadAllHeads()`), and `verifyIntegrity()`
    /// then *writes* an anchor to heal the crash window — so it is a read-modify-write of the same
    /// invariant `append` maintains, not a read:
    /// - an append committing during those suspensions left the snapshot's tip one row behind the
    ///   anchor, which is indistinguishable from a deleted tail: `.tampered`, and `exportAll()`
    ///   refusing, on a ledger that was never touched.
    /// - worse, the heal wrote back a head derived from the stale snapshot, *rewinding* an anchor that
    ///   two later appends had already advanced. That one is durable: the tip's
    ///   `previousReceiptHash` no longer matches the anchor at all, so the account reads `.tampered`
    ///   until it receives another receipt — forever, for a wallet the person stopped using, which is
    ///   exactly the case the healing was added to prevent.
    /// - and an append that had saved its row but not yet its anchor could be healed by the verify and
    ///   then rolled back by its own compensation, leaving an anchor ahead of every row.
    ///
    /// The cost runs both ways, and the export direction is the one that matters: a verify waits for
    /// any in-flight append (one P-256 signature), but every append also waits for an in-flight
    /// export, which is a payload decode, two canonical encodes, two SHA-256s and a P-256 verify *per
    /// row*. On a large ledger that stalls receipt writes across the process for the duration.
    /// Accepted rather than solved, because the alternative on offer was a verdict that could be
    /// durably wrong; a snapshot-based verify that releases the lock after its fetch is the way out
    /// if it ever hurts. ``verifyIntegrity()`` has no production caller today, so this is reachable
    /// only from a user-initiated export.
    ///
    /// Cancellation is deliberately not propagated: `Task.value` is not a cancellation point, so a
    /// cancelled caller cannot abandon a half-written row. The same choice means a dismissed export
    /// runs to completion holding the queue, which is the right trade for `append`/`resetAll` and
    /// merely wasteful for `exportAll()`.
    /// `internal` rather than `private` only so the verify-and-export half can acquire it from this
    /// actor's other file. **Not** an invitation to call it from anywhere else in the module: it is
    /// non-reentrant, and the guard below is the only thing standing between a misplaced call and
    /// a deadlock.
    ///
    /// `operation` is for diagnostics only. It costs one argument per call site and buys a refusal
    /// that names *both* the attempted and the enclosing operation, which is the difference between
    /// a field report that locates the composition bug and one that only says a nesting occurred.
    func withLedgerLock<T: Sendable>(
        _ operation: ReceiptLedgerOperation,
        _ body: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        // Refused rather than trapped, and the condition is narrower than "a marker is present".
        //
        // This was an `assert(!LedgerLock.isHeld)`, on the theory that re-entry is a programming
        // error the debug build catches before it can ship. A field crash disproved the theory: an
        // NFT refresh appending `nft.refresh.started` trapped here. `assert` also meant the two
        // configurations disagreed about the consequence — a crash in front of a person in debug,
        // the self-wait it was warning about in release — so neither was the stated behaviour.
        //
        // The narrowing matters just as much as the throw. A genuine self-wait needs the enclosing
        // body to be *this store's* and *still running*, and one set membership answers both: the
        // set is per store and the IDs in it are globally unique. A marker failing that test came
        // from a task that merely inherited it, and such a task queues behind the tail like any
        // other caller and completes. Refusing those would discard real receipts for a hazard that
        // is not present — and because the marker travels into every unstructured `Task {}` spawned
        // under a locked body, including ones a `modelContext.save()` notification starts, they are
        // the common case rather than the exotic one.
        if let inherited = LedgerLock.context {
            if liveLedgerAcquisitions.contains(inherited.acquisitionID) {
                Self.logger.fault(
                    "Refusing a re-entrant receipt ledger \(operation.rawValue, privacy: .public) attempted from inside a live \(inherited.operation.rawValue, privacy: .public) body. Call the unlocked performX() half from a locked body."
                )
                throw ReceiptLedgerReentrancyError(
                    attemptedOperation: operation,
                    enclosingOperation: inherited.operation
                )
            }
            // Inherited, not held: either another store's marker or one left behind by a body that
            // has already returned. Safe, and logged anyway — this line is the only evidence of how
            // the marker escapes, and the escape route is what a future fix would have to address.
            // Downgrade it to `debug` if it proves chatty; do not delete it without a replacement.
            Self.logger.error(
                "Receipt ledger \(operation.rawValue, privacy: .public) inherited a stale lock marker from \(inherited.operation.rawValue, privacy: .public) (sameStore: \(inherited.storeID == ObjectIdentifier(self), privacy: .public)); proceeding."
            )
        }

        // Built before the body's task, because the marker the body runs under has to name this
        // acquisition. Registration itself happens inside `runLedgerBody` — see
        // ``liveLedgerAcquisitions`` for why the two cannot be separated.
        nextLedgerToken += 1
        let token = nextLedgerToken
        let context = LedgerLockContext(
            acquisitionID: UUID(),
            storeID: ObjectIdentifier(self),
            operation: operation
        )
        let predecessor = ledgerTail?.task
        let work = Task { () async throws -> T in
            // A failed predecessor still releases the queue: it leaves no row behind, and the next
            // body re-reads the ledger rather than trusting anything the failure computed.
            await predecessor?.value
            return try await self.runLedgerBody(context, body)
        }
        ledgerTail = LedgerTail(
            token: token,
            task: Task { _ = try? await work.value }
        )
        defer {
            // Dropped only while still the tail, so the chain stays bounded without stranding a
            // caller that has already queued behind this one.
            if ledgerTail?.token == token {
                ledgerTail = nil
            }
        }
        return try await work.value
    }

    /// Runs one acquisition's body with its marker installed, registered as live for exactly that
    /// span and no longer.
    ///
    /// Split out of ``withLedgerLock(_:_:)`` so the registration can sit on the body rather than on
    /// the whole call. It runs after the queue wait, so a caller still waiting its turn is never
    /// registered; and the `defer` fires with no suspension point between the marker coming down and
    /// the remove, so there is no instant in which an escaped marker names a live acquisition whose
    /// body has already returned.
    private func runLedgerBody<T: Sendable>(
        _ context: LedgerLockContext,
        _ body: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        liveLedgerAcquisitions.insert(context.acquisitionID)
        defer { liveLedgerAcquisitions.remove(context.acquisitionID) }
        return try await LedgerLock.$context.withValue(context) {
            try await body()
        }
    }

    public func append(_ receipt: ReceiptDraft) async throws -> ReceiptRecord {
        try await withLedgerLock(.append) { [self] in
            try await performAppend(receipt)
        }
    }

    private func performAppend(_ receipt: ReceiptDraft) async throws -> ReceiptRecord {
        // First, before any write — including the backfill below. A refused append must leave the
        // ledger exactly as it found it, and a receipt is an immutable hashed fact, so the parent
        // contract has nowhere to be enforced except in front of the write.
        try validateParentReceipts(receipt.parentReceiptIDs)

        // Before anything predicates on `accountKey`, including the predecessor lookup below.
        try backfillAccountKeysIfNeeded()

        // Read from the ledger on every attempt, never carried over from the last one.
        //
        // This used to be served by a `nextSequenceIDCache`, and the cache was a liability rather
        // than an optimization. It had to be invalidated on every failure path between allocation
        // and insert or the attempt *burned* an ID and left a hole in `sequenceID` — five separate
        // `nextSequenceIDCache = nil` sites existed only to pay that debt, and any new `throw` in
        // between silently reopened it. It was also per instance, so a second
        // `ReceiptPersistenceStore` over the same container (which `SwiftDataReceiptResetService`
        // could build) would reset the ledger underneath a warm cache and hand the next append an ID
        // from the deleted one. Reading fresh costs a single indexed, `fetchLimit`-1 descending fetch
        // — `StoredReceipt` now indexes `sequenceID` — and a failed attempt simply inserts nothing,
        // so the next one derives the same ID again with no bookkeeping at all.
        //
        // The mark is read first so a number a deletion freed is never handed out again — reusing one
        // silently closes a reported truncation, which is the whole point of the check. Read as a
        // three-way state rather than an `Int?`, because "no mark exists" and "the mark is there but
        // will not decode" license different writes below. See ``LedgerHighWaterMarkState``.
        let markState = await loadLedgerHighWaterMarkState()
        let allocation = try nextSequenceIDAllocation(notBelow: markState.usableFloor)
        let nextSequenceID = allocation.sequenceID
        let accountKey: String
        let chainHash: String
        let storedReceipt: StoredReceipt
        do {
            // Both resolved through the shared helpers, so the values that go into the chain hash
            // below are the exact values `StoredReceipt` stores and `verifyIntegrity()` re-hashes. See
            // ``ReceiptAccountAddress`` and ``ReceiptChainScope``.
            let accountAddress = ReceiptAccountAddress.resolve(
                explicit: receipt.timelineAccountAddress,
                details: receipt.details
            )
            let chainRawValue = ReceiptChainScope.resolve(
                explicit: receipt.timelineChainRawValue,
                details: receipt.details
            )
            // Keyed the same way every grouping in this file is keyed, so the predecessor this append
            // chains off is the same row `verifyIntegrity()` will expect it to chain off.
            accountKey = ReceiptIntegrity.accountKey(accountAddress: accountAddress)
            let latestReceipt = try latestReceipt(accountKey: accountKey)
            // Overflow-checked for the reason the global allocation above is: this predecessor is a
            // stored row, so its `accountSequenceID` is attacker-writable and `+ 1` on `Int.max`
            // traps rather than returning a wrong number.
            let (accountSequenceID, accountSequenceOverflowed) =
                (latestReceipt?.accountSequenceID ?? 0).addingReportingOverflow(1)
            guard !accountSequenceOverflowed else {
                throw ReceiptPersistenceConsistencyError.sequenceAllocationOutOfRange(
                    highest: latestReceipt?.accountSequenceID ?? 0
                )
            }
            let previousReceiptHash = latestReceipt?.chainHash ?? ReceiptIntegrity.genesisHash
            let payloadHash = try ReceiptIntegrity.payloadHash(for: receipt.details)
            // Resolved before hashing, because the identity is part of the envelope — see the note on
            // `chainHash(signerPublicKey:)`. A signer that cannot produce its key is a write failure for
            // the same reason a signer that cannot sign is: no receipt enters the ledger unattributed.
            let signerPublicKey = try await signer.publicKeyRepresentation().base64EncodedString()
            // Minted here rather than defaulted inside `StoredReceipt.init`, because the id is now
            // part of the hashed envelope: the value that goes into the hash has to be the same value
            // the row is built with, and letting `init` generate its own would hash one id and store
            // another. Same discipline as `accountAddress`/`chainRawValue` above.
            let receiptID = UUID()
            // Spelled out rather than left to the two defaults agreeing. `ReceiptIntegrity.chainHash`
            // and `StoredReceipt.init` both default this to `.current`, so the row and its hash
            // happened to match by coincidence of two independent defaults — and the column decides
            // whether anything ever recomputes the hash (see `chainHash(forVerifiable:)`), so a drift
            // between them would be a row nothing checks. Passed at both ends, one value, visible.
            let envelopeVersion = ReceiptIntegrityEnvelopeVersion.current
            chainHash = try ReceiptIntegrity.chainHash(
                receiptID: receiptID,
                envelopeVersion: envelopeVersion,
                sequenceID: nextSequenceID,
                accountSequenceID: accountSequenceID,
                createdAt: receipt.createdAt,
                // Derived exactly as `StoredReceipt.init` derives the column it stores (F-45), and
                // spelled out at both ends rather than left to agree by coincidence — the same
                // reason `envelopeVersion` above is passed explicitly at both ends. If these two
                // derivations ever diverge, the row is hashed over one coarse actor and stores
                // another, which `verifyIntegrity()` reports as an invalid chain hash.
                actorRawValue: (receipt.actorDetail?.coarseActor ?? receipt.actor).rawValue,
                actorColumns: ReceiptActorColumns(receipt.actorDetail),
                authorityColumns: ReceiptAuthorityColumns(receipt.authorityDetail),
                // Derived from the draft through the same accessor `StoredReceipt.init` takes its
                // columns from, so the hashed values and the stored columns cannot disagree — the
                // discipline this function already applies to the coarse actor, the account address,
                // the chain scope and the envelope version.
                contributionColumns: receipt.contributionColumns,
                modeRawValue: receipt.mode.rawValue,
                trigger: receipt.trigger,
                scope: receipt.scope,
                summary: receipt.summary,
                provenance: receipt.provenance,
                isSuccess: receipt.isSuccess,
                correlationID: receipt.correlationID,
                accountAddress: accountAddress,
                chainRawValue: chainRawValue,
                payloadHash: payloadHash,
                signerPublicKey: signerPublicKey,
                previousReceiptHash: previousReceiptHash
            )
            // A new receipt must never enter the ledger without its provenance signature. Legacy
            // unsigned rows remain readable for migration, but signing failure is a write failure.
            let chainSignature = try await signer.sign(chainHash)
            storedReceipt = try StoredReceipt(
                id: receiptID,
                sequenceID: nextSequenceID,
                createdAt: receipt.createdAt,
                actor: receipt.actor,
                actorDetail: receipt.actorDetail,
                authorityDetail: receipt.authorityDetail,
                mode: receipt.mode,
                trigger: receipt.trigger,
                scope: receipt.scope,
                summary: receipt.summary,
                provenance: receipt.provenance,
                isSuccess: receipt.isSuccess,
                correlationID: receipt.correlationID,
                // The resolved values, not the draft's raw ones: these are the strings the chain hash
                // above committed to, and `verifyIntegrity()` re-hashes whatever lands in the row.
                timelineAccountAddress: accountAddress,
                timelineChainRawValue: chainRawValue,
                accountSequenceID: accountSequenceID,
                payloadHash: payloadHash,
                previousReceiptHash: previousReceiptHash,
                chainHash: chainHash,
                signature: chainSignature.signature.base64EncodedString(),
                // The same string the chain hash committed to, not the one the signature happens to
                // carry back, so the stored column and the hashed envelope cannot disagree.
                signerPublicKey: signerPublicKey,
                // The same value the hash above was taken over, for the reason stated where it is
                // bound: this column decides whether the hash is ever recomputed.
                integrityEnvelopeVersion: envelopeVersion,
                // The draft's own values, which is what `receipt.contributionColumns` above hashed.
                principal: receipt.principal,
                affectedResource: receipt.affectedResource,
                producedResult: receipt.producedResult,
                parentReceiptIDs: receipt.parentReceiptIDs,
                details: receipt.details
            )
        }

        // Rolled back on failure, like every other mutation here. Without the rollback, a throwing
        // save left the row registered as a pending insert: SwiftData fetches include unsaved
        // inserts, so the *next* append's `latestReceipt(accountKey:)` would chain off a row that is
        // not on disk and then re-attempt the same failed write — one row-specific failure
        // permanently breaking every later append in the process.
        //
        // Spelled out rather than routed through `performRollbackSafeMutation`, which is what the
        // paths below use: `ModelContext.insert` takes the model as `sending`, so calling it inside
        // that helper's closure hands the row to a captured region and the later uses of
        // `storedReceipt` here become a region-isolation error. Same work, same rollback.
        modelContext.insert(storedReceipt)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
        do {
            try await integrityHeadStore.saveHead(chainHash, for: accountKey)
        } catch let headStoreError {
            do {
                #if DEBUG
                // The only way to reach the compensation-failure branch below from a test. It needs a
                // `ModelContext` whose `save()` throws while the container is otherwise healthy,
                // which an in-memory container will not do — and the branch's outcome is the one
                // state this package documents as degraded integrity (a row on disk with no anchor),
                // so leaving it permanently unexecuted was the wrong trade.
                if let failure = compensationFailureForTesting {
                    throw failure
                }
                #endif
                try modelContext.performRollbackSafeMutation {
                    modelContext.delete(storedReceipt)
                }
            } catch let rollbackError {
                throw ReceiptPersistenceConsistencyError.appendCompensationFailed(
                    headStoreError: headStoreError.localizedDescription,
                    receiptRollbackError: rollbackError.localizedDescription
                )
            }
            throw headStoreError
        }
        // **The mark may be raised, but minted only over a ledger that had no rows.**
        //
        // This is the difference between a mark that is evidence and a mark that is a restatement of
        // whatever rows happen to be present. Writing `nextSequenceID` unconditionally looked right —
        // it is the sequence this append really did allocate — but when the mark is absent that value
        // is itself derived from the surviving rows, so the write laundered exactly the deletion the
        // mark exists to record: erase an account plus its anchor plus the mark, and the *next
        // ordinary append* re-minted a mark agreeing with the survivors and the ledger read
        // `.verified` with `isFullyAttested == true` again, in the signed archive too. One append, and
        // a wallet's missing history was certified complete. `verifyIntegrity()` refuses the same
        // write for the same reason; this is that refusal on the write path.
        //
        // An empty ledger is the one safe case to mint from: there is nothing to have truncated, and
        // it is what a fresh install and a post-`resetAll()` ledger both look like.
        //
        // The cost, stated rather than glossed: a process killed between the anchor write and this one
        // on a brand-new ledger's very first append leaves rows with no mark, and no later append will
        // mint one — so completeness reads as unconfirmed until `resetAll()`. That is `.unattested`,
        // which still exports, and it is the right side to err on. The alternative is a mark that can
        // be conjured out of whatever survived a deletion.
        // Recorded before the mark, and unconditionally — unlike the mark, which is gated above.
        //
        // The gate exists because the mark's value is derived from the surviving rows, so minting one
        // could launder a deletion. This value is a constant of the running build
        // (`ReceiptIntegrityEnvelopeVersion.current`) and is derived from nothing an attacker
        // controls, so there is no equivalent risk — and leaving it unwritten is what *weakens* the
        // ledger: an absent floor is the permissive case, which is precisely the state the version
        // bypass needed. See ``ReceiptIntegrityHeadStoring/loadHighestEnvelopeVersion()``.
        //
        // Non-fatal, like the mark and for the same reason: the row and its anchor are already
        // committed, so throwing here would report a write failure for a receipt that exists and
        // invite a retry that appends it twice. A failure leaves the floor low, which costs a future
        // downgrade a false `.tampered` — never a missed forgery, since a low floor is *stricter*.
        do {
            try await integrityHeadStore.saveHighestEnvelopeVersion(
                ReceiptIntegrityEnvelopeVersion.current
            )
        } catch {
            Self.logger.error(
                "Receipt integrity envelope-version floor could not be recorded at \(ReceiptIntegrityEnvelopeVersion.current, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }

        let mayWriteMark: Bool
        switch markState {
        case .known:
            mayWriteMark = true
        case .absent, .unreadable:
            mayWriteMark = allocation.ledgerWasEmpty
        }
        guard mayWriteMark else {
            Self.logger.error(
                "Receipt ledger high-water mark is \(markState.diagnosticDescription, privacy: .public) over a non-empty ledger; leaving it alone rather than deriving one from the surviving rows. Completeness stays unconfirmed until this ledger is reset."
            )
            return storedReceipt.asReceiptRecord()
        }

        // Last, and deliberately not fatal.
        //
        // The mark is what makes a deleted *suffix* of the ledger detectable, so it has to be durable
        // — but it is a third durable write after the row and the anchor, and every ordering has a
        // failure that lands somewhere. This one is chosen so the only reachable inconsistency is the
        // harmless direction:
        //
        // - Advancing it *before* the row would let a failed append (a signer that cannot sign, a
        //   throwing save) leave the mark ahead of the rows, which reads as "the ledger is missing a
        //   receipt" — a false accusation against a ledger nobody touched, and a durable one for an
        //   install that never appends again.
        // - Throwing from here would report a write failure for a receipt that is already committed
        //   with its anchor. The caller's only sensible response is to retry, which appends the
        //   receipt a second time.
        //
        // Leaving it behind instead is the same shape as the crash window the anchor check already
        // tolerates: `verifyIntegrity()` treats a stale-low mark as innocent and advances it, and the
        // next successful append raises it regardless. What it costs, stated plainly: between this
        // failure and the next append-or-verify, a deletion down to the mark's stale value would not
        // be reported. That window needs a Keychain write failure and a deletion inside it, and the
        // alternatives above are wrong on ledgers where nothing failed at all.
        do {
            try await integrityHeadStore.saveLedgerHighWaterMark(nextSequenceID)
        } catch {
            Self.logger.error(
                "Receipt ledger high-water mark could not be advanced to \(nextSequenceID, privacy: .public); completeness checking is degraded until the next append or verify: \(error.localizedDescription, privacy: .public)"
            )
        }

        // Last of all, and off-device. Published on every append so the window the witness cannot
        // vouch for stays one receipt wide — see ``publishWitnessCheckpoint(highestVerifiedSequenceID:chainHeads:recordCount:)``
        // for why a failure here is a logged advisory rather than a thrown error.
        //
        // The heads are taken from the rows now on disk rather than from this append alone, because a
        // checkpoint that named only the account just written would tell the witness nothing about the
        // others — and "this account is gone" is one of the three things the witness exists to catch.
        await publishWitnessCheckpoint(
            highestVerifiedSequenceID: nextSequenceID,
            chainHeads: try currentChainHeads(),
            recordCount: try modelContext.fetchCount(FetchDescriptor<StoredReceipt>())
        )
        return storedReceipt.asReceiptRecord()
    }

    /// The Phase 1 parent-receipt contract, enforced at the one point it can be: before the write.
    ///
    /// Three rules, and each is refused rather than normalized because a receipt is an append-only,
    /// hashed, immutable fact — there is no repairing a false causal claim once it has been signed.
    ///
    /// - **No duplicates.** Naming the same cause twice states nothing the single listing does not.
    /// - **No self-reference.** Checked here against the supplied list rather than against the id this
    ///   append is about to mint. A freshly minted `UUID` cannot collide with anything, so checking it
    ///   there would be vacuous; what *can* carry a self-reference is a hand-built archive, and
    ///   ``ReceiptProvenanceVerifier`` applies the rule to those. `ReceiptContributionParents.problems`
    ///   is given no `receiptID` for that reason, and the duplicate rule is the half that bites here.
    /// - **Parents must already exist in this store.** A dangling parent is a causal claim about
    ///   something the ledger cannot show ever happened, which is exactly the sort of unfalsifiable
    ///   assertion the rest of this package goes to lengths to keep out of the hash.
    ///
    /// Safe as a plain existence check only because the caller holds the ledger lock: `resetAll()` and
    /// any other append are serialized behind it, so a parent that exists when this runs still exists
    /// when the row is written. See ``withLedgerLock(_:_:)``.
    ///
    /// The contract is deliberately *not* enforced at verify time as a verdict. A parent can stop
    /// existing afterwards — a `resetAll()` is one way, a deleted row another — and calling that
    /// tampering would brand a ledger for something the rows cannot attribute. `verifyIntegrity()`
    /// reports a dangling parent as an unattested reason instead, which is the same line this package
    /// draws for a sequence hole.
    private func validateParentReceipts(_ parentReceiptIDs: [UUID]) throws {
        guard parentReceiptIDs.isEmpty == false else { return }

        let problems = ReceiptContributionParents.problems(parentReceiptIDs)
        guard problems.isEmpty else {
            throw ReceiptParentContractError.invalidParents(reasons: problems)
        }

        for parentReceiptID in parentReceiptIDs {
            let id = parentReceiptID
            let existing = try modelContext.fetchCount(
                FetchDescriptor<StoredReceipt>(predicate: #Predicate<StoredReceipt> { $0.id == id })
            )
            guard existing > 0 else {
                throw ReceiptParentContractError.unknownParent(parentReceiptID)
            }
        }
    }

    /// Every account's tip, for a witness checkpoint.
    ///
    /// Reads the rows rather than tracking heads incrementally: the append path already holds the
    /// ledger lock, and a checkpoint assembled from anything other than what is actually on disk is
    /// precisely the kind of second, racing read the lock exists to prevent.
    private func currentChainHeads() throws -> [ReceiptProvenanceChainHead] {
        var tips: [String: StoredReceipt] = [:]
        for receipt in try modelContext.fetch(FetchDescriptor<StoredReceipt>())
        where receipt.hasCompleteIntegrityMetadata {
            if receipt.isNewerIntegrityHead(than: tips[receipt.accountKey]) {
                tips[receipt.accountKey] = receipt
            }
        }
        return tips
            .map {
                ReceiptProvenanceChainHead(
                    accountKey: $0.key,
                    accountSequenceID: $0.value.accountSequenceID,
                    chainHash: $0.value.chainHash
                )
            }
            .sorted { $0.accountKey < $1.accountKey }
    }

    /// Queued behind in-flight appends for the same reason they are queued behind each other: this
    /// clears the trusted heads and then deletes the rows, so an append interleaving between those
    /// two steps would leave a receipt whose head was wiped — reported forever after as "persisted
    /// receipts without protected heads".
    public func resetAll() async throws {
        try await withLedgerLock(.resetAll) { [self] in
            try await performResetAll()
        }
    }

    /// Rows first, anchors second — the opposite of the original order, and the ordering is the whole
    /// point.
    ///
    /// Clearing the anchors first meant the *first* step destroyed the durable half of the invariant.
    /// If the row delete then failed, the compensation restored heads derived from the rows rather
    /// than the values the Keychain actually held; if `clearAllHeads()` itself threw part-way — a
    /// partial `SecItemDelete`, `errSecInteractionNotAllowed` — there was no compensation at all, and
    /// the process died holding every row with no anchor. `verifyIntegrity()` reports that as
    /// `.invalid("persisted receipts without protected heads")` for every account this device wrote,
    /// forever, and the only way out was another `resetAll()` — destroying the history, the exact
    /// outcome the `Status` contract exists to avoid.
    ///
    /// In this order each failure lands on a consistent state:
    /// - the row delete throws → nothing was touched; rows and anchors still agree.
    /// - `clearAllHeads()` throws → rows are gone and some anchors survive. `verifyIntegrity()` calls
    ///   that `.invalid` too, but it is *recoverable*: this method clears heads unconditionally, so
    ///   simply running the reset again finishes the job.
    private func performResetAll() async throws {
        let receipts = try modelContext.fetch(FetchDescriptor<StoredReceipt>())

        try modelContext.performRollbackSafeMutation {
            for receipt in receipts {
                modelContext.delete(receipt)
            }
        }
        try await integrityHeadStore.clearAllHeads()

        // Re-recorded immediately, because `clearAllHeads()` takes the envelope-version floor with it
        // and an *absent* floor is the permissive state, not a neutral one.
        //
        // Clearing it looked harmless — no rows survive a reset, so no row needs vouching for — but it
        // left a window between the reset and the next append in which a row planted with a raised
        // version column had nothing to bound it, and a `chainHash`/`signature` pair captured from a
        // pre-reset row is unique in the now-empty ledger so ``ReceiptChainHashUniqueness`` does not
        // fire either. Restoring the floor closes the window without keeping any pre-reset state: the
        // value is a constant of this build, not anything derived from the history just deleted.
        //
        // Non-fatal, like the append path's write and for the same reason: the rows and anchors are
        // already gone, so throwing here would report a failure for a reset that has happened. A
        // failure leaves the floor absent, which is exactly the state this line improves on and never
        // worse than it was.
        do {
            try await integrityHeadStore.saveHighestEnvelopeVersion(
                ReceiptIntegrityEnvelopeVersion.current
            )
        } catch {
            Self.logger.error(
                "Receipt integrity envelope-version floor could not be re-recorded after a reset: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    public func latest(limit: Int) throws -> [ReceiptRecord] {
        guard limit > 0 else {
            return []
        }

        var descriptor = FetchDescriptor<StoredReceipt>(
            sortBy: [
                SortDescriptor(\StoredReceipt.createdAt, order: .reverse),
                SortDescriptor(\StoredReceipt.sequenceID, order: .reverse)
            ]
        )
        descriptor.fetchLimit = limit

        return try modelContext.fetch(descriptor).map { $0.asReceiptRecord() }
    }

    public func receipts(
        forCorrelationID correlationID: String,
        limit: Int
    ) throws -> [ReceiptRecord] {
        guard limit > 0 else {
            return []
        }

        let correlationValue = correlationID
        var descriptor = FetchDescriptor<StoredReceipt>(
            predicate: #Predicate<StoredReceipt> { receipt in
                receipt.correlationID == correlationValue
            },
            sortBy: [
                SortDescriptor(\StoredReceipt.createdAt, order: .reverse),
                SortDescriptor(\StoredReceipt.sequenceID, order: .reverse)
            ]
        )
        descriptor.fetchLimit = limit

        return try modelContext.fetch(descriptor).map { $0.asReceiptRecord() }
    }

    /// The whole ledger as a plain read: one fetch, no verification, no signing, no JSON round trip.
    ///
    /// Exists because the console was reading history through ``exportAll()``, which made every
    /// Mission Control open verify every signature in the store and then decode its own export.
    public func allRecords() throws -> [ReceiptRecord] {
        let descriptor = FetchDescriptor<StoredReceipt>(
            sortBy: [
                SortDescriptor(\StoredReceipt.createdAt, order: .reverse),
                SortDescriptor(\StoredReceipt.sequenceID, order: .reverse)
            ]
        )
        return try modelContext.fetch(descriptor).map { $0.asReceiptRecord() }
    }

    /// What this device can currently say about the ledger high-water mark.
    ///
    /// Three cases rather than an `Int?`, because the append path licenses different writes for each
    /// and collapsing the last two into `nil` is how a deletion became indistinguishable from a fresh
    /// ledger.
    private enum LedgerHighWaterMarkState {
        /// No mark item exists: a fresh install, a ledger just reset, a store restored without its
        /// `ThisDeviceOnly` items — or one an attacker deleted the mark from.
        case absent
        /// A mark this device read and trusts as a floor.
        case known(Int)
        /// The item exists but does not decode, so it is neither a usable floor nor safely absent.
        case unreadable(String)

        /// The value allocation may treat as a floor. `nil` for both failure cases: neither licenses
        /// inventing one, and a floor guessed from the rows is precisely the laundering to avoid.
        var usableFloor: Int? {
            if case let .known(value) = self { return value }
            return nil
        }

        var diagnosticDescription: String {
            switch self {
            case .absent: return "absent"
            case let .known(value): return "\(value)"
            case let .unreadable(reason): return "unreadable (\(reason))"
            }
        }
    }

    private func loadLedgerHighWaterMarkState() async -> LedgerHighWaterMarkState {
        do {
            guard let mark = try await integrityHeadStore.loadLedgerHighWaterMark() else {
                return .absent
            }
            return .known(mark)
        } catch {
            return .unreadable(error.localizedDescription)
        }
    }

    /// One past the furthest this ledger has ever got, plus whether it had any rows at all.
    ///
    /// **Taking the mark into account is what makes a deletion permanent, and it is the strongest
    /// thing the mark buys.** Everything else the mark does is advisory; this is not. Allocating above
    /// it means a deletion's freed sequence IDs are never reissued, so the gap they leave becomes an
    /// *interior hole* — which ``ReceiptIntegrity/sequenceGapReasons(sequenceIDs:)`` reads from the
    /// rows alone, with no Keychain state involved and nothing an attacker can roll back afterwards.
    /// A suffix deletion is converted into row-derived, verdict-affecting evidence.
    ///
    /// Allocating from the surviving rows instead reissued every number a deletion had freed, so
    /// `count` climbed back to meet `highest` and every trace closed — after as many ordinary appends
    /// as there were deleted receipts, nothing anywhere recorded that anything had gone. That needed
    /// no Keychain access at all: ordinary continued use erased the evidence.
    ///
    /// On an honest ledger the mark and the rows agree, so this changes no allocation anybody sees.
    ///
    /// - Parameter ledgerHighWaterMark: A floor this device actually read, or `nil` when the mark is
    ///   absent or unreadable. With `nil` this falls back to the rows, so **an ID freed by a deletion
    ///   can still be reissued in that state** — a Keychain that cannot be read must not block
    ///   receipt writes, and there is no honest floor to use instead.
    ///
    ///   That reuse is tolerable only because of what the caller does with it: with no readable mark,
    ///   ``performAppend(_:)`` writes no mark either (unless the ledger was empty), so the advisory
    ///   keeps reporting completeness as unconfirmed rather than being silenced by a freshly minted
    ///   mark that agrees with the reissued rows.
    ///
    ///   An earlier version of this note claimed the fallback was near-unreachable because "a device
    ///   that cannot read the mark cannot sign either". That was wrong twice over:
    ///   ``DeviceReceiptSigner`` caches its resolved identity, so signing touches no Keychain after
    ///   the first resolution, and a mark that fails to *decode* fails this read while the anchor
    ///   service stays perfectly healthy.
    private func nextSequenceIDAllocation(
        notBelow ledgerHighWaterMark: Int?
    ) throws -> (sequenceID: Int, ledgerWasEmpty: Bool) {
        var descriptor = FetchDescriptor<StoredReceipt>(
            sortBy: [SortDescriptor(\StoredReceipt.sequenceID, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        let highestRow = try modelContext.fetch(descriptor).first
        let highestOnDisk = highestRow?.sequenceID ?? 0
        // Overflow-checked, because `+ 1` on this is a *trap*, not a wrong answer.
        //
        // Both inputs are attacker-writable — the column by anyone who can write the row store, the
        // mark by anyone who can write the Keychain — and neither is validated before this point, so
        // one row edited to `Int.max` made every later append overflow and kill the process. Measured:
        // `SIGTRAP`, permanently, from SwiftData write access alone. A corrupted or forged column has
        // to produce a verdict or an error, never an abort; that principle is already applied to
        // unencodable columns on the verify path, and this was the same hole on the write path.
        let ceiling = max(highestOnDisk, ledgerHighWaterMark ?? 0)
        let (nextSequenceID, ceilingOverflowed) = ceiling.addingReportingOverflow(1)
        guard !ceilingOverflowed else {
            throw ReceiptPersistenceConsistencyError.sequenceAllocationOutOfRange(highest: ceiling)
        }
        // Emptiness from the *absence of a row*, not from `highestOnDisk == 0`.
        //
        // `ledgerWasEmpty` is the sole licence the caller has to mint a mark when none is readable,
        // which is the anti-laundering condition the whole truncation mechanism rests on — so it must
        // not rest on a sentinel collision in turn. A row carrying `sequenceID <= 0` made a non-empty
        // ledger report empty. Not reachable today (that column is inside the chain hash, and
        // `sequenceGapReasons` rejects non-positive IDs outright), which is exactly why it was worth
        // fixing while it is still cheap: a load-bearing guard should be true by construction.
        return (nextSequenceID, highestRow == nil)
    }

    /// The row a new receipt for this account should chain off.
    ///
    /// Predicated on ``StoredReceipt/accountKey`` — the same value ``verifyIntegrity()`` groups by —
    /// rather than on `accountAddress`. Those are different functions (the key folds `nil` and `""`
    /// together and lowercases the rest), and using one to pick the predecessor while using the other
    /// to verify the result forked the chain: two drafts whose addresses share a key each started at
    /// `accountSequenceID == 1` off the genesis hash, and `verifyIntegrity()` merged them and reported
    /// `.tampered` for good.
    ///
    /// Safe as a bare equality only because `backfillAccountKeysIfNeeded()` has already run: a row
    /// still carrying the column's `""` default would match nothing here and fork its own chain.
    private func latestReceipt(accountKey: String) throws -> StoredReceipt? {
        let key = accountKey
        var descriptor = FetchDescriptor<StoredReceipt>(
            predicate: #Predicate<StoredReceipt> { receipt in
                receipt.accountKey == key
            },
            sortBy: [
                SortDescriptor(\StoredReceipt.accountSequenceID, order: .reverse),
                SortDescriptor(\StoredReceipt.sequenceID, order: .reverse)
            ]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// Fills in ``StoredReceipt/accountKey`` for rows written before that column existed, once per
    /// store, before anything reads it.
    ///
    /// A migration rather than a read-time fallback, because a fallback cannot be pushed into a
    /// `#Predicate`. The first attempt at this kept the derivation as a computed property and had the
    /// append path match legacy rows with `accountKey == "" && accountAddress == <raw address>` — but
    /// the derivation *folds* `nil`/`""` into `"global"` and lowercases, and raw equality expresses
    /// neither. A pre-column row stored under the literal address `"global"` then matched no
    /// predecessor at all: the next unattributed append restarted at `accountSequenceID == 1` off the
    /// genesis hash, `verifyIntegrity()` grouped the two together, and the ledger read `.tampered`
    /// permanently — the exact failure the column was added to remove.
    ///
    /// Writing the derived value instead makes the stored column the single answer everywhere, and it
    /// changes no hash: `accountKey` is not in the hashed envelope, and `accountAddress`, which is,
    /// is not touched.
    func backfillAccountKeysIfNeeded() throws {
        guard !didBackfillAccountKeys else { return }

        let unkeyed = try modelContext.fetch(
            FetchDescriptor<StoredReceipt>(
                predicate: #Predicate<StoredReceipt> { $0.accountKey == "" }
            )
        )
        guard !unkeyed.isEmpty else {
            didBackfillAccountKeys = true
            return
        }

        try modelContext.performRollbackSafeMutation {
            for receipt in unkeyed {
                receipt.accountKey = receipt.derivedAccountKey
            }
        }
        // Only after the write commits: a throw above leaves the flag clear so the next caller
        // retries, rather than proceeding over rows the predicates cannot see.
        didBackfillAccountKeys = true
    }
}

public final class SwiftDataReceiptStore: ReceiptStore, ReceiptProvenanceTrustAnchorProviding {
    private let persistenceStore: ReceiptPersistenceStore

    /// Takes no `ModelContext`: every read and write goes through `persistenceStore`, which owns its
    /// own context off the container it was built with. The parameter this used to accept was never
    /// read, so passing a context other than that one looked like it selected the store's backing
    /// context and in fact did nothing.
    public init(persistenceStore: ReceiptPersistenceStore) {
        self.persistenceStore = persistenceStore
    }

    /// A self-contained store for tests and previews: integrity anchors live in memory and the
    /// signing identity is a throwaway, so nothing here outlives the instance. Not a production
    /// seam — the in-memory head store already rules that out, and the ephemeral signer is passed
    /// explicitly so it reads as the deliberate choice it is rather than a defaulted one.
    public convenience init(modelContext: ModelContext) {
        self.init(
            persistenceStore: ReceiptPersistenceStore(
                modelContainer: modelContext.container,
                integrityHeadStore: InMemoryReceiptIntegrityHeadStore(),
                signer: ReceiptSignerFactory.ephemeralSigner()
            )
        )
    }

    public func append(_ receipt: ReceiptDraft) async throws -> ReceiptRecord {
        try await persistenceStore.append(receipt)
    }

    public func latest(limit: Int) async throws -> [ReceiptRecord] {
        try await persistenceStore.latest(limit: limit)
    }

    public func receipts(
        forCorrelationID correlationID: String,
        limit: Int
    ) async throws -> [ReceiptRecord] {
        try await persistenceStore.receipts(
            forCorrelationID: correlationID,
            limit: limit
        )
    }

    public func allRecords() async throws -> [ReceiptRecord] {
        try await persistenceStore.allRecords()
    }

    public func exportAll() async throws -> Data {
        try await persistenceStore.exportAll()
    }

    public func provenanceTrustAnchor() async throws -> ReceiptProvenanceTrustAnchor {
        try await persistenceStore.provenanceTrustAnchor()
    }

    public func resetAll() async throws {
        try await persistenceStore.resetAll()
    }

    public func verifyIntegrity() async throws -> ReceiptIntegrityVerificationResult {
        try await persistenceStore.verifyIntegrity()
    }

    /// Bridges the full verification verdict onto the `ReceiptStore` seam so a trust surface can read
    /// it without going through `exportAll()`'s refusal.
    public func ledgerAttestation() async throws -> ReceiptLedgerAttestation? {
        try await verifyIntegrity().ledgerAttestation
    }
}

public extension ReceiptIntegrityVerificationResult {
    /// The dependency-free projection of this verdict, for callers that only have `ReceiptsCore`.
    ///
    /// Maps one-to-one and carries ``completenessAdvisory`` through, because a surface that cares
    /// about removed rows has to show the advisory *alongside* the status rather than instead of it.
    var ledgerAttestation: ReceiptLedgerAttestation {
        let mapped: ReceiptLedgerAttestation.Status =
            switch status {
            case .verified: .verified
            case .unattested: .unattested
            case .tampered: .tampered
            }
        return ReceiptLedgerAttestation(
            status: mapped,
            failureReason: failureReason,
            completenessAdvisory: completenessAdvisory
        )
    }
}

@MainActor
public enum ReceiptStores {
    /// Both caches are keyed by the `ModelContainer`, never by the `ModelContext` a caller happens to
    /// hand in.
    ///
    /// Keying on the context was unsound twice over. Nothing here retained it — the store keeps only
    /// the `ReceiptPersistenceStore`, which retains the *container* — so a context could be
    /// deallocated while its entry lived on, and a later context allocated at the same address
    /// inherited the dead one's store, possibly over a different container entirely. And because
    /// ``ReceiptPersistenceStore`` was already memoized per container, two contexts over one
    /// container produced two `SwiftDataReceiptStore` facades; harmless only because they shared the
    /// one actor underneath, which is the thing the ledger lock lives on.
    ///
    /// The container key is sound for the reason the context key was not: the cached value transitively
    /// retains the container, so its `ObjectIdentifier` cannot be reused by a different object while
    /// the entry exists. That is also why nothing is ever evicted — an entry keeps its own key alive,
    /// so eviction would have to be driven from outside. A process holds one primary container, so the
    /// unbounded growth only shows up in test processes that build a container per case.
    private static var cachedStores: [ObjectIdentifier: SwiftDataReceiptStore] = [:]
    private static var cachedPersistenceStores: [ObjectIdentifier: ReceiptPersistenceStore] = [:]

    /// The CloudKit container that backs the external witness, or `nil` to run without one.
    ///
    /// **Opt-in, and off by default, because turning it on is not this package's decision to make.**
    /// Naming a container requires the app to carry an `iCloud` entitlement listing it and to have
    /// that container provisioned; a build without both cannot use CloudKit at all. Defaulting it on
    /// would either abort the process (see ``CloudKitReceiptLedgerWitness/init(containerIdentifier:)``)
    /// or spend a network round trip per append to learn that it cannot work.
    ///
    /// Left `nil`, verification behaves exactly as it did before the witness existed, plus one
    /// advisory saying the ledger is unwitnessed. Set it once at launch, before the first receipt
    /// store is built, to enable the real thing:
    ///
    /// ```swift
    /// ReceiptStores.witnessCloudKitContainerIdentifier = "iCloud.com.example.Auralis"
    /// ```
    ///
    /// Read once per `ModelContainer`, since the stores below are memoized — changing it afterwards
    /// does not re-make a store that already exists.
    public static var witnessCloudKitContainerIdentifier: String?

    private static func makeWitness() -> any ReceiptLedgerWitnessing {
        guard let identifier = witnessCloudKitContainerIdentifier else {
            return UnconfiguredReceiptLedgerWitness()
        }
        return CloudKitReceiptLedgerWitness(containerIdentifier: identifier)
    }

    public static func live(modelContext: ModelContext) -> any ReceiptStore {
        let key = ObjectIdentifier(modelContext.container)
        if let cachedStore = cachedStores[key] {
            return cachedStore
        }

        let store = SwiftDataReceiptStore(
            persistenceStore: persistenceStore(for: modelContext)
        )
        cachedStores[key] = store
        return store
    }

    static func persistenceStore(for modelContext: ModelContext) -> ReceiptPersistenceStore {
        let key = ObjectIdentifier(modelContext.container)
        if let cachedPersistenceStore = cachedPersistenceStores[key] {
            return cachedPersistenceStore
        }

        let newPersistenceStore = ReceiptPersistenceStore(
            modelContainer: modelContext.container,
            integrityHeadStore: KeychainReceiptIntegrityHeadStore(),
            signer: ReceiptSignerFactory.deviceSigner(),
            witness: makeWitness()
        )
        cachedPersistenceStores[key] = newPersistenceStore
        return newPersistenceStore
    }
}

extension StoredReceipt {
    var hasCompleteIntegrityMetadata: Bool {
        !payloadHash.isEmpty
            && !previousReceiptHash.isEmpty
            && !chainHash.isEmpty
    }

    func isNewerIntegrityHead(than current: StoredReceipt?) -> Bool {
        guard let current else {
            return true
        }

        return accountSequenceID > current.accountSequenceID
            || (
                accountSequenceID == current.accountSequenceID
                && sequenceID > current.sequenceID
            )
    }
}

extension ReceiptIntegrity {
    /// ``chainHash(for:)``, or `nil` when the row declares an envelope version this build does not
    /// implement and therefore cannot reproduce.
    ///
    /// Separate from ``chainHash(for:)`` rather than folded into it because the two callers want
    /// different things: the integrity check has to tell "cannot verify" apart from "does not match",
    /// while a test that mutates columns and needs the row to stay chain-consistent is always working
    /// at the current version and wants the value or a throw.
    ///
    /// **A `nil` from here is not a licence to accept the row.** It only says this build cannot judge
    /// it, and the version column that produced the `nil` is itself part of the row — so the caller
    /// has to corroborate it against state an attacker with row-store access cannot write. See the
    /// envelope-version floor on ``ReceiptIntegrityHeadStoring/loadHighestEnvelopeVersion()``, which
    /// exists because the unbounded version of that concession was a complete bypass of this check.
    static func chainHash(forVerifiable receipt: StoredReceipt) throws -> String? {
        guard receipt.integrityEnvelopeVersion <= ReceiptIntegrityEnvelopeVersion.current else {
            return nil
        }
        return try chainHash(for: receipt)
    }

    /// The chain hash a persisted row should carry, derived entirely from that row's stored columns.
    ///
    /// Shared by ``ReceiptPersistenceStore/verifyIntegrity()`` and by tests that mutate the signing
    /// columns and need the row to stay chain-consistent, so neither can drift from the envelope the
    /// append path commits to.
    static func chainHash(for receipt: StoredReceipt) throws -> String {
        try chainHash(
            receiptID: receipt.id,
            envelopeVersion: receipt.integrityEnvelopeVersion,
            sequenceID: receipt.sequenceID,
            accountSequenceID: receipt.accountSequenceID,
            createdAt: receipt.createdAt,
            actorRawValue: receipt.actorRawValue,
            // The raw columns, not the reconstructed details — see ``StoredReceipt/actorColumns``.
            actorColumns: receipt.actorColumns,
            authorityColumns: receipt.authorityColumns,
            contributionColumns: receipt.contributionColumns,
            modeRawValue: receipt.modeRawValue,
            trigger: receipt.trigger,
            scope: receipt.scope,
            summary: receipt.summary,
            provenance: receipt.provenance,
            isSuccess: receipt.isSuccess,
            correlationID: receipt.correlationID,
            accountAddress: receipt.accountAddress,
            chainRawValue: receipt.chainRawValue,
            payloadHash: receipt.payloadHash,
            signerPublicKey: receipt.signerPublicKey,
            previousReceiptHash: receipt.previousReceiptHash
        )
    }
}
