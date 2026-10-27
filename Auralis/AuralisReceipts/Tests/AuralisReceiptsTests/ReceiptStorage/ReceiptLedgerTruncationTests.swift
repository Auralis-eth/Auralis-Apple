import Foundation
@testable import AuralisReceipts
import AuralisRuntime
import SwiftData
import Testing

/// Suffix truncation — deleting whatever was written *last* — and the high-water mark that reports
/// it, **as an advisory rather than a verdict.**
///
/// The two halves of completeness are deliberately separated, and most of what these tests pin is
/// which half a given deletion lands in:
///
/// - **Row-derived** — duplicate `sequenceID`s and interior holes. Visible in a single fetch with no
///   durable state outside the rows, so it moves the verdict to `.unattested`
///   (``ReceiptIntegrity/sequenceGapReasons(sequenceIDs:)``).
/// - **Mark-derived** — a deleted *suffix*, which the rows cannot show because the survivors are
///   still a contiguous `1...k`. Only the high-water mark can see it, and the mark is an
///   unauthenticated Keychain item whose absence is equally uninformative, so it reports through
///   ``ReceiptIntegrityVerificationResult/completenessAdvisory`` and leaves `status` and
///   `isFullyAttested` alone.
///
/// The consequence to be clear-eyed about, and the reason these tests read the way they do: a
/// *sequential* whole-account deletion reads `.verified` with an advisory attached. That is a
/// deliberate decision — the mark cannot be made into a control (see
/// ``ReceiptIntegrity/completenessAdvisory(sequenceIDs:highWaterMark:completenessUnconfirmed:)``),
/// and pretending otherwise dressed a heuristic up as a guarantee while its absence penalised honest
/// restored ledgers. An *interleaved* deletion leaves an interior hole and is still `.unattested`.
@MainActor
struct ReceiptLedgerTruncationTests {
    private static let accountA = "0x1111111111111111111111111111111111111111"
    private static let accountB = "0x2222222222222222222222222222222222222222"

    // MARK: - Suffix deletion: advisory, not verdict

    /// Written sequentially, not interleaved, and that is the whole point of the fixture.
    ///
    /// The pre-existing regression test for "deleting an entire account" appends
    /// `a-0, b-0, a-1, b-1`, so excising B leaves an interior hole at sequence 2 and the old check
    /// caught it. Reordering the same fixture so the victim account is written *last* defeated it
    /// completely — the survivors are `1, 2` and nothing is left to notice.
    @Test("excising the account that holds the high-water mark raises an advisory")
    func excisingTheAccountHoldingTheHighWaterMarkRaisesAnAdvisory() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let store = try makeStore(context: context, headStore: headStore)

        for index in 0..<2 {
            _ = try await store.append(draft(kind: "a-\(index)", accountAddress: Self.accountA))
        }
        for index in 0..<2 {
            _ = try await store.append(draft(kind: "b-\(index)", accountAddress: Self.accountB))
        }
        #expect(try await store.verifyIntegrity().status == .verified)

        // Account B holds sequence 3 and 4 — the top of the ledger.
        let victims = try context.fetch(FetchDescriptor<StoredReceipt>())
            .filter { $0.accountKey == Self.accountB.lowercased() }
        #expect(victims.map(\.sequenceID).sorted() == [3, 4])
        for row in victims {
            context.delete(row)
        }
        try context.save()
        // And its anchor, so nothing is left dangling for the orphaned-head check to trip on.
        await headStore.clearHead(for: Self.accountB.lowercased())

        let result = try await store.verifyIntegrity()
        // The advisory names the deletion exactly, because the mark survived it.
        #expect(
            result.completenessAdvisory?.contains("suggests 2 were removed") == true,
            "\(result.completenessAdvisory ?? "-")"
        )
        // And the verdict is decided without it. The rows that remain are intact and this device
        // signed them, so that is what `status` says; the mark's observation travels alongside rather
        // than overriding it. See the type's doc for why the mark cannot carry a verdict.
        #expect(result.status == .verified, "\(result.failureReason ?? "-")")
        #expect(result.isFullyAttested)
        // Crucially the row-derived half stays silent here: the survivors *are* a contiguous 1...2,
        // which is exactly why this deletion needed the mark to be noticed at all.
        #expect(result.failureReason == nil)
    }

    /// The same erasure at the boundary that actually matters: the advisory has to cross into the
    /// signed archive, so a third party is told what the exporting device observed instead of taking
    /// the record set on faith.
    @Test("a truncated ledger's signed archive carries the advisory")
    func truncatedLedgerArchiveCarriesTheAdvisory() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let store = try makeStore(context: context, headStore: headStore)

        _ = try await store.append(draft(kind: "a-0", accountAddress: Self.accountA))
        for index in 0..<2 {
            _ = try await store.append(draft(kind: "b-\(index)", accountAddress: Self.accountB))
        }

        for row in try context.fetch(FetchDescriptor<StoredReceipt>())
            where row.accountKey == Self.accountB.lowercased() {
            context.delete(row)
        }
        try context.save()
        await headStore.clearHead(for: Self.accountB.lowercased())

        let anchor = try await store.provenanceTrustAnchor()
        let verified = try ReceiptProvenanceVerifier.verify(
            try await store.exportAll(),
            trustedSignerFingerprint: anchor.fingerprint
        )
        #expect(
            verified.completenessAdvisory?.contains("suggests 2 were removed") == true,
            "\(verified.completenessAdvisory ?? "-")"
        )
        #expect(verified.status == .verified, "\(verified.failureReason ?? "-")")
    }

    /// Wiping the rows wholesale. Distinguishable from a fresh install only because `resetAll()`
    /// clears the mark and a raw delete does not — so the mark is the only thing with anything to say.
    @Test("deleting every row while the mark survives raises an advisory")
    func deletingEveryRowRaisesAnAdvisory() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let store = try makeStore(context: context, headStore: headStore)

        for index in 0..<3 {
            _ = try await store.append(draft(kind: "row-\(index)", accountAddress: Self.accountA))
        }
        for row in try context.fetch(FetchDescriptor<StoredReceipt>()) {
            context.delete(row)
        }
        try context.save()
        await headStore.clearHead(for: Self.accountA.lowercased())

        let result = try await store.verifyIntegrity()
        #expect(
            result.completenessAdvisory?.contains("suggests 3 were removed") == true,
            "\(result.completenessAdvisory ?? "-")"
        )
    }

    /// The advisory must not be launderable by running the check twice.
    ///
    /// A stale *low* mark is healed forward, so the obvious-looking implementation heals the mark to
    /// whatever the rows now say — which would report once and then fall silent. The heal is
    /// one-directional for exactly this reason.
    @Test("the advisory persists on every later pass")
    func advisoryIsNotHealedAway() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let store = try makeStore(context: context, headStore: headStore)

        for index in 0..<3 {
            _ = try await store.append(draft(kind: "row-\(index)", accountAddress: Self.accountA))
        }
        let tail = try #require(
            try context.fetch(FetchDescriptor<StoredReceipt>()).max(by: { $0.sequenceID < $1.sequenceID })
        )
        context.delete(tail)
        try context.save()
        await headStore.saveHead(
            try #require(
                try context.fetch(FetchDescriptor<StoredReceipt>())
                    .max(by: { $0.sequenceID < $1.sequenceID })?.chainHash
            ),
            for: Self.accountA.lowercased()
        )

        #expect(try await store.verifyIntegrity().completenessAdvisory != nil)
        let second = try await store.verifyIntegrity()
        #expect(
            second.completenessAdvisory?.contains("suggests 1 were removed") == true,
            "the second pass laundered the deletion: \(second.completenessAdvisory ?? "-")"
        )
        #expect(await headStore.loadLedgerHighWaterMark() == 3, "the mark was walked backwards")
    }

    /// Reuse-prevention is what converts a suffix deletion into a *row-derived* interior hole, and so
    /// into a verdict rather than only an advisory. That makes it the most valuable thing the mark
    /// does, and the one part of the mechanism that is not merely advisory.
    ///
    /// `nextSequenceID()` used to allocate from the highest surviving *row*, so a deletion's freed
    /// numbers were handed straight back out: `count` climbed back to meet `highest` and every trace
    /// closed. Allocating above the mark instead leaves a permanent hole at the deleted IDs, which
    /// ``ReceiptIntegrity/sequenceGapReasons(sequenceIDs:)`` sees from the rows alone — no Keychain
    /// state required, and nothing an attacker can roll back afterwards.
    @Test("appending after a truncation leaves a permanent, row-derived hole")
    func appendingAfterTruncationLeavesARowDerivedHole() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let store = try makeStore(context: context, headStore: headStore)

        for index in 0..<5 {
            _ = try await store.append(draft(kind: "row-\(index)", accountAddress: Self.accountA))
        }

        // Delete the last two rows and repoint the anchor at the new tip, which is what the append
        // path itself would do on the next write — so the only thing left to notice is the count.
        let doomed = try context.fetch(FetchDescriptor<StoredReceipt>())
            .filter { $0.sequenceID >= 4 }
        for row in doomed {
            context.delete(row)
        }
        try context.save()
        let survivingTip = try #require(
            try context.fetch(FetchDescriptor<StoredReceipt>()).max(by: { $0.sequenceID < $1.sequenceID })
        )
        await headStore.saveHead(survivingTip.chainHash, for: survivingTip.accountKey)

        // Straight after the deletion only the mark has anything to say: the survivors are a
        // contiguous 1...3, so this is advisory-only.
        let detected = try await store.verifyIntegrity()
        #expect(detected.status == .verified, "\(detected.failureReason ?? "-")")
        #expect(
            detected.completenessAdvisory?.contains("suggests 2 were removed") == true,
            "\(detected.completenessAdvisory ?? "-")"
        )

        // Two ordinary appends — governed actions during normal use.
        _ = try await store.append(draft(kind: "later-1", accountAddress: Self.accountA))
        _ = try await store.append(draft(kind: "later-2", accountAddress: Self.accountA))

        let sequenceIDs = try context.fetch(FetchDescriptor<StoredReceipt>())
            .map(\.sequenceID)
            .sorted()
        #expect(sequenceIDs == [1, 2, 3, 6, 7], "the deleted sequence IDs were reissued: \(sequenceIDs)")

        // And now it is a verdict, permanently: 4 and 5 are a hole in the rows themselves, which no
        // later Keychain tampering can close.
        let after = try await store.verifyIntegrity()
        #expect(after.status == .unattested, "continued use laundered the deletion")
        #expect(after.isFullyAttested == false)
        #expect(after.failureReason?.contains("missing 2 of 7") == true, "\(after.failureReason ?? "-")")
    }

    /// Deleting the mark must not cause verification to *manufacture* one.
    ///
    /// The heal that advances a stale-low mark is necessary, but testing it against a mark that
    /// *exists* leaves the absent case uncovered — and treating absent as zero made the heal write a
    /// mark agreeing with the survivors. What that destroyed is the thing this test still protects:
    /// with no mark, the advisory says completeness is unconfirmed; with a manufactured one it says
    /// nothing at all, and the reuse-prevention above silently starts allocating from the truncated
    /// rows too.
    @Test("deleting the mark does not cause a mark to be manufactured")
    func deletedMarkIsNotHealedFromSurvivingRows() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let signer = SoftwareReceiptSigner()
        let store = try makeStore(context: context, headStore: headStore, signer: signer)

        for index in 0..<2 {
            _ = try await store.append(draft(kind: "a-\(index)", accountAddress: Self.accountA))
        }
        for index in 0..<2 {
            _ = try await store.append(draft(kind: "b-\(index)", accountAddress: Self.accountB))
        }

        // Account B's rows, B's anchor, and the mark — one Keychain delete more than the case above.
        for row in try context.fetch(FetchDescriptor<StoredReceipt>())
            where row.accountKey == Self.accountB.lowercased() {
            context.delete(row)
        }
        try context.save()
        let anchorsOnly = InMemoryReceiptIntegrityHeadStore()
        for row in try context.fetch(FetchDescriptor<StoredReceipt>()) {
            await anchorsOnly.saveHead(row.chainHash, for: row.accountKey)
        }
        let truncated = try makeStore(context: context, headStore: anchorsOnly, signer: signer)

        let first = try await truncated.verifyIntegrity()
        #expect(
            first.completenessAdvisory?.contains("no high-water mark") == true,
            "\(first.completenessAdvisory ?? "-")"
        )

        // The pass must not have written a mark derived from what survived.
        #expect(
            await anchorsOnly.loadLedgerHighWaterMark() == nil,
            "verification manufactured a high-water mark from the surviving rows"
        )

        // And it still says so on the second pass rather than falling silent.
        let second = try await truncated.verifyIntegrity()
        #expect(
            second.completenessAdvisory?.contains("no high-water mark") == true,
            "\(second.completenessAdvisory ?? "-")"
        )
        #expect(await anchorsOnly.loadLedgerHighWaterMark() == nil)
    }

    /// The cell the other two truncation tests leave uncovered, and the one that was broken.
    ///
    /// `deletedMarkIsNotHealedFromSurvivingRows` covers *deleted mark + second verify*, and
    /// `appendingAfterTruncationDoesNotReuseSequenceIDs` covers *mark present + appends*. Together
    /// they look like a complete matrix; the intersection — deleted mark, then an ordinary append —
    /// was where the laundering moved to. The append wrote `saveLedgerHighWaterMark(nextSequenceID)`,
    /// and with no mark to read, `nextSequenceID` came from the surviving rows: one append and the
    /// ledger had a mark agreeing with the truncation, in the signed archive too.
    @Test("appending after a mark deletion does not mint a mark from the surviving rows")
    func appendingAfterMarkDeletionDoesNotMintAMark() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let signer = SoftwareReceiptSigner()
        let store = try makeStore(context: context, headStore: headStore, signer: signer)

        for index in 0..<2 {
            _ = try await store.append(draft(kind: "a-\(index)", accountAddress: Self.accountA))
        }
        for index in 0..<2 {
            _ = try await store.append(draft(kind: "b-\(index)", accountAddress: Self.accountB))
        }

        // Account B's rows, B's anchor, and the mark.
        for row in try context.fetch(FetchDescriptor<StoredReceipt>())
            where row.accountKey == Self.accountB.lowercased() {
            context.delete(row)
        }
        try context.save()
        let anchorsOnly = InMemoryReceiptIntegrityHeadStore()
        for row in try context.fetch(FetchDescriptor<StoredReceipt>()) {
            await anchorsOnly.saveHead(row.chainHash, for: row.accountKey)
        }
        let truncated = try makeStore(context: context, headStore: anchorsOnly, signer: signer)

        #expect(try await truncated.verifyIntegrity().completenessAdvisory != nil)

        // One ordinary governed action — the attacker's work is done; the user's own next receipt
        // was what used to erase the evidence.
        _ = try await truncated.append(draft(kind: "a-2", accountAddress: Self.accountA))

        #expect(
            await anchorsOnly.loadLedgerHighWaterMark() == nil,
            "the append minted a high-water mark from the surviving rows"
        )
        let after = try await truncated.verifyIntegrity()
        #expect(
            after.completenessAdvisory?.contains("no high-water mark") == true,
            "one append silenced the advisory: \(after.completenessAdvisory ?? "-")"
        )

        // And the archive keeps saying so, which is where it matters most.
        let anchor = try await truncated.provenanceTrustAnchor()
        let verified = try ReceiptProvenanceVerifier.verify(
            try await truncated.exportAll(),
            trustedSignerFingerprint: anchor.fingerprint
        )
        #expect(
            verified.completenessAdvisory?.contains("no high-water mark") == true,
            "\(verified.completenessAdvisory ?? "-")"
        )
    }

    /// The other side of that rule: minting over an *empty* ledger is exactly what a fresh install
    /// and a just-reset ledger need, so the restriction must not break bootstrap.
    @Test("the first append on an empty ledger does mint a mark")
    func firstAppendOnAnEmptyLedgerMintsAMark() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let store = try makeStore(context: context, headStore: headStore)

        #expect(await headStore.loadLedgerHighWaterMark() == nil)
        _ = try await store.append(draft(kind: "first", accountAddress: Self.accountA))

        #expect(await headStore.loadLedgerHighWaterMark() == 1)
        let result = try await store.verifyIntegrity()
        #expect(result.status == .verified, "\(result.failureReason ?? "-")")
        #expect(result.isFullyAttested)
    }

    /// "Empty" has to mean *no rows*, not "the highest sequence number is zero".
    ///
    /// `ledgerWasEmpty` is the sole licence `performAppend` has to mint a mark when none is readable,
    /// which is the anti-laundering condition the whole truncation mechanism rests on — so it must not
    /// rest on a sentinel collision in turn. Deriving it from `highestOnDisk == 0` meant a row
    /// carrying `sequenceID <= 0` made a populated ledger report empty, and the next append would mint
    /// a mark over it: exactly the laundering the restriction exists to prevent, reached without any
    /// deletion at all.
    ///
    /// The row here cannot be produced by this package (`sequenceID` is inside the chain hash, and
    /// `sequenceGapReasons` rejects non-positive IDs outright), and the ledger it makes is reported as
    /// unattested. The point is the guard, not the row: a load-bearing condition should be true by
    /// construction rather than by a survey of what can currently reach it.
    @Test("a row with a non-positive sequence number does not make the ledger look empty")
    func nonPositiveSequenceRowDoesNotLookLikeAnEmptyLedger() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let store = try makeStore(context: context, headStore: headStore)

        _ = try await store.append(draft(kind: "first", accountAddress: Self.accountA))
        // The mark the honest append wrote, then deleted — the state an attacker leaves behind.
        let anchorsOnly = InMemoryReceiptIntegrityHeadStore()
        for row in try context.fetch(FetchDescriptor<StoredReceipt>()) {
            await anchorsOnly.saveHead(row.chainHash, for: row.accountKey)
        }
        let reopened = try makeStore(context: context, headStore: anchorsOnly)

        // Rewrite the surviving row's sequence number to the sentinel the old guard compared against.
        let row = try #require(try context.fetch(FetchDescriptor<StoredReceipt>()).first)
        row.sequenceID = 0
        try context.save()

        _ = try await reopened.append(draft(kind: "second", accountAddress: Self.accountA))
        #expect(
            await anchorsOnly.loadLedgerHighWaterMark() == nil,
            "a row at sequence 0 made a populated ledger look empty, and the append minted a mark"
        )
    }

    /// The mark heal must never advance off a row this build could not verify.
    ///
    /// The heal is a durable, monotonic, irreversible write into the trusted store, derived from a
    /// `sequenceID` column — and for a row whose envelope version this build cannot reproduce, that
    /// column is covered by nothing. Taking `sequenceIDs.max()` over *all* rows therefore handed an
    /// attacker with row-store writes alone a way to write an arbitrary number into the Keychain.
    ///
    /// Measured before the fix, in the restore-concession state (no floor, nothing attestable):
    /// `sequenceID = 500_000` on one conceded row raised the mark to 500000, and every later pass
    /// reported *"the receipt ledger is missing 499998 of 500000 receipts written on this device"*.
    /// `saveLedgerHighWaterMark` refuses to lower it, so the only way back was `resetAll()` — a
    /// durable false accusation against an honest ledger with destroying the history as the only
    /// recovery, which is exactly what the `Status` trichotomy exists to prevent. Not a forgery, and
    /// still worth a verdict-free defence.
    @Test("the mark heal ignores rows whose envelope this build cannot recompute")
    func markHealIgnoresUnrecomputableRows() async throws {
        let context = try makeContext()
        let writingStore = try makeStore(
            context: context,
            headStore: InMemoryReceiptIntegrityHeadStore()
        )
        for index in 0..<2 {
            _ = try await writingStore.append(draft(kind: "a-\(index)", accountAddress: Self.accountA))
        }

        // The restore shape, which is the state where an unrecomputable row is conceded at all:
        // anchors and mark travel, the floor and the signing identity do not.
        let restored = InMemoryReceiptIntegrityHeadStore()
        for row in try context.fetch(FetchDescriptor<StoredReceipt>()) {
            await restored.saveHead(row.chainHash, for: row.accountKey)
        }
        await restored.saveLedgerHighWaterMark(2)
        #expect(await restored.loadHighestEnvelopeVersion() == nil)
        let victim = try makeStore(context: context, headStore: restored)

        let rows = try context.fetch(
            FetchDescriptor<StoredReceipt>(sortBy: [SortDescriptor(\StoredReceipt.sequenceID)])
        )
        rows[1].sequenceID = 500_000
        rows[1].integrityEnvelopeVersion = ReceiptIntegrityEnvelopeVersion.current + 1
        try context.save()

        _ = try await victim.verifyIntegrity()
        #expect(
            await restored.loadLedgerHighWaterMark() == 2,
            "the heal wrote an unverified sequence number into the trusted store"
        )

        // And the damage is not durable: the reported gap comes from the rows on disk, so removing
        // the planted row clears it, whereas a raised mark could never have been lowered.
        context.delete(rows[1])
        try context.save()
        let afterRemoval = try await victim.verifyIntegrity()
        #expect(
            afterRemoval.failureReason?.contains("is missing") != true,
            "\(afterRemoval.failureReason ?? "-")"
        )
    }

    /// A sequence column at the end of the number line must produce an error, not kill the process.
    ///
    /// Allocation is `max(highestOnDisk, mark) + 1`, and both inputs are attacker-writable — the
    /// column by anyone who can write the row store, the mark by anyone who can write the Keychain.
    /// Neither is range-checked before that addition, so **one row edited to `Int.max` made every
    /// later append overflow and trap**: measured `SIGTRAP`, from SwiftData write access alone, with
    /// no signing key and no Keychain. Permanent, too — the row survives, so every subsequent append
    /// crashes again. That is a corrupted column denying the entire audit trail, the same failure
    /// shape a non-finite `createdAt` once had on the verify path, and the reason both are now
    /// verdicts or errors rather than aborts.
    @Test("a sequence number at the end of the number line fails the append instead of trapping")
    func sequenceAllocationAtIntMaxFailsInsteadOfTrapping() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let store = try makeStore(context: context, headStore: headStore)

        _ = try await store.append(draft(kind: "first", accountAddress: Self.accountA))

        let row = try #require(try context.fetch(FetchDescriptor<StoredReceipt>()).first)
        row.sequenceID = Int.max
        try context.save()

        // A typed error the caller can match, not a trap and not an opaque failure.
        await #expect(
            throws: ReceiptPersistenceConsistencyError.sequenceAllocationOutOfRange(highest: Int.max)
        ) {
            _ = try await store.append(draft(kind: "second", accountAddress: Self.accountA))
        }

        // And the condition is still *reported* through the ordinary channel: `sequenceID` is inside
        // the hashed envelope, so the edited row fails its chain hash.
        let result = try await store.verifyIntegrity()
        #expect(result.status == .tampered, "\(result.failureReason ?? "-")")
    }

    /// The same guard on the per-account counter, which is derived from a stored row in exactly the
    /// same way and was therefore the same trap.
    @Test("an account sequence at the end of the number line fails the append instead of trapping")
    func accountSequenceAllocationAtIntMaxFailsInsteadOfTrapping() async throws {
        let context = try makeContext()
        let store = try makeStore(context: context, headStore: InMemoryReceiptIntegrityHeadStore())

        _ = try await store.append(draft(kind: "first", accountAddress: Self.accountA))

        let row = try #require(try context.fetch(FetchDescriptor<StoredReceipt>()).first)
        row.accountSequenceID = Int.max
        try context.save()

        await #expect(
            throws: ReceiptPersistenceConsistencyError.sequenceAllocationOutOfRange(highest: Int.max)
        ) {
            _ = try await store.append(draft(kind: "second", accountAddress: Self.accountA))
        }
    }

    /// The verify and archive paths are safe from the same arithmetic only because their fetches sort
    /// `accountSequenceID` ascending, so a row at `Int.max` is reached last and never becomes a
    /// predecessor. That is too subtle to leave a verdict resting on, so both now report overflow
    /// instead of adding — and this pins that they return a verdict rather than trapping.
    @Test("rows and records at the end of the number line still produce a verdict")
    func intMaxAccountSequenceStillProducesAVerdict() async throws {
        let context = try makeContext()
        let store = try makeStore(context: context, headStore: InMemoryReceiptIntegrityHeadStore())

        _ = try await store.append(draft(kind: "first", accountAddress: Self.accountA))
        _ = try await store.append(draft(kind: "second", accountAddress: Self.accountA))

        // Both rows on one account at the top, so the second one's expected predecessor arithmetic is
        // the overflowing case.
        for row in try context.fetch(FetchDescriptor<StoredReceipt>()) {
            row.accountSequenceID = Int.max
        }
        try context.save()

        let result = try await store.verifyIntegrity()
        #expect(result.status == .tampered, "\(result.failureReason ?? "-")")
        #expect(
            result.failureReason?.contains("invalid account sequence") == true,
            "\(result.failureReason ?? "-")"
        )
    }

    /// A mark item that will not decode must not pin the ledger forever.
    ///
    /// `saveLedgerHighWaterMark` used to read the existing value with a plain `try`, so a stored item
    /// that failed to parse failed the *write* too and could never be replaced — every verification
    /// afterwards reported completeness unconfirmed, permanently, with `resetAll()` as the only exit.
    /// An item this device cannot parse is not a floor it can honour.
    @Test("a mark that cannot be decoded is repaired rather than pinning the ledger")
    func unreadableMarkIsRepairable() async throws {
        let headStore = CorruptibleHighWaterMarkHeadStore()
        await headStore.saveLedgerHighWaterMark(3)
        await headStore.corruptMark()

        // The read fails...
        await #expect(throws: ReceiptIntegrityHeadStoreError.self) {
            _ = try await headStore.loadLedgerHighWaterMark()
        }
        // ...but the write still lands, which is what makes the state recoverable.
        try await headStore.saveLedgerHighWaterMark(4)
        #expect(try await headStore.loadLedgerHighWaterMark() == 4)
    }

    /// With no readable mark, sequence IDs freed by a deletion *can* be reissued — there is no honest
    /// floor to allocate from, and a Keychain that cannot be read must not block receipt writes.
    ///
    /// Pinned because the safety argument is indirect and worth protecting: the reuse is tolerable
    /// only because the same condition stops the append writing a mark at all, so the advisory keeps
    /// saying completeness is unconfirmed rather than being silenced by a mark that agrees with the
    /// reissued rows.
    @Test("reuse with no readable mark keeps the advisory")
    func reuseWithoutAReadableMarkKeepsTheAdvisory() async throws {
        let context = try makeContext()
        let headStore = CorruptibleHighWaterMarkHeadStore()
        let signer = SoftwareReceiptSigner()
        let store = try makeStore(context: context, headStore: headStore, signer: signer)

        for index in 0..<4 {
            _ = try await store.append(draft(kind: "row-\(index)", accountAddress: Self.accountA))
        }
        for row in try context.fetch(FetchDescriptor<StoredReceipt>()) where row.sequenceID >= 3 {
            context.delete(row)
        }
        try context.save()
        let tip = try #require(
            try context.fetch(FetchDescriptor<StoredReceipt>()).max(by: { $0.sequenceID < $1.sequenceID })
        )
        await headStore.saveHead(tip.chainHash, for: tip.accountKey)
        await headStore.corruptMark()

        _ = try await store.append(draft(kind: "later", accountAddress: Self.accountA))

        // The reuse happens — 3 was freed by the deletion and handed out again.
        let sequenceIDs = try context.fetch(FetchDescriptor<StoredReceipt>()).map(\.sequenceID).sorted()
        #expect(sequenceIDs == [1, 2, 3])

        // And the advisory still says completeness is unconfirmed, because no mark was written.
        let result = try await store.verifyIntegrity()
        #expect(
            result.completenessAdvisory?.contains("no high-water mark") == true,
            "\(result.completenessAdvisory ?? "-")"
        )
    }

    /// The same erasure taken straight to export with no prior verify, which is the path that
    /// actually reaches a third party. The archive has to say that completeness is unconfirmed; an
    /// omitted mark alone is indistinguishable from an archive predating the field.
    @Test("an archive exported with no mark carries the advisory")
    func archiveWithNoMarkCarriesTheAdvisory() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let signer = SoftwareReceiptSigner()
        let store = try makeStore(context: context, headStore: headStore, signer: signer)

        for index in 0..<2 {
            _ = try await store.append(draft(kind: "a-\(index)", accountAddress: Self.accountA))
        }
        for index in 0..<2 {
            _ = try await store.append(draft(kind: "b-\(index)", accountAddress: Self.accountB))
        }
        for row in try context.fetch(FetchDescriptor<StoredReceipt>())
            where row.accountKey == Self.accountB.lowercased() {
            context.delete(row)
        }
        try context.save()
        let anchorsOnly = InMemoryReceiptIntegrityHeadStore()
        for row in try context.fetch(FetchDescriptor<StoredReceipt>()) {
            await anchorsOnly.saveHead(row.chainHash, for: row.accountKey)
        }
        let truncated = try makeStore(context: context, headStore: anchorsOnly, signer: signer)

        let anchor = try await truncated.provenanceTrustAnchor()
        let data = try await truncated.exportAll()

        let export = try ReceiptCanonicalJSON.decoder().decode(ReceiptProvenanceExport.self, from: data)
        #expect(export.manifest.ledgerHighWaterMark == nil)
        #expect(export.manifest.ledgerCompletenessUnconfirmed == true, "the archive hid the uncertainty")

        let verified = try ReceiptProvenanceVerifier.verify(
            data,
            trustedSignerFingerprint: anchor.fingerprint
        )
        #expect(
            verified.completenessAdvisory?.contains("no high-water mark") == true,
            "\(verified.completenessAdvisory ?? "-")"
        )
    }

    /// The residual this mechanism does *not* close, pinned so it is a stated property rather than a
    /// surprise. The mark is an unauthenticated Keychain item, so an attacker who can write the
    /// Keychain can lower it to agree with the rows they left and silence the advisory entirely.
    /// Signing it would not help — the signing key is in the same Keychain. That unfixability is why
    /// the mark is advisory rather than a control; see
    /// `ReceiptIntegrity.completenessAdvisory(sequenceIDs:highWaterMark:completenessUnconfirmed:)`.
    @Test("a mark rewritten directly in the Keychain silences the advisory, as documented")
    func rewrittenMarkSilencesTheAdvisoryAsDocumented() async throws {
        let context = try makeContext()
        let headStore = RewritableHighWaterMarkHeadStore()
        let store = try makeStore(context: context, headStore: headStore)

        for index in 0..<5 {
            _ = try await store.append(draft(kind: "row-\(index)", accountAddress: Self.accountA))
        }
        for row in try context.fetch(FetchDescriptor<StoredReceipt>()) where row.sequenceID >= 4 {
            context.delete(row)
        }
        try context.save()
        let tip = try #require(
            try context.fetch(FetchDescriptor<StoredReceipt>()).max(by: { $0.sequenceID < $1.sequenceID })
        )
        await headStore.saveHead(tip.chainHash, for: tip.accountKey)
        // The bypass: writing the item directly rather than through the monotonic API.
        await headStore.forceLedgerHighWaterMark(3)

        let result = try await store.verifyIntegrity()
        #expect(
            result.completenessAdvisory == nil,
            "if this now raises an advisory, the residual was closed and the docs should say so"
        )
        #expect(result.status == .verified, "\(result.failureReason ?? "-")")
    }

    // MARK: - No false accusations

    /// The advisory must not fire on an ordinary ledger. A false positive here would put a "receipts
    /// may have been removed" note on every healthy install.
    @Test("an untouched ledger raises no advisory")
    func untouchedLedgerIsClean() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let store = try makeStore(context: context, headStore: headStore)

        for index in 0..<3 {
            _ = try await store.append(draft(kind: "a-\(index)", accountAddress: Self.accountA))
        }
        _ = try await store.append(draft(kind: "b-0", accountAddress: Self.accountB))

        let result = try await store.verifyIntegrity()
        #expect(result.status == .verified, "\(result.failureReason ?? "-")")
        #expect(result.isFullyAttested)
        #expect(await headStore.loadLedgerHighWaterMark() == 4)
    }

    /// `resetAll()` restarts `sequenceID` at 1, so leaving the mark behind would make an honest reset
    /// read as a ledger that lost everything it ever had — permanently, since re-running the reset
    /// would not clear it either.
    @Test("a reset clears the mark, so an honest reset is not reported as truncation")
    func resetClearsTheMark() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let store = try makeStore(context: context, headStore: headStore)

        for index in 0..<3 {
            _ = try await store.append(draft(kind: "row-\(index)", accountAddress: Self.accountA))
        }
        try await store.resetAll()
        #expect(await headStore.loadLedgerHighWaterMark() == nil)

        // Empty and reset: nothing to report.
        #expect(try await store.verifyIntegrity().status == .verified)

        // And writing again starts a clean mark rather than resuming the old one.
        _ = try await store.append(draft(kind: "after-reset", accountAddress: Self.accountA))
        #expect(await headStore.loadLedgerHighWaterMark() == 1)
        let result = try await store.verifyIntegrity()
        #expect(result.status == .verified, "\(result.failureReason ?? "-")")
        #expect(result.isFullyAttested)
    }

    /// The append path commits the row and its anchor before raising the mark, so a crash or a locked
    /// Keychain in that window leaves the mark one behind. That is the innocent direction and must be
    /// healed rather than reported — otherwise an install whose last append was interrupted reads as
    /// incomplete forever.
    @Test("a mark left behind by a crash is healed, not reported")
    func staleLowMarkIsHealed() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let store = try makeStore(context: context, headStore: headStore)

        for index in 0..<3 {
            _ = try await store.append(draft(kind: "row-\(index)", accountAddress: Self.accountA))
        }
        // Exactly what an append interrupted between its anchor write and its mark write leaves.
        await headStore.clearAllHeads()
        for row in try context.fetch(FetchDescriptor<StoredReceipt>()) {
            await headStore.saveHead(row.chainHash, for: row.accountKey)
        }
        await headStore.saveLedgerHighWaterMark(2)

        let result = try await store.verifyIntegrity()
        #expect(result.status == .verified, "\(result.failureReason ?? "-")")
        #expect(await headStore.loadLedgerHighWaterMark() == 3, "the stale mark was not advanced")
    }

    /// A store restored to a new device brings the rows without the `ThisDeviceOnly` Keychain items,
    /// so it has neither anchors nor a mark. Branding that ledger truncated on arrival is the false
    /// accusation this package repeatedly goes out of its way to avoid — the absent-mark complaint is
    /// gated on this device having demonstrably written the chain.
    @Test("a restored ledger with no mark is not reported as truncated")
    func restoredLedgerWithNoMarkIsNotAccused() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let writingSigner = SoftwareReceiptSigner()
        let writingStore = try makeStore(context: context, headStore: headStore, signer: writingSigner)

        for index in 0..<2 {
            _ = try await writingStore.append(draft(kind: "row-\(index)", accountAddress: Self.accountA))
        }

        // The restore: same rows, no Keychain state, and a signing identity that wrote none of them.
        await headStore.clearAllHeads()
        let restoredStore = try makeStore(
            context: context,
            headStore: headStore,
            signer: SoftwareReceiptSigner()
        )

        let result = try await restoredStore.verifyIntegrity()
        #expect(result.status == .unattested, "\(result.failureReason ?? "-")")
        #expect(
            result.failureReason?.contains("missing") == false,
            "a restore is not a truncation: \(result.failureReason ?? "-")"
        )
        // Locally silent, deliberately: the advisory's `!currentIdentitySeen.isEmpty` conjunct exists
        // so the most ordinary event there is does not read as an accusation.
        #expect(result.completenessAdvisory == nil, "\(result.completenessAdvisory ?? "-")")
    }

    /// The one place the store and the archive verifier are *allowed* to disagree, pinned so the
    /// asymmetry is a decision rather than a discrepancy someone finds later.
    ///
    /// A restored ledger raises no local advisory (above). Its archive still declares
    /// `ledgerCompletenessUnconfirmed`, because for a third party an omitted mark is ambiguous between
    /// "this archive predates the field" and "the exporting device had no mark" — and removing that
    /// ambiguity is the whole reason the flag exists. The local surface declines to alarm; the archive
    /// declines to imply. See the note at the `ReceiptProvenanceManifest` construction site.
    @Test("a restored ledger's archive declares completeness unconfirmed even though the store does not")
    func restoredLedgerArchiveDeclaresCompletenessUnconfirmed() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let writingStore = try makeStore(
            context: context,
            headStore: headStore,
            signer: SoftwareReceiptSigner()
        )

        for index in 0..<2 {
            _ = try await writingStore.append(draft(kind: "row-\(index)", accountAddress: Self.accountA))
        }
        await headStore.clearAllHeads()
        let restoredStore = try makeStore(
            context: context,
            headStore: headStore,
            signer: SoftwareReceiptSigner()
        )

        #expect(try await restoredStore.verifyIntegrity().completenessAdvisory == nil)

        let anchor = try await restoredStore.provenanceTrustAnchor()
        let exported = try await restoredStore.exportAll()
        let decoded = try ReceiptCanonicalJSON.decoder()
            .decode(ReceiptProvenanceExport.self, from: exported)
        #expect(decoded.manifest.ledgerHighWaterMark == nil)
        #expect(decoded.manifest.ledgerCompletenessUnconfirmed == true)

        let verified = try ReceiptProvenanceVerifier.verify(
            exported,
            trustedSignerFingerprint: anchor.fingerprint
        )
        #expect(
            verified.completenessAdvisory?.contains("carries no high-water mark") == true,
            "\(verified.completenessAdvisory ?? "-")"
        )
        // And still not an accusation: the rows are intact, they are just not attestable from here.
        #expect(verified.status == .unattested, "\(verified.failureReason ?? "-")")
    }

    /// The other side of that gate: a device that *did* write the chain and has no mark says so in the
    /// advisory, because without the mark completeness degrades to exactly the measure a suffix
    /// deletion defeats — but it says so without moving the verdict, since a missing
    /// `ThisDeviceOnly` item is not evidence of tampering.
    @Test("a ledger this device wrote with no mark raises the unconfirmed advisory")
    func missingMarkOnALedgerThisDeviceWroteRaisesTheAdvisory() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        // One signer across both stores, so `currentIdentitySeen` is non-empty on the second pass —
        // this device demonstrably wrote these rows, which is what separates this case from a restore.
        let signer = SoftwareReceiptSigner()
        let store = try makeStore(context: context, headStore: headStore, signer: signer)

        for index in 0..<2 {
            _ = try await store.append(draft(kind: "row-\(index)", accountAddress: Self.accountA))
        }

        // The anchors kept, the mark alone removed — the shape of a ledger written before the mark
        // existed, and of an attacker deleting just the evidence of how far the ledger got.
        let anchorsOnly = InMemoryReceiptIntegrityHeadStore()
        for row in try context.fetch(FetchDescriptor<StoredReceipt>()) {
            await anchorsOnly.saveHead(row.chainHash, for: row.accountKey)
        }
        #expect(await anchorsOnly.loadLedgerHighWaterMark() == nil)
        let storeWithoutMark = try makeStore(context: context, headStore: anchorsOnly, signer: signer)

        let result = try await storeWithoutMark.verifyIntegrity()
        #expect(
            result.completenessAdvisory?.contains("no high-water mark") == true,
            "\(result.completenessAdvisory ?? "-")"
        )
        #expect(result.status == .verified, "\(result.failureReason ?? "-")")
        #expect(result.isFullyAttested, "a missing ThisDeviceOnly item is not evidence of tampering")
    }

    // MARK: - The advisory is structurally independent of the verdict

    /// The invariant the whole split rests on: an advisory never changes a verdict, in either
    /// direction.
    ///
    /// Asserted against the type rather than only through the store, because this is a property of
    /// the API shape. `withCompletenessAdvisory(_:)` exists precisely so the verdict is constructed
    /// first and the note attached afterwards — there is no factory that takes both, so no code path
    /// can compute one from the other.
    @Test("attaching an advisory leaves status and isFullyAttested untouched")
    func advisoryCannotChangeAVerdict() {
        let advisory = "The ledger high-water mark is 9 but only 2 receipts are present."

        let verified = ReceiptIntegrityVerificationResult.valid
        let verifiedWithNote = verified.withCompletenessAdvisory(advisory)
        #expect(verifiedWithNote.status == verified.status)
        #expect(verifiedWithNote.isFullyAttested == verified.isFullyAttested)
        #expect(verifiedWithNote.isFullyAttested, "an advisory downgraded a verified ledger")
        #expect(verifiedWithNote.failureReason == verified.failureReason)
        #expect(verifiedWithNote.completenessAdvisory == advisory)

        let unattested = ReceiptIntegrityVerificationResult.unattested("a reason")
        let unattestedWithNote = unattested.withCompletenessAdvisory(advisory)
        #expect(unattestedWithNote.status == .unattested)
        #expect(unattestedWithNote.failureReason == "a reason", "the advisory overwrote the verdict reason")

        let tampered = ReceiptIntegrityVerificationResult.invalid("broken chain")
        let tamperedWithNote = tampered.withCompletenessAdvisory(advisory)
        #expect(tamperedWithNote.status == .tampered, "an advisory upgraded a tampered ledger")
        #expect(tamperedWithNote.isValid == false)

        // And clearing it is equally inert.
        #expect(verifiedWithNote.withCompletenessAdvisory(nil).status == .verified)
    }

    /// The same independence through the real store, so the wiring matches the type's contract: one
    /// ledger with a suffix deletion (advisory, verdict untouched) and one with an interior hole
    /// (verdict moves, because that half is row-derived).
    @Test("a suffix deletion moves only the advisory; an interior hole moves the verdict")
    func advisoryAndVerdictComeFromDifferentEvidence() async throws {
        // Sequential: the survivors are contiguous, so only the mark has anything to say.
        let sequentialContext = try makeContext()
        let sequentialHeads = InMemoryReceiptIntegrityHeadStore()
        let sequential = try makeStore(context: sequentialContext, headStore: sequentialHeads)
        for index in 0..<2 {
            _ = try await sequential.append(draft(kind: "a-\(index)", accountAddress: Self.accountA))
        }
        for index in 0..<2 {
            _ = try await sequential.append(draft(kind: "b-\(index)", accountAddress: Self.accountB))
        }
        for row in try sequentialContext.fetch(FetchDescriptor<StoredReceipt>())
            where row.accountKey == Self.accountB.lowercased() {
            sequentialContext.delete(row)
        }
        try sequentialContext.save()
        await sequentialHeads.clearHead(for: Self.accountB.lowercased())

        let suffix = try await sequential.verifyIntegrity()
        #expect(suffix.status == .verified, "\(suffix.failureReason ?? "-")")
        #expect(suffix.completenessAdvisory != nil)

        // Interleaved: the same deletion now leaves a hole at sequence 2, which the rows show.
        let interleavedContext = try makeContext()
        let interleavedHeads = InMemoryReceiptIntegrityHeadStore()
        let interleaved = try makeStore(context: interleavedContext, headStore: interleavedHeads)
        for index in 0..<2 {
            _ = try await interleaved.append(draft(kind: "a-\(index)", accountAddress: Self.accountA))
            _ = try await interleaved.append(draft(kind: "b-\(index)", accountAddress: Self.accountB))
        }
        for row in try interleavedContext.fetch(FetchDescriptor<StoredReceipt>())
            where row.accountKey == Self.accountB.lowercased() {
            interleavedContext.delete(row)
        }
        try interleavedContext.save()
        await interleavedHeads.clearHead(for: Self.accountB.lowercased())

        let interior = try await interleaved.verifyIntegrity()
        #expect(interior.status == .unattested, "\(interior.failureReason ?? "-")")
        #expect(interior.failureReason?.contains("missing") == true, "\(interior.failureReason ?? "-")")
    }

    // MARK: - Concurrency across the mark read

    /// The append path gained an `await` — the mark read — *before* it allocates a sequence ID, which
    /// is the shape of the read-modify-write bug this codebase has hit repeatedly: read, suspend,
    /// write back stale. It is safe only because the whole body runs inside `withLedgerLock`, so this
    /// pins that rather than trusting it.
    ///
    /// If the mark read ever moved outside the lock, two concurrent appends would read the same floor,
    /// allocate the same sequence ID, and write duplicate rows.
    @Test("concurrent appends allocate distinct sequence IDs across the mark read")
    func concurrentAppendsAllocateDistinctSequenceIDs() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        // A signer that suspends widens the window between the mark read and the row insert, so a
        // concurrent append lands in it reliably rather than by chance.
        let store = try makeStore(context: context, headStore: headStore, signer: SlowSigner())

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<6 {
                group.addTask {
                    _ = try? await store.append(
                        draft(kind: "concurrent-\(index)", accountAddress: Self.accountA)
                    )
                }
            }
        }

        let sequenceIDs = try context.fetch(FetchDescriptor<StoredReceipt>()).map(\.sequenceID).sorted()
        #expect(sequenceIDs == Array(1...sequenceIDs.count), "duplicate or skipped sequence IDs: \(sequenceIDs)")
        #expect(
            await headStore.loadLedgerHighWaterMark() == sequenceIDs.count,
            "the mark disagrees with the rows after concurrent appends"
        )

        let result = try await store.verifyIntegrity()
        #expect(result.status == .verified, "\(result.failureReason ?? "-")")
        #expect(result.isFullyAttested)
    }

    /// Two stores over one container is a documented hazard (each owns its own ledger lock, so they do
    /// not serialize against each other). It is not prevented, and this does not claim it is — what it
    /// pins is that the damage is *reported* rather than silent: duplicate sequence IDs are caught by
    /// the completeness check, so the ledger cannot read `.verified` afterwards.
    @Test("two stores over one container produce a reported inconsistency, not a silent one")
    func twoStoresOverOneContainerAreReported() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let signer = SoftwareReceiptSigner()
        // `SlowSigner`, like every other concurrency test here, because without it this test provided
        // no coverage at all: if the race did not land, the only surviving assertion was
        // `result.isValid`, which an ordinary two-row ledger satisfies unconditionally. The window is
        // the span between reading the ledger and inserting the row, so widening the signature is what
        // makes the second store land inside it rather than behind it.
        let first = try makeStore(context: context, headStore: headStore, signer: SlowSigner())
        let second = try makeStore(context: context, headStore: headStore, signer: signer)

        // Deliberately racing the two independent locks.
        await withTaskGroup(of: Void.self) { group in
            group.addTask { _ = try? await first.append(draft(kind: "a", accountAddress: Self.accountA)) }
            group.addTask { _ = try? await second.append(draft(kind: "b", accountAddress: Self.accountA)) }
        }

        let sequenceIDs = try context.fetch(FetchDescriptor<StoredReceipt>()).map(\.sequenceID).sorted()
        let result = try await first.verifyIntegrity()
        #expect(sequenceIDs.count == 2, "both appends should have committed: \(sequenceIDs)")
        // The claim, either way round: the hazard is not prevented, but it cannot be silent. The two
        // stores collide on `accountSequenceID` as well as `sequenceID`, so whichever check sees it
        // first, the one outcome this test rules out is `.verified`.
        #expect(result.status != .verified, "two stores raced and the ledger still read verified")
        #expect(
            result.failureReason != nil,
            "the collision produced no reason at all"
        )
    }

    // MARK: - The residual, stated explicitly

    /// Wiping *everything* — every row and the mark — is indistinguishable from a fresh install, and
    /// one append later the ledger reads `.verified` again.
    ///
    /// Pinned deliberately, as the boundary of what the mark claims. The mark makes *selective*
    /// truncation permanent; it cannot make total destruction detectable, because there is nothing
    /// left to compare against and a genuinely new install must not be reported as tampered. An
    /// attacker who gets here has destroyed the history rather than forged a subset of it. If a future
    /// change makes this detectable that is an improvement — and this test should then be updated
    /// rather than deleted.
    @Test("a total wipe is indistinguishable from a fresh install, as documented")
    func totalWipeIsIndistinguishableFromAFreshInstall() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let store = try makeStore(context: context, headStore: headStore)

        for index in 0..<3 {
            _ = try await store.append(draft(kind: "row-\(index)", accountAddress: Self.accountA))
        }
        for row in try context.fetch(FetchDescriptor<StoredReceipt>()) {
            context.delete(row)
        }
        try context.save()
        await headStore.clearAllHeads()

        _ = try await store.append(draft(kind: "after-wipe", accountAddress: Self.accountA))
        let result = try await store.verifyIntegrity()
        #expect(
            result.status == .verified,
            "if this is no longer verified, total-wipe detection was added and the docs should say so"
        )

        // The contrast that makes the mark worth having: leave the mark behind and the same deletion
        // is permanent.
        let secondContext = try makeContext()
        let keptMark = InMemoryReceiptIntegrityHeadStore()
        let secondStore = try makeStore(context: secondContext, headStore: keptMark)
        for index in 0..<3 {
            _ = try await secondStore.append(draft(kind: "row-\(index)", accountAddress: Self.accountA))
        }
        for row in try secondContext.fetch(FetchDescriptor<StoredReceipt>()) {
            secondContext.delete(row)
        }
        try secondContext.save()
        await keptMark.clearHead(for: Self.accountA.lowercased())

        _ = try await secondStore.append(draft(kind: "after-truncation", accountAddress: Self.accountA))
        let stillReported = try await secondStore.verifyIntegrity()
        #expect(stillReported.status == .unattested, "\(stillReported.failureReason ?? "-")")
        #expect(stillReported.isFullyAttested == false)
    }

    // MARK: - The mark itself

    @Test("the mark never moves backwards")
    func markIsMonotonic() async throws {
        let headStore = InMemoryReceiptIntegrityHeadStore()

        await headStore.saveLedgerHighWaterMark(7)
        await headStore.saveLedgerHighWaterMark(3)
        #expect(await headStore.loadLedgerHighWaterMark() == 7)

        await headStore.saveLedgerHighWaterMark(9)
        #expect(await headStore.loadLedgerHighWaterMark() == 9)
    }

    /// The mark is stored under its own Keychain service, and this is why: `loadAllHeads()` queries
    /// the head service wholesale, so a mark filed alongside the anchors would come back as an
    /// account named `"ledger"` — and a protected head with no persisted receipts is reported as
    /// tampering, so every verify would fail on a wallet that does not exist.
    @Test("the mark is not returned as an account anchor")
    func markIsNotAnAccountAnchor() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let store = try makeStore(context: context, headStore: headStore)

        _ = try await store.append(draft(kind: "row", accountAddress: Self.accountA))

        #expect(await headStore.loadAllHeads().keys.sorted() == [Self.accountA.lowercased()])
        #expect(await headStore.loadLedgerHighWaterMark() == 1)
        #expect(try await store.verifyIntegrity().status == .verified)
    }

    /// The exported manifest has to carry the mark, or exporting first defeats the check — the same
    /// way omitting `sequenceGapReasons` from the verifier once did. And it has to be *inside* the
    /// signed manifest hash, so stripping it is not an option either.
    @Test("the export manifest publishes the mark under the manifest signature")
    func exportPublishesTheMark() async throws {
        let context = try makeContext()
        let store = try makeStore(context: context, headStore: InMemoryReceiptIntegrityHeadStore())

        for index in 0..<3 {
            _ = try await store.append(draft(kind: "row-\(index)", accountAddress: Self.accountA))
        }

        let data = try await store.exportAll()
        let export = try ReceiptCanonicalJSON.decoder().decode(ReceiptProvenanceExport.self, from: data)
        #expect(export.manifest.ledgerHighWaterMark == 3)

        // Stripping the field changes the manifest hash, so the pinned signature no longer covers it.
        let stripped = ReceiptProvenanceManifest(
            recordCount: export.manifest.recordCount,
            recordsHash: export.manifest.recordsHash,
            chainHeads: export.manifest.chainHeads,
            ledgerHighWaterMark: nil
        )
        let anchor = try await store.provenanceTrustAnchor()
        let tampered = try ReceiptCanonicalJSON.encoder().encode(
            ReceiptProvenanceExport(
                records: export.records,
                manifest: stripped,
                manifestHash: export.manifestHash,
                manifestSignature: export.manifestSignature,
                trustAnchor: export.trustAnchor
            )
        )
        let result = try ReceiptProvenanceVerifier.verify(
            tampered,
            trustedSignerFingerprint: anchor.fingerprint
        )
        #expect(result.status == .tampered, "\(result.failureReason ?? "-")")
        #expect(result.failureReason?.contains("manifest signature is invalid") == true)
    }

    // MARK: - Helpers

    private func makeContext() throws -> ModelContext {
        try ReceiptStorageTestModelContainers.context()
    }

    private func makeStore(
        context: ModelContext,
        headStore: any ReceiptIntegrityHeadStoring,
        signer: any ReceiptSigning = SoftwareReceiptSigner()
    ) throws -> ReceiptPersistenceStore {
        ReceiptPersistenceStore(
            modelContainer: context.container,
            integrityHeadStore: headStore,
            signer: signer
        )
    }

    /// Marks the mark writable *downwards*, which the real store's API refuses — so a test can stand
    /// in for an attacker writing the Keychain item directly instead of going through
    /// `saveLedgerHighWaterMark(_:)`.
    private actor RewritableHighWaterMarkHeadStore: ReceiptIntegrityHeadStoring {
        private var heads: [String: String] = [:]
        private var mark: Int?
        private var envelopeVersion: Int?

        func loadHead(for accountKey: String) -> String? { heads[accountKey] }
        func loadAllHeads() -> [String: String] { heads }
        func saveHead(_ hash: String, for accountKey: String) { heads[accountKey] = hash }
        func clearHead(for accountKey: String) { heads.removeValue(forKey: accountKey) }

        func clearAllHeads() {
            heads.removeAll()
            mark = nil
            envelopeVersion = nil
        }

        func loadLedgerHighWaterMark() -> Int? { mark }

        func saveLedgerHighWaterMark(_ sequenceID: Int) {
            mark = max(mark ?? 0, sequenceID)
        }

        func loadHighestEnvelopeVersion() -> Int? { envelopeVersion }

        func saveHighestEnvelopeVersion(_ version: Int) {
            envelopeVersion = max(envelopeVersion ?? 0, version)
        }

        /// The bypass. Not part of the protocol, because nothing in the package may lower the mark.
        func forceLedgerHighWaterMark(_ sequenceID: Int) {
            mark = sequenceID
        }
    }

    /// Models a stored mark item that exists but does not decode — the real store's
    /// ``ReceiptIntegrityHeadStoreError/dataDecodingFailed``, which the plain in-memory double cannot
    /// reach because it holds an `Int` rather than bytes.
    private actor CorruptibleHighWaterMarkHeadStore: ReceiptIntegrityHeadStoring {
        private var heads: [String: String] = [:]
        private var mark: Int?
        private var markIsCorrupt = false
        private var envelopeVersion: Int?

        func loadHead(for accountKey: String) -> String? { heads[accountKey] }
        func loadAllHeads() -> [String: String] { heads }
        func saveHead(_ hash: String, for accountKey: String) { heads[accountKey] = hash }
        func clearHead(for accountKey: String) { heads.removeValue(forKey: accountKey) }

        func clearAllHeads() {
            heads.removeAll()
            mark = nil
            markIsCorrupt = false
            envelopeVersion = nil
        }

        func loadHighestEnvelopeVersion() -> Int? { envelopeVersion }

        func saveHighestEnvelopeVersion(_ version: Int) {
            envelopeVersion = max(envelopeVersion ?? 0, version)
        }

        func loadLedgerHighWaterMark() throws -> Int? {
            if markIsCorrupt { throw ReceiptIntegrityHeadStoreError.dataDecodingFailed }
            return mark
        }

        /// Mirrors the real store: an existing value that cannot be read is not a floor to honour, so
        /// the write replaces it instead of failing.
        func saveLedgerHighWaterMark(_ sequenceID: Int) {
            if !markIsCorrupt, let mark, mark >= sequenceID { return }
            mark = sequenceID
            markIsCorrupt = false
        }

        func corruptMark() {
            markIsCorrupt = true
        }
    }

    private func draft(kind: String, accountAddress: String?) -> ReceiptDraft {
        ReceiptDraft(
            createdAt: Date(timeIntervalSince1970: 100),
            actorDetail: .system,
            authorityDetail: nil,
            trigger: kind,
            scope: "accounts",
            summary: "Fixture",
            provenance: "test",
            isSuccess: true,
            correlationID: nil,
            timelineAccountAddress: accountAddress,
            timelineChainRawValue: nil,
            details: ReceiptPayload(values: [:])
        )
    }
}
