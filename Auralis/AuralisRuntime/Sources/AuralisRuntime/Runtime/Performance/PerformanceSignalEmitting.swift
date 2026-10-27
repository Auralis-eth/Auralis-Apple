import AuralisFoundation
import Foundation

/// The boundary that refused a governed call. This remains AuralisRuntime-owned so the kernel does not
/// depend outward on AuralisRuntime; adapters map it into their persistence taxonomy.
public enum PerformanceBlockSource: String, Equatable, Sendable {
    case policy
    case authority
    case infrastructure
    case other
}

/// A performance signal emitted by the AfterToolCall phase of the pipeline for one governed tool
/// call (P0.5-204 "performance signals"). Kept free of any AuralisRuntime type so `AuralisRuntime`
/// stays a leaf; the app layer's adapter (`PerformancePipelineSink`) translates this into a
/// `PerformanceEvent` and records it.
public struct PerformanceSignal: Equatable, Sendable {
    public let toolID: String
    public let capability: CapabilityID
    /// The terminal disposition this signal describes: `.executed`, `.failed`, `.blocked`, or
    /// `.needsRevision` (a proposal sent back for correction by the input-schema gate or the Judge).
    public let outcome: GovernedOutcomeKind
    /// Wall-clock latency from the start of the governed run to this terminal outcome (includes
    /// deterministic checks and the judge decision, not just executor time).
    public let durationSeconds: Double
    /// The proposal id, so a later human action (e.g. approving the run's artifact) can be
    /// attributed back to the exact run that produced it.
    public let runID: UUID?
    public let correlationID: String?
    /// A short, stable reason a run failed or was blocked. Nil for successful runs. The primary
    /// grouping key for failure patterns downstream.
    public let failureReason: String?
    public let blockSource: PerformanceBlockSource?

    public init(
        toolID: String,
        capability: CapabilityID,
        outcome: GovernedOutcomeKind,
        durationSeconds: Double,
        runID: UUID? = nil,
        correlationID: String? = nil,
        failureReason: String? = nil,
        blockSource: PerformanceBlockSource? = nil
    ) {
        self.toolID = toolID
        self.capability = capability
        self.outcome = outcome
        self.durationSeconds = durationSeconds
        self.runID = runID
        self.correlationID = correlationID
        self.failureReason = failureReason
        self.blockSource = blockSource
    }
}

/// Sink for performance signals. The AfterToolCall phase of the pipeline emits one of these per
/// terminal tool-call outcome, alongside the receipt and worklog emissions.
public protocol PerformanceSignalEmitting: Sendable {
    func record(_ signal: PerformanceSignal) async
}

/// In-memory performance-signal sink for tests and previews.
public actor InMemoryPerformanceSignalEmitter: PerformanceSignalEmitting {
    private var signals: [PerformanceSignal] = []

    public init() { }

    public func record(_ signal: PerformanceSignal) {
        signals.append(signal)
    }

    public func allSignals() -> [PerformanceSignal] {
        signals
    }
}
