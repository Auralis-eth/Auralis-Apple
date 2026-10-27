import Foundation
import ReceiptsCore
@testable import ReceiptStorage
import AuralisRuntime
import SwiftData
import Testing

/// A scratch model standing in for anything else the app keeps in its primary context — an account
/// rename, a playlist edit. Its only job is to be an *unrelated* pending change, so a receipt reset's
/// blast radius is observable.
@Model
final class ResetScopeScratchNote {
    var body: String

    init(body: String) {
        self.body = body
    }
}

/// `SwiftDataReceiptResetService` runs against the app's **primary** `ModelContext`, so anything it
/// does context-wide reaches the whole app.
@MainActor
struct ReceiptResetScopeTests {
    /// The reset must not save or roll back the primary context.
    ///
    /// Discarding the pending receipt rows used to go through `performRollbackSafeMutation`, whose
    /// `save()` and `rollback()` are both context-wide. On this context that meant two side effects
    /// nobody asked for: on success, every unrelated pending edit in the app was committed early; on a
    /// failing save — disk pressure being the realistic cause — *every* unsaved change in the app was
    /// discarded, not just the receipt deletes. The method's doc reasoned carefully about which rows
    /// to delete and not at all about what save/rollback would touch.
    @Test("resetting receipts neither commits nor discards unrelated pending edits")
    func resetLeavesUnrelatedPendingEditsAlone() async throws {
        let container = try ModelContainer(
            for: Schema([StoredReceipt.self, ResetScopeScratchNote.self]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let service = SwiftDataReceiptResetService(
            modelContext: context,
            integrityHeadStoreForTesting: InMemoryReceiptIntegrityHeadStore()
        )

        // An unrelated edit the person has not saved yet.
        let note = ResetScopeScratchNote(body: "renamed account")
        context.insert(note)
        // And a receipt sitting unsaved in the same context, which is the shape the discard exists for.
        context.insert(try makeUnsavedReceipt())

        #expect(context.insertedModelsArray.compactMap { $0 as? StoredReceipt }.count == 1)

        try await service.resetReceipts()

        // The unrelated edit is *still pending*, which pins both failure directions at once. A
        // context-wide `save()` would have committed the note and emptied `insertedModelsArray`; a
        // context-wide `rollback()` would have discarded it outright. Only leaving the context's
        // save state alone keeps it here, unsaved.
        let pendingNotes = context.insertedModelsArray.compactMap { $0 as? ResetScopeScratchNote }
        #expect(pendingNotes.count == 1, "the reset committed or discarded an unrelated pending edit")
        #expect(pendingNotes.first?.body == "renamed account")
        #expect(context.hasChanges, "the reset saved the primary context out from under its owner")

        // And the receipt really was discarded rather than merely left unsaved: when the app next
        // saves the context on its own terms, the note lands and the receipt does not. This is the
        // property that matters — a pending insert the reset could not see would otherwise be
        // committed by this very save and survive the reset.
        try context.save()
        #expect(try context.fetch(FetchDescriptor<ResetScopeScratchNote>()).count == 1)
        #expect(
            try context.fetch(FetchDescriptor<StoredReceipt>()).isEmpty,
            "a pending receipt survived the reset and was committed by the next save"
        )
    }

    private func makeUnsavedReceipt() throws -> StoredReceipt {
        try StoredReceipt(
            sequenceID: 1,
            createdAt: Date(timeIntervalSince1970: 100),
            actor: .system,
            actorDetail: .system,
            mode: .observe,
            trigger: "pending",
            scope: "accounts",
            summary: "Never saved",
            provenance: "test",
            isSuccess: true,
            accountSequenceID: 1,
            payloadHash: "payload",
            previousReceiptHash: ReceiptIntegrity.genesisHash,
            chainHash: "chain",
            details: ReceiptPayload(values: [:])
        )
    }
}

/// The ledger lock lives on a `ReceiptPersistenceStore` instance, so "how many instances exist per
/// container" is a correctness property, not a caching detail.
@MainActor
struct ReceiptStoreSharingTests {
    /// Two contexts over one container must resolve to one store.
    ///
    /// This is what makes the ledger lock effective process-wide: the governed pipeline sink, both
    /// `RuntimeHost`s, the account and ENS recorders and the ritual coordinator all append through
    /// whatever `ReceiptStores.live(modelContext:)` hands back, and a second instance would give them
    /// a second queue over the same rows — the duplicate-`accountSequenceID` defect the lock exists to
    /// prevent. The memoization is keyed on the `ModelContainer` rather than the `ModelContext`
    /// precisely so a caller's choice of context cannot fork it; nothing asserted that.
    @Test("two contexts over one container share a single receipt store")
    func oneStorePerContainer() throws {
        let container = try ModelContainer(
            for: Schema([StoredReceipt.self]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )

        let first = ReceiptStores.live(modelContext: ModelContext(container))
        let second = ReceiptStores.live(modelContext: ModelContext(container))

        #expect(first as AnyObject === second as AnyObject, "a second context forked the receipt store")

        // And a genuinely different container gets its own.
        let otherContainer = try ModelContainer(
            for: Schema([StoredReceipt.self]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let other = ReceiptStores.live(modelContext: ModelContext(otherContainer))
        #expect(first as AnyObject !== other as AnyObject)
    }

    /// The backfill is idempotent under contention.
    ///
    /// `backfillAccountKeysIfNeeded()` is per store instance, and the two-hosts-per-process shape puts
    /// two of them over the same durable rows. Both will find the same unkeyed rows and write the same
    /// derived value, so the interleaving must not matter — but the existing coverage only ever ran it
    /// sequentially on a fresh store.
    @Test("two stores backfilling one container concurrently agree on every account key")
    func concurrentBackfillIsIdempotent() async throws {
        let container = try ModelContainer(
            for: Schema([StoredReceipt.self]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let seedContext = ModelContext(container)
        // A shared head store and signer, because that is what two hosts over one container have:
        // separate durable state would break the anchor invariant for reasons unrelated to backfill.
        let headStore = InMemoryReceiptIntegrityHeadStore()
        let signer = SoftwareReceiptSigner()

        let seedStore = ReceiptPersistenceStore(
            modelContainer: container,
            integrityHeadStore: headStore,
            signer: signer
        )
        for index in 0..<4 {
            _ = try await seedStore.append(
                ReceiptDraft(
                    createdAt: Date(timeIntervalSince1970: 100),
                    actorDetail: .system,
                    authorityDetail: nil,
                    trigger: "seed-\(index)",
                    scope: "accounts",
                    summary: "Fixture",
                    provenance: "test",
                    isSuccess: true,
                    correlationID: nil,
                    timelineAccountAddress: "0x1111111111111111111111111111111111111111",
                    timelineChainRawValue: nil,
                    details: ReceiptPayload(values: [:])
                )
            )
        }

        // Rewind the column to its pre-migration default, which is the state the backfill exists for.
        let seeded = try seedContext.fetch(FetchDescriptor<StoredReceipt>())
        #expect(seeded.count == 4)
        for receipt in seeded {
            receipt.accountKey = ""
        }
        try seedContext.save()

        let storeA = ReceiptPersistenceStore(
            modelContainer: container,
            integrityHeadStore: headStore,
            signer: signer
        )
        let storeB = ReceiptPersistenceStore(
            modelContainer: container,
            integrityHeadStore: headStore,
            signer: signer
        )

        // Both verify at once; each one backfills on the way in.
        async let verdictA = storeA.verifyIntegrity()
        async let verdictB = storeB.verifyIntegrity()
        // Both are already running; these awaits only collect them.
        let resultA = try await verdictA
        let resultB = try await verdictB

        // `.verified`, not `isValid`. Both stores share one head store and one live signer, so every
        // interleaving must end fully attested — `isValid` also accepts `.unattested`, which is how a
        // concurrent backfill that silently dropped attestation would slip through.
        #expect(resultA.status == .verified, "\(resultA.failureReason ?? "-")")
        #expect(resultB.status == .verified, "\(resultB.failureReason ?? "-")")

        // Every row keyed, and keyed to the value the derivation produces — not left on `""`, and not
        // written twice into disagreeing states.
        let checkContext = ModelContext(container)
        let backfilled = try checkContext.fetch(FetchDescriptor<StoredReceipt>())
        #expect(backfilled.count == 4)
        for receipt in backfilled {
            #expect(
                receipt.accountKey == ReceiptIntegrity.accountKey(accountAddress: receipt.accountAddress)
            )
        }
        #expect(Set(backfilled.map(\.accountKey)).count == 1, "the backfill forked one account into two keys")
    }
}
