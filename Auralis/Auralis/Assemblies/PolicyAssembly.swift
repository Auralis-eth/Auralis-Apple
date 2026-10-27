import AuralisPolicy
import RuntimeKit
import SwiftData

@MainActor
struct PolicyAssembly {
    private let receiptAssembly: ReceiptAssembly

    init(receiptAssembly: ReceiptAssembly) {
        self.receiptAssembly = receiptAssembly
    }

    /// The app's policy gate. All governed actions now flow through the one `GovernedToolPipeline`
    /// via ``PipelineBackedPolicyGate`` on the shared ``RuntimeHost`` (#3): the crypto-scoped
    /// `DomainJudge` gates wallet actions in Observe exactly as before, but there is now a single
    /// governance path (judge + deterministic checks + receipts + events).
    func makePolicyActionHandler(
        modelContext: ModelContext,
        modeState: ModeState
    ) -> any PolicyActionGating {
        PipelineBackedPolicyGate(
            host: RuntimeAssembly.sharedHost(
                modelContext: modelContext,
                receiptStore: receiptAssembly.makeReceiptStore(modelContext: modelContext),
                cryptoModeProvider: { modeState.mode },
                cryptoModeSetter: { modeState.setMode($0) }
            )
        )
    }
}
