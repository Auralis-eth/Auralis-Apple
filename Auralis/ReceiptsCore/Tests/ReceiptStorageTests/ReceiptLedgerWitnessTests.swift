import Foundation
import ReceiptsCore
@testable import ReceiptStorage
import AuralisRuntime
import SwiftData
import Testing

/// The external witness, and the three attacks that were **undetectable at any severity** without it.
///
/// Everything else in this package reasons about state that lives on the device being attacked. Six
/// review rounds kept finding the same shape of hole underneath that fact, and two of the residuals
/// they left were documented as unclosable locally — a deleted suffix and a deleted account both leave
/// the survivors internally consistent, and the only local evidence, the high-water mark, is an
/// unauthenticated item that anyone reaching the Keychain can lower to agree with what they left.
///
/// A witness is the standard construction for exactly that gap: a party off the device writes down
/// where the ledger got to, and a later rewrite cannot match what it already holds. These tests are
/// organised as *before and after* on the same fixtures, because the value of this feature is
/// precisely the difference between the two.
@MainActor
struct ReceiptLedgerWitnessTests {
    private static let accountA = "0x1111111111111111111111111111111111111111"
    private static let accountB = "0x2222222222222222222222222222222222222222"

    // MARK: - What the witness makes detectable

    /// Suffix truncation: deleting whatever was written last.
    ///
    /// The survivors are a contiguous `1...k`, so no row-derived check can see it, and
    /// `ReceiptLedgerTruncationTests.excisingTheAccountHoldingTheHighWaterMarkRaisesAnAdvisory` pins
    /// the pre-witness outcome — `.verified`, `isFullyAttested`, with only an advisory attached. Same
    /// fixture here, now with a witness that was told the ledger reached receipt 4.
    @Test("a deleted suffix is tampering once a witness has seen the ledger")
    func deletedSuffixIsTamperingWithAWitness() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let witness = InMemoryReceiptLedgerWitness()
        let store = try makeStore(context: context, headStore: headStore, witness: witness)

        for index in 0..<2 {
            _ = try await store.append(draft(kind: "a-\(index)", account: Self.accountA))
        }
        for index in 0..<2 {
            _ = try await store.append(draft(kind: "b-\(index)", account: Self.accountB))
        }
        // The witness was told, by the append path itself, on every append.
        let checkpoint = try #require(await witness.latestCheckpoint())
        #expect(checkpoint.ledgerHighWaterMark == 4)
        #expect(try await store.verifyIntegrity().status == .verified)

        // Account B holds sequence 3 and 4 — the top of the ledger — and its anchor goes too, so
        // nothing local is left dangling.
        for row in try context.fetch(FetchDescriptor<StoredReceipt>())
        where row.accountKey == Self.accountB.lowercased() {
            context.delete(row)
        }
        try context.save()
        await headStore.clearHead(for: Self.accountB.lowercased())

        let result = try await store.verifyIntegrity()
        #expect(result.status == .tampered, "\(result.failureReason ?? "-")")
        #expect(result.isValid == false)
        #expect(
            result.failureReason?.contains("recorded this ledger reaching receipt 4") == true,
            "\(result.failureReason ?? "-")"
        )
        // And the archive can no longer be produced, which is the outcome that matters: before the
        // witness this ledger exported happily, with a note.
        await #expect(throws: ReceiptProvenanceExportError.self) {
            _ = try await store.exportAll()
        }
    }

    /// Whole-account deletion, interleaved so it does not also truncate the ledger.
    ///
    /// Every local check except the anchor set is per account, so excising one account's rows *and*
    /// its anchor leaves the survivors linking cleanly. With the victim account interleaved rather
    /// than last, even the mark has nothing to say — the highest sequence is untouched.
    @Test("an excised account is tampering once a witness has seen it")
    func excisedAccountIsTamperingWithAWitness() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let witness = InMemoryReceiptLedgerWitness()
        let store = try makeStore(context: context, headStore: headStore, witness: witness)

        // Interleaved, and account A written last, so the top of the ledger survives the deletion.
        _ = try await store.append(draft(kind: "a-0", account: Self.accountA))
        _ = try await store.append(draft(kind: "b-0", account: Self.accountB))
        _ = try await store.append(draft(kind: "a-1", account: Self.accountA))

        for row in try context.fetch(FetchDescriptor<StoredReceipt>())
        where row.accountKey == Self.accountB.lowercased() {
            context.delete(row)
        }
        try context.save()
        await headStore.clearHead(for: Self.accountB.lowercased())

        let result = try await store.verifyIntegrity()
        #expect(result.status == .tampered, "\(result.failureReason ?? "-")")
        #expect(
            result.failureReason?.contains("no longer holds") == true,
            "\(result.failureReason ?? "-")"
        )
    }

    /// Rewriting a receipt that the witness already recorded the hash of.
    ///
    /// A rewritten row's own chain hash can always be recomputed to be self-consistent — that is why
    /// the envelope-version concession was such a wide hole. What it cannot be made equal to is a hash
    /// a third party wrote down before the alteration.
    @Test("a rewritten receipt the witness recorded is tampering even when its hash is consistent")
    func rewrittenWitnessedReceiptIsTampering() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let witness = InMemoryReceiptLedgerWitness()
        let store = try makeStore(context: context, headStore: headStore, witness: witness)

        _ = try await store.append(draft(kind: "a-0", account: Self.accountA))
        let witnessed = try #require(await witness.latestCheckpoint())

        // Rewrite the row and re-hash it so it is *locally* flawless, then move the anchor to match —
        // i.e. grant the attacker Keychain write access too, which is the state `isValid` otherwise
        // concedes by design.
        let row = try #require(try context.fetch(FetchDescriptor<StoredReceipt>()).first)
        row.summary = "FORGED: user approved unlimited spend"
        row.signature = nil
        row.signerPublicKey = nil
        row.chainHash = try ReceiptIntegrity.chainHash(for: row)
        try context.save()
        await headStore.saveHead(row.chainHash, for: row.accountKey)
        // Locally self-consistent: the hash matches the columns.
        #expect(row.chainHash != witnessed.chainHeads.first?.chainHash)

        let result = try await store.verifyIntegrity()
        #expect(result.status == .tampered, "\(result.failureReason ?? "-")")
        #expect(
            result.failureReason?.contains("does not match the hash the external witness recorded") == true,
            "\(result.failureReason ?? "-")"
        )
    }

    /// A rolled-back account: the rows are genuine, just an older set of them.
    @Test("an account rolled back to an earlier state is tampering")
    func rolledBackAccountIsTampering() async throws {
        let context = try makeContext()
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let witness = InMemoryReceiptLedgerWitness()
        let store = try makeStore(context: context, headStore: headStore, witness: witness)

        for index in 0..<3 {
            _ = try await store.append(draft(kind: "a-\(index)", account: Self.accountA))
        }
        // Drop the account's last receipt and move its anchor back to the new tip, so every local
        // check agrees. Only the witness remembers there was a third.
        let rows = try context.fetch(
            FetchDescriptor<StoredReceipt>(sortBy: [SortDescriptor(\StoredReceipt.accountSequenceID)])
        )
        context.delete(rows[2])
        try context.save()
        await headStore.saveHead(rows[1].chainHash, for: rows[1].accountKey)

        let result = try await store.verifyIntegrity()
        #expect(result.status == .tampered, "\(result.failureReason ?? "-")")
    }

    // MARK: - What the witness must not do

    /// Ordinary use must not trip any of it. The rules are all drawn on *backwards* moves, so a ledger
    /// that only grows can never contradict a checkpoint.
    @Test("appending past a checkpoint keeps the ledger verified")
    func growingPastACheckpointStaysVerified() async throws {
        let context = try makeContext()
        let witness = InMemoryReceiptLedgerWitness()
        let store = try makeStore(
            context: context,
            headStore: InMemoryReceiptIntegrityHeadStore(),
            witness: witness
        )

        _ = try await store.append(draft(kind: "a-0", account: Self.accountA))
        let early = try #require(await witness.latestCheckpoint())

        // Grow: more receipts on the witnessed account, and a whole new account the checkpoint never
        // mentioned. Both are legitimate and neither may be reported.
        _ = try await store.append(draft(kind: "a-1", account: Self.accountA))
        _ = try await store.append(draft(kind: "b-0", account: Self.accountB))

        let result = try await store.verifyIntegrity()
        #expect(result.status == .verified, "\(result.failureReason ?? "-")")
        #expect(result.completenessAdvisory == nil, "\(result.completenessAdvisory ?? "-")")
        // The witnessed receipt is still located by `(account, sequence)` rather than compared against
        // the tip, which is what makes growth safe.
        #expect(early.chainHeads.first?.accountSequenceID == 1)
        #expect(try await store.exportAll().isEmpty == false)
    }

    /// An unreachable witness degrades to an advisory. It must never accuse, because a first run, an
    /// offline device, a signed-out account and a service outage all land here and none of them is
    /// evidence about the receipts.
    @Test("an unreachable witness is an advisory, not a verdict")
    func unreachableWitnessIsAnAdvisory() async throws {
        let context = try makeContext()
        let witness = InMemoryReceiptLedgerWitness()
        let store = try makeStore(
            context: context,
            headStore: InMemoryReceiptIntegrityHeadStore(),
            witness: witness
        )

        _ = try await store.append(draft(kind: "a-0", account: Self.accountA))
        await witness.setUnreachable(true)

        let result = try await store.verifyIntegrity()
        #expect(result.status == .verified, "\(result.failureReason ?? "-")")
        #expect(result.isValid)
        #expect(
            result.completenessAdvisory?.contains("has not been confirmed against the external witness") == true,
            "\(result.completenessAdvisory ?? "-")"
        )
        // Still exportable — the property this package has fought hardest to keep.
        #expect(try await store.exportAll().isEmpty == false)
    }

    /// A witness that exists but has never been told about this ledger says so, and still does not
    /// accuse. Distinct from unreachable, and distinct again from "no witness configured", which is a
    /// build fact and is logged rather than surfaced.
    @Test("a witness with no record yet is an advisory, not a verdict")
    func neverWitnessedLedgerIsAnAdvisory() async throws {
        let context = try makeContext()
        let witness = InMemoryReceiptLedgerWitness()
        // Rows written by a store with no witness at all, then verified by one that has a witness
        // which has never heard of them.
        let writer = try makeStore(context: context, headStore: InMemoryReceiptIntegrityHeadStore())
        _ = try await writer.append(draft(kind: "a-0", account: Self.accountA))

        let store = try makeStore(
            context: context,
            headStore: InMemoryReceiptIntegrityHeadStore(),
            witness: witness
        )
        #expect(try await witness.latestCheckpoint() == nil)

        let result = try await store.verifyIntegrity()
        #expect(result.isValid, "\(result.failureReason ?? "-")")
        #expect(
            result.completenessAdvisory?.contains("never been recorded with the witness") == true,
            "\(result.completenessAdvisory ?? "-")"
        )
    }

    /// With no witness configured at all, nothing changes and nothing is said. Pinned because the
    /// default path is every existing install, and a feature that is switched off must be invisible.
    @Test("an unconfigured witness leaves the verdict and the advisory untouched")
    func unconfiguredWitnessChangesNothing() async throws {
        let context = try makeContext()
        let store = try makeStore(context: context, headStore: InMemoryReceiptIntegrityHeadStore())

        _ = try await store.append(draft(kind: "a-0", account: Self.accountA))

        let result = try await store.verifyIntegrity()
        #expect(result.status == .verified, "\(result.failureReason ?? "-")")
        #expect(result.completenessAdvisory == nil, "\(result.completenessAdvisory ?? "-")")
    }

    /// The witness is append-only, and that is enforced rather than assumed — a witness the device can
    /// walk backwards is just another local store, and every argument for this feature collapses.
    @Test("a witness refuses a checkpoint that moves backwards")
    func witnessRefusesRegression() async throws {
        let witness = InMemoryReceiptLedgerWitness()
        try await witness.publish(
            ReceiptLedgerCheckpoint(
                ledgerHighWaterMark: 9,
                chainHeads: [],
                recordCount: 9,
                publishedAt: Date(timeIntervalSince1970: 100)
            )
        )
        await #expect(
            throws: ReceiptLedgerWitnessError.wouldRegress(witnessed: 9, offered: 4)
        ) {
            try await witness.publish(
                ReceiptLedgerCheckpoint(
                    ledgerHighWaterMark: 4,
                    chainHeads: [],
                    recordCount: 4,
                    publishedAt: Date(timeIntervalSince1970: 200)
                )
            )
        }
    }

    /// A failed publish must not fail the append. The receipt and its anchor are already committed by
    /// then, so throwing would report a write failure for a receipt that exists and invite a retry
    /// that writes it twice.
    @Test("an unreachable witness does not fail the append")
    func unreachableWitnessDoesNotFailTheAppend() async throws {
        let context = try makeContext()
        let witness = InMemoryReceiptLedgerWitness()
        await witness.setUnreachable(true)
        let store = try makeStore(
            context: context,
            headStore: InMemoryReceiptIntegrityHeadStore(),
            witness: witness
        )

        _ = try await store.append(draft(kind: "a-0", account: Self.accountA))
        #expect(try context.fetch(FetchDescriptor<StoredReceipt>()).count == 1)
    }

    // MARK: - The comparison in isolation

    /// The rules with no store and no ledger, because they are the part worth pinning exactly.
    @Test("the comparison fires only on backwards moves")
    func comparisonRules() {
        let head = ReceiptProvenanceChainHead(accountKey: "a", accountSequenceID: 2, chainHash: "h2")
        let witnessed = ReceiptLedgerCheckpoint(
            ledgerHighWaterMark: 5,
            chainHeads: [head],
            recordCount: 5,
            publishedAt: Date(timeIntervalSince1970: 0)
        )
        func local(
            highest: Int,
            hashes: [ReceiptWitnessRowKey: String],
            tips: [String: Int]
        ) -> ReceiptWitnessComparison.LocalLedger {
            ReceiptWitnessComparison.LocalLedger(
                highestVerifiedSequenceID: highest,
                chainHashesByAccountSequence: hashes,
                tipSequenceByAccount: tips
            )
        }
        let matching: [ReceiptWitnessRowKey: String] = [
            ReceiptWitnessRowKey(accountKey: "a", accountSequenceID: 2): "h2"
        ]

        // Agreement, and growth past the checkpoint.
        #expect(
            ReceiptWitnessComparison.contradiction(
                local: local(highest: 5, hashes: matching, tips: ["a": 2]),
                witnessed: witnessed
            ) == nil
        )
        #expect(
            ReceiptWitnessComparison.contradiction(
                local: local(highest: 9, hashes: matching, tips: ["a": 7]),
                witnessed: witnessed
            ) == nil
        )

        // Shorter ledger, missing account, rolled-back account, rewritten receipt.
        #expect(
            ReceiptWitnessComparison.contradiction(
                local: local(highest: 4, hashes: matching, tips: ["a": 2]),
                witnessed: witnessed
            ) != nil
        )
        #expect(
            ReceiptWitnessComparison.contradiction(
                local: local(highest: 5, hashes: [:], tips: [:]),
                witnessed: witnessed
            ) != nil
        )
        #expect(
            ReceiptWitnessComparison.contradiction(
                local: local(highest: 5, hashes: matching, tips: ["a": 1]),
                witnessed: witnessed
            ) != nil
        )
        #expect(
            ReceiptWitnessComparison.contradiction(
                local: local(
                    highest: 5,
                    hashes: [ReceiptWitnessRowKey(accountKey: "a", accountSequenceID: 2): "rewritten"],
                    tips: ["a": 2]
                ),
                witnessed: witnessed
            ) != nil
        )
    }

    // MARK: - Helpers

    private func makeContext() throws -> ModelContext {
        try ReceiptStorageTestModelContainers.context()
    }

    private func makeStore(
        context: ModelContext,
        headStore: any ReceiptIntegrityHeadStoring,
        witness: any ReceiptLedgerWitnessing = UnconfiguredReceiptLedgerWitness(),
        signer: any ReceiptSigning = SoftwareReceiptSigner()
    ) throws -> ReceiptPersistenceStore {
        ReceiptPersistenceStore(
            modelContainer: context.container,
            integrityHeadStore: headStore,
            signer: signer,
            witness: witness
        )
    }

    private func draft(kind: String, account: String?) -> ReceiptDraft {
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
            timelineAccountAddress: account,
            timelineChainRawValue: nil,
            details: ReceiptPayload(values: [:])
        )
    }
}
