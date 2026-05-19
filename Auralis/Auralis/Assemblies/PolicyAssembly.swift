import PolicyCore
import SwiftData

@MainActor
struct PolicyAssembly {
    private let receiptAssembly: ReceiptAssembly

    init(receiptAssembly: ReceiptAssembly) {
        self.receiptAssembly = receiptAssembly
    }

    func makePolicyActionHandler(
        modelContext: ModelContext,
        modeState: ModeState
    ) -> any PolicyActionGating {
        PolicyActionGateService(
            modeProvider: { modeState.mode },
            receiptStore: receiptAssembly.makeReceiptStore(modelContext: modelContext)
        )
    }
}
