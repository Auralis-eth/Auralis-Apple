import Foundation

/// Immutable terminal context delivered after an executor has returned or thrown.
public struct AfterToolCallContext: Equatable, Sendable {
    public let proposal: ActionProposal
    public let tool: ToolDefinition
    public let outcome: ToolCallOutcome
    public let artifactID: UUID?
    public let durationSeconds: Double
    public let authority: AuthorityRef

    public init(
        proposal: ActionProposal,
        tool: ToolDefinition,
        outcome: ToolCallOutcome,
        artifactID: UUID?,
        durationSeconds: Double,
        authority: AuthorityRef
    ) {
        self.proposal = proposal
        self.tool = tool
        self.outcome = outcome
        self.artifactID = artifactID
        self.durationSeconds = durationSeconds
        self.authority = authority
    }
}

/// Extension point invoked after real tool execution reaches a terminal state.
///
/// The pipeline emits its required receipt, worklog, artifact-link event, and performance signal
/// before notifying these hooks. Hooks are therefore additive and cannot suppress the audit trail.
public protocol AfterToolCallHook: Sendable {
    func emit(_ context: AfterToolCallContext) async -> EvidenceEmissionReport
}

public struct EvidenceEmissionReport: Equatable, Sendable {
    public let failures: [String]

    public init(failures: [String] = []) {
        self.failures = failures
    }

    public var succeeded: Bool { failures.isEmpty }
}

/// The mandatory audit hook. It owns every required post-execution emission and only then invokes
/// additive observers, so extension code cannot suppress or replace the governance record.
public struct StandardAfterToolCallHook: AfterToolCallHook {
    private let eventBus: any RuntimeEventPublishing
    private let worklog: any WorklogRecording
    private let receiptSink: any ReceiptEmitting
    private let performanceSink: any PerformanceSignalEmitting
    private let observers: [any AfterToolCallHook]

    public init(
        eventBus: any RuntimeEventPublishing,
        worklog: any WorklogRecording,
        receiptSink: any ReceiptEmitting,
        performanceSink: any PerformanceSignalEmitting,
        observers: [any AfterToolCallHook] = []
    ) {
        self.eventBus = eventBus
        self.worklog = worklog
        self.receiptSink = receiptSink
        self.performanceSink = performanceSink
        self.observers = observers
    }

    public func emit(_ context: AfterToolCallContext) async -> EvidenceEmissionReport {
        var failures: [String] = []
        let governedOutcome: GovernedOutcomeKind
        let worklogEvent: WorkflowWorklogEvent
        let reason: String?
        let outputFields: [String: String]

        switch context.outcome {
        case let .executed(artifact):
            governedOutcome = .executed
            worklogEvent = .executed(artifactID: artifact.id, durationSeconds: context.durationSeconds)
            reason = nil
            outputFields = artifact.outputFields
        case let .failed(failureReason):
            governedOutcome = .failed
            worklogEvent = .failed(reason: failureReason)
            reason = failureReason
            outputFields = [:]
        case .blocked, .needsRevision, .needsApproval, .evidenceIncomplete:
            // These outcomes happen before execution and are emitted by the before-call path.
            return EvidenceEmissionReport()
        }

        let worklogResult = await worklog.record(WorkflowStepLog(
            correlationID: context.proposal.resolvedCorrelationID,
            toolID: context.tool.id,
            event: worklogEvent,
            actor: context.proposal.actor,
            authority: context.authority
        ))
        if let failure = worklogResult.failure {
            failures.append(failure.localizedDescription)
        }
        if let artifactID = context.artifactID {
            await eventBus.publish(WorkflowEventEnvelope(
                event: .artifactCreated(id: artifactID),
                correlationID: context.proposal.resolvedCorrelationID
            ))
        }
        if context.tool.requiresReceipt || governedOutcome != .executed {
            do {
                try await receiptSink.emit(GovernedReceipt(
                    proposal: context.proposal,
                    toolID: context.tool.id,
                    outcome: governedOutcome,
                    artifactID: context.artifactID,
                    reason: reason,
                    outputFields: outputFields,
                    authority: context.authority
                ))
            } catch {
                failures.append(
                    "Required receipt or artifact link failed: \(error.localizedDescription)"
                )
            }
        }
        await performanceSink.record(PerformanceSignal(
            toolID: context.tool.id,
            capability: context.proposal.capability,
            outcome: governedOutcome,
            durationSeconds: context.durationSeconds,
            runID: context.proposal.id,
            correlationID: context.proposal.resolvedCorrelationID,
            failureReason: reason
        ))
        for observer in observers {
            let observerReport = await observer.emit(context)
            failures.append(contentsOf: observerReport.failures)
        }
        return EvidenceEmissionReport(failures: failures)
    }
}
