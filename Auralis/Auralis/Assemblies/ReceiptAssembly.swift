import AccountsCore
import AuralisPrimaryModels
import AuralisShellCore
import NFTDomain
import NFTPersistence
import NFTPresentation
import NFTProviderAdapters
import AuralisReceipts
import SwiftData

@MainActor
struct ReceiptAssembly {
    private let receiptStoreFactory: @MainActor (ModelContext) -> any ReceiptStore

    init(
        receiptStoreFactory: (@MainActor (ModelContext) -> any ReceiptStore)? = nil
    ) {
        self.receiptStoreFactory = receiptStoreFactory ?? { modelContext in
            ReceiptStores.live(modelContext: modelContext)
        }
    }

    func makeReceiptStore(modelContext: ModelContext) -> any ReceiptStore {
        receiptStoreFactory(modelContext)
    }

    /// A store with caller-supplied integrity anchors, for tests and previews.
    ///
    /// The signing identity is a throwaway and is passed explicitly: this factory bypasses
    /// ``ReceiptStores/live(modelContext:)``, so it gets neither the shared ledger queue nor the
    /// device signing key, and receipts it writes are not attestable after the instance goes away.
    /// Production goes through `makeReceiptStore(modelContext:)`.
    func makeReceiptStore(
        modelContext: ModelContext,
        integrityHeadStore: any ReceiptIntegrityHeadStoring
    ) -> any ReceiptStore {
        SwiftDataReceiptStore(
            persistenceStore: ReceiptPersistenceStore(
                modelContainer: modelContext.container,
                integrityHeadStore: integrityHeadStore,
                signer: ReceiptSignerFactory.ephemeralSigner()
            )
        )
    }

    func makeEphemeralReceiptStore(modelContext: ModelContext) -> any ReceiptStore {
        makeReceiptStore(
            modelContext: modelContext,
            integrityHeadStore: InMemoryReceiptIntegrityHeadStore()
        )
    }

    func makeReceiptEventLogger(modelContext: ModelContext) -> ReceiptEventLogger {
        ReceiptEventLogger(receiptStore: makeReceiptStore(modelContext: modelContext))
    }

    func makeShellReceiptLogger(modelContext: ModelContext) -> ReceiptEventShellLogger {
        ReceiptEventShellLogger(receiptEventLogger: makeReceiptEventLogger(modelContext: modelContext))
    }

    /// Defaults to the persisted mode, not a hardcoded `.observe`. `mode` is inside the receipt
    /// integrity hash, so a defaulted literal stamps the wrong mode into evidence whose whole job is
    /// to record which mode the user was in. `AccountAssembly` already threads the real provider; this
    /// default is the backstop for any call site that omits it.
    func makeAccountEventRecorder(
        modelContext: ModelContext,
        modeProvider: @escaping @MainActor () -> ReceiptMode = { PersistedCryptoMode.currentReceiptMode }
    ) -> any AccountEventRecorder {
        ReceiptBackedAccountEventRecorder(
            receiptStore: makeReceiptStore(modelContext: modelContext),
            modeProvider: modeProvider
        )
    }

    func makeNFTRefreshEventRecorder(modelContext: ModelContext) -> any NFTRefreshEventRecording {
        ReceiptBackedNFTRefreshEventRecorder(receiptStore: makeReceiptStore(modelContext: modelContext))
    }
}
