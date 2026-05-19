import Foundation

public struct MusicAutoOrganizationDryRunProposal: Equatable, Sendable {
    public let affectedMediaIDs: [String]
    public let beforeSummary: MusicReceiptStateSummary?
    public let proposedSummary: MusicReceiptStateSummary?
    public let reason: String?

    public init(
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

public struct MusicAutoOrganizationDryRunResult: Equatable, Sendable {
    public let affectedMediaIDs: [String]
    public let beforeSummary: MusicReceiptStateSummary?
    public let proposedSummary: MusicReceiptStateSummary?
    public let dryRun: Bool

    public init(
        affectedMediaIDs: [String],
        beforeSummary: MusicReceiptStateSummary?,
        proposedSummary: MusicReceiptStateSummary?,
        dryRun: Bool
    ) {
        self.affectedMediaIDs = affectedMediaIDs
        self.beforeSummary = beforeSummary
        self.proposedSummary = proposedSummary
        self.dryRun = dryRun
    }
}

@MainActor
public protocol MusicAutoOrganizationRunning {
    func runDryRun(
        proposal: MusicAutoOrganizationDryRunProposal,
        context: MusicReceiptContext
    ) async throws -> MusicAutoOrganizationDryRunResult
}

@MainActor
public struct MusicAutoOrganizationReceiptService: MusicAutoOrganizationRunning {
    private let receiptLogger: MusicReceiptEventLogger

    public init(receiptLogger: MusicReceiptEventLogger) {
        self.receiptLogger = receiptLogger
    }

    public func runDryRun(
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
