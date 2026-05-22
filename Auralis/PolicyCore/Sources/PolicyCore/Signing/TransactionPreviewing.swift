import AuralisPrimaryModels

/// Protocol boundary for future transaction preview or simulation services.
///
/// No concrete draft transaction model exists yet. Future signing work should
/// bind its draft type here and feed the resulting preview evidence into
/// `PolicyExecutionReadiness` before constructing an executable transaction.
public protocol TransactionPreviewing: Sendable {
    associatedtype DraftTransaction: Sendable

    func preview(
        for draftTransaction: DraftTransaction,
        on chain: Chain
    ) async throws -> DraftTransactionPreviewEvidence
}
