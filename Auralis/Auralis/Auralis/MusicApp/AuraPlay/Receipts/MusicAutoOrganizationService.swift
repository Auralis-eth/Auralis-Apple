import Foundation

struct MusicAutoOrganizationDryRunProposal: Equatable, Sendable {
    let affectedMediaIDs: [String]
    let beforeSummary: MusicReceiptStateSummary?
    let proposedSummary: MusicReceiptStateSummary?
    let reason: String?

    init(
        affectedMediaIDs: [String],
        beforeSummary: MusicReceiptStateSummary? = nil,
        proposedSummary: MusicReceiptStateSummary? = nil,
        reason: String? = nil
    ) {
        self.affectedMediaIDs = affectedMediaIDs
        self.beforeSummary = beforeSummary
        self.proposedSummary = proposedSummary
        self.reason = reason
    }
}

struct MusicAutoOrganizationDryRunResult: Equatable, Sendable {
    let affectedMediaIDs: [String]
    let beforeSummary: MusicReceiptStateSummary?
    let proposedSummary: MusicReceiptStateSummary?
    let dryRun: Bool
}

@MainActor
protocol MusicAutoOrganizationRunning {
    func runDryRun(
        proposal: MusicAutoOrganizationDryRunProposal,
        context: MusicReceiptContext
    ) async throws -> MusicAutoOrganizationDryRunResult
}

@MainActor
struct ReceiptBackedMusicAutoOrganizationService: MusicAutoOrganizationRunning {
    private let receiptLogger: MusicReceiptEventLogger

    init(receiptLogger: MusicReceiptEventLogger) {
        self.receiptLogger = receiptLogger
    }

    func runDryRun(
        proposal: MusicAutoOrganizationDryRunProposal,
        context: MusicReceiptContext
    ) async throws -> MusicAutoOrganizationDryRunResult {
        let result = MusicAutoOrganizationDryRunResult(
            affectedMediaIDs: Array(Set(proposal.affectedMediaIDs)).sorted(),
            beforeSummary: proposal.beforeSummary,
            proposedSummary: proposal.proposedSummary,
            dryRun: true
        )

        _ = try await receiptLogger.recordAutoOrganizationRun(
            affectedMediaIDs: result.affectedMediaIDs,
            beforeSummary: result.beforeSummary,
            afterSummary: result.proposedSummary,
            reason: proposal.reason,
            context: MusicReceiptContext(
                triggerCause: .dryRun,
                actor: context.actor,
                accountAddress: context.accountAddress,
                chain: context.chain,
                correlationID: context.correlationID,
                surface: context.surface
            )
        )

        return result
    }
}
