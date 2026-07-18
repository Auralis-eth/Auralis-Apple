import AccountsCore
import AuralisShellCore
import NFTDomain
import NFTPersistence
import NFTPresentation
import NFTProviderAdapters
import ReceiptsCore
import ReceiptStorage
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

    func makeReceiptStore(
        modelContext: ModelContext,
        integrityHeadStore: any ReceiptIntegrityHeadStoring
    ) -> any ReceiptStore {
        SwiftDataReceiptStore(
            modelContext: modelContext,
            persistenceStore: ReceiptPersistenceStore(
                modelContainer: modelContext.container,
                integrityHeadStore: integrityHeadStore
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

    func makeAccountEventRecorder(modelContext: ModelContext) -> any AccountEventRecorder {
        ReceiptBackedAccountEventRecorder(receiptStore: makeReceiptStore(modelContext: modelContext))
    }

    func makeNFTRefreshEventRecorder(modelContext: ModelContext) -> any NFTRefreshEventRecording {
        ReceiptBackedNFTRefreshEventRecorder(receiptStore: makeReceiptStore(modelContext: modelContext))
    }
}
