import SwiftData
import AuralisFoundation

@MainActor
public struct SwiftDataReceiptResetService: ReceiptResetting {
    private let receiptStore: any ReceiptStore
    private let modelContext: ModelContext?

    /// - Parameter integrityHeadStoreForTesting: Test seam, named so that choosing it is visible at
    ///   the call site — the same reason ``ReceiptPersistenceStore`` takes its signer as a required
    ///   parameter instead of defaulting to one. It was called `integrityHeadStore`, which read like
    ///   ordinary configuration while in fact opting the caller out of the shared ledger lock *and*
    ///   silently downgrading it to an ephemeral signing identity. When `nil` — the production path —
    ///   the reset runs through the store memoized by ``ReceiptStores/live(modelContext:)`` for this
    ///   container.
    ///
    ///   That sharing is load-bearing, not an optimization. `resetAll()` deletes the rows and then
    ///   clears the trusted heads, and it relies on `ReceiptPersistenceStore`'s ledger lock to keep
    ///   appends out of the gap between those two steps. The lock is per instance, so building a
    ///   second store here gave the reset its own queue and let an append land mid-reset — leaving a
    ///   receipt whose head was then wiped, which `verifyIntegrity()` reports forever after as
    ///   "persisted receipts without protected heads".
    public init(
        modelContext: ModelContext,
        integrityHeadStoreForTesting: (any ReceiptIntegrityHeadStoring)? = nil
    ) {
        self.modelContext = modelContext
        if let integrityHeadStoreForTesting {
            self.receiptStore = SwiftDataReceiptStore(
                persistenceStore: ReceiptPersistenceStore(
                    modelContainer: modelContext.container,
                    integrityHeadStore: integrityHeadStoreForTesting,
                    signer: ReceiptSignerFactory.ephemeralSigner()
                )
            )
        } else {
            self.receiptStore = ReceiptStores.live(modelContext: modelContext)
        }
    }

    public init(receiptStore: any ReceiptStore) {
        self.modelContext = nil
        self.receiptStore = receiptStore
    }

    public func resetReceipts() async throws {
        try await receiptStore.resetAll()
        discardPendingRowsInMainContextIfNeeded()
    }

    /// Drops rows sitting unsaved in the main context, which `resetAll()` cannot see: the persistence
    /// store works through its own `ModelContext`, so a pending insert here is invisible to it and
    /// would be committed by the main context's next save, surviving the reset.
    ///
    /// Restricted to `insertedModelsArray` rather than everything a fetch returns. A fetch also
    /// matches rows already on disk, including any appended after `resetAll()` returned — deleting
    /// one of those would strand its Keychain head and brand the ledger tampered, the exact outcome
    /// the reset is supposed to avoid. Pending inserts cannot have heads: heads are written by the
    /// persistence store after its own save, so a row this context has never saved was never anchored.
    ///
    /// Nothing outside this package inserts a `StoredReceipt` into the primary context — the
    /// persistence store owns its own — so in production this is a no-op guard. It stays because the
    /// app-target fixtures do produce that shape, and because "unsaved receipt in the primary
    /// context" is cheap to defend against and expensive to discover.
    private func discardPendingRowsInMainContextIfNeeded() {
        guard let modelContext else {
            return
        }

        let pendingReceipts = modelContext.insertedModelsArray.compactMap { $0 as? StoredReceipt }
        guard pendingReceipts.isEmpty == false else {
            return
        }

        // Deleted without a `save()`, deliberately. These rows have never been written, so there is
        // nothing on disk to remove: un-inserting them *is* the whole job, and the main context's
        // next save then commits nothing on their behalf.
        //
        // Note that a deleted-but-unsaved insert stays listed in `insertedModelsArray` — SwiftData
        // clears that bookkeeping at save time, not here. That looks like the delete did not take;
        // it did. `ReceiptResetScopeTests` saves the context afterwards and asserts the row does not
        // land, so do not "fix" this by adding a `save()` on the strength of that array alone.
        //
        // This used to run through `performRollbackSafeMutation`, whose `save()` and `rollback()` are
        // both context-wide — and this is the app's *primary* context. A receipt reset therefore
        // committed any unrelated pending edit (an account rename, a playlist change) early as a side
        // effect, and on a failing save — disk pressure being the realistic cause — rolled back every
        // unsaved change in the app rather than just these deletes. A reset's blast radius has to
        // stop at receipts.
        for receipt in pendingReceipts {
            modelContext.delete(receipt)
        }
    }
}

@MainActor
public enum ReceiptResetServices {
    public static func live(modelContext: ModelContext) -> SwiftDataReceiptResetService {
        SwiftDataReceiptResetService(modelContext: modelContext)
    }
}
