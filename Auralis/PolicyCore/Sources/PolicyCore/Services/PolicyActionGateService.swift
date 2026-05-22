import ReceiptsCore

/// Default policy gate service backed by a current-mode provider and receipt store.
@MainActor
public struct PolicyActionGateService: PolicyActionGating {
    private let modeProvider: @MainActor () -> AppMode
    private let receiptStore: any ReceiptStore

    public init(
        modeProvider: @escaping @MainActor () -> AppMode,
        receiptStore: any ReceiptStore
    ) {
        self.modeProvider = modeProvider
        self.receiptStore = receiptStore
    }

    public func attempt(_ action: PolicyControlledAction) async -> PolicyGateResult {
        await ActionPolicyGate.attempt(
            action,
            mode: modeProvider(),
            executionEvidence: .none,
            signingChainAllowlist: .denyAll,
            receiptStore: receiptStore
        )
    }
}
