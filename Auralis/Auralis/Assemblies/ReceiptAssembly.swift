import AccountsCore
import AuralisShellCore
import NFTKit
import ReceiptsCore
import ReceiptStorage
import SwiftData

@MainActor
struct ReceiptAssembly {
    func makeReceiptStore(modelContext: ModelContext) -> any ReceiptStore {
        ReceiptStores.live(modelContext: modelContext)
    }

    func makeReceiptEventLogger(modelContext: ModelContext) -> ReceiptEventLogger {
        ReceiptEventLogger(receiptStore: makeReceiptStore(modelContext: modelContext))
    }

    func makeShellReceiptLogger(modelContext: ModelContext) -> ReceiptEventShellLogger {
        ReceiptEventShellLogger(receiptEventLogger: makeReceiptEventLogger(modelContext: modelContext))
    }

    func makeAccountEventRecorder(modelContext: ModelContext) -> any AccountEventRecorder {
        AccountEventRecorders.live(modelContext: modelContext)
    }

    func makeNFTRefreshEventRecorder(modelContext: ModelContext) -> any NFTRefreshEventRecording {
        ReceiptBackedNFTRefreshEventRecorder(receiptStore: makeReceiptStore(modelContext: modelContext))
    }
}
