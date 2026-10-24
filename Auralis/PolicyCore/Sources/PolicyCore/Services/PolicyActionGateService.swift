import AuralisPrimaryModels
import ReceiptsCore
import RuntimeCore

/// Default policy gate service backed by a current-mode provider and receipt store.
@MainActor
public struct PolicyActionGateService: PolicyActionGating {
    private let modeProvider: @MainActor () -> CryptoMode
    private let executionEvidenceProvider: @MainActor () -> PolicyExecutionEvidence
    private let signingChainAllowlistProvider: @MainActor () -> SigningChainAllowlist
    private let receiptStore: any ReceiptStore

    public init(
        modeProvider: @escaping @MainActor () -> CryptoMode,
        executionEvidenceProvider: @escaping @MainActor () -> PolicyExecutionEvidence = { .none },
        signingChainAllowlistProvider: @escaping @MainActor () -> SigningChainAllowlist = { .denyAll },
        receiptStore: any ReceiptStore
    ) {
        self.modeProvider = modeProvider
        self.executionEvidenceProvider = executionEvidenceProvider
        self.signingChainAllowlistProvider = signingChainAllowlistProvider
        self.receiptStore = receiptStore
    }

    public func attempt(
        _ action: PolicyControlledAction,
        actor: ActorRef
    ) async -> PolicyGateResult {
        await ActionPolicyGate.attempt(
            action,
            mode: modeProvider(),
            actor: actor,
            executionEvidence: executionEvidenceProvider(),
            signingChainAllowlist: signingChainAllowlistProvider(),
            receiptStore: receiptStore
        )
    }
}
