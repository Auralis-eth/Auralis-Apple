import CryptoKit
import Foundation

public enum ImprovementRecommendationCategory: String, Equatable, Sendable, Codable, CaseIterable {
    case reliability
    case observability
    case latency
    case outcomeQuality
}

public enum ImprovementProposedChange: Equatable, Sendable, Codable {
    case reviewOperatorInstructions
    case repairWorklogInstrumentation
    case reviewLatencyBudget
    case reviewSuccessCriteria
}

public enum ImprovementRecommendationState: String, Equatable, Sendable, Codable {
    case proposed
    case accepted
    case rejected
    case superseded
    case applied
}

/// A deterministic, evidence-linked suggestion. It is data only and cannot mutate policy,
/// capabilities, operators, or playbooks.
public struct ImprovementRecommendation: Identifiable, Equatable, Sendable, Codable {
    public let id: String
    public let operatorID: String
    public let evidenceWorkflowIDs: [String]
    public let category: ImprovementRecommendationCategory
    public let summary: String
    public let proposedChange: ImprovementProposedChange
    public let confidence: Double
    public let state: ImprovementRecommendationState
    public let createdAt: Date
    public let reviewedAt: Date?
    public let reviewedBy: String?

    public init(
        id: String,
        operatorID: String,
        evidenceWorkflowIDs: [String],
        category: ImprovementRecommendationCategory,
        summary: String,
        proposedChange: ImprovementProposedChange,
        confidence: Double,
        state: ImprovementRecommendationState = .proposed,
        createdAt: Date = .now,
        reviewedAt: Date? = nil,
        reviewedBy: String? = nil
    ) {
        self.id = id
        self.operatorID = operatorID
        self.evidenceWorkflowIDs = evidenceWorkflowIDs.sorted()
        self.category = category
        self.summary = summary
        self.proposedChange = proposedChange
        // `min`/`max` do not clamp NaN — both comparisons against it are false, so it passes straight
        // through — and a NaN confidence would make this value unequal to itself, breaking the
        // `Equatable` comparison the refresh path uses to recognise a proposal it already stored, and
        // throwing on any JSON encode of the durable row. Non-finite means "no basis", so it floors.
        self.confidence = confidence.isFinite ? min(max(confidence, 0), 1) : 0
        self.state = state
        self.createdAt = createdAt
        self.reviewedAt = reviewedAt
        self.reviewedBy = reviewedBy
    }

    public func transitioning(
        to state: ImprovementRecommendationState,
        reviewedBy: String,
        at date: Date = .now
    ) -> ImprovementRecommendation {
        ImprovementRecommendation(
            id: id,
            operatorID: operatorID,
            evidenceWorkflowIDs: evidenceWorkflowIDs,
            category: category,
            summary: summary,
            proposedChange: proposedChange,
            confidence: confidence,
            state: state,
            createdAt: createdAt,
            reviewedAt: date,
            reviewedBy: reviewedBy
        )
    }
}

public protocol ImprovementRecommendationStoring: Sendable {
    func upsert(_ recommendation: ImprovementRecommendation) async
    /// Every recommendation, newest first.
    ///
    /// Fetched once per Mission Control refresh and then filtered per card in memory, which is why
    /// there is deliberately no `recommendations(forOperatorID:)` here: every card is rendered in
    /// the same pass, so narrowing per operator would turn one query into one per card.
    func allRecommendations() async -> [ImprovementRecommendation]
    func recommendation(id: String) async -> ImprovementRecommendation?
    func resetAll() async
}

public actor InMemoryImprovementRecommendationStore: ImprovementRecommendationStoring {
    private var values: [String: ImprovementRecommendation] = [:]

    public init() { }
    public func upsert(_ recommendation: ImprovementRecommendation) { values[recommendation.id] = recommendation }
    public func allRecommendations() -> [ImprovementRecommendation] {
        values.values.sorted { $0.createdAt > $1.createdAt }
    }
    public func recommendation(id: String) -> ImprovementRecommendation? { values[id] }
    public func resetAll() { values.removeAll() }
}

/// Pure recommendation derivation: identical report-card evidence produces identical IDs and text.
public struct ImprovementRecommendationEngine: Sendable {
    /// How many of an operator's most recent graded runs a recommendation cites.
    ///
    /// A recommendation's ID embeds its evidence on purpose, so that new evidence produces a *new*
    /// proposal instead of silently rewriting one a person already reviewed. Embedding **every**
    /// graded run made that key grow without bound: eval results are deliberately never pruned
    /// (see ``EvalResultStoring``), so an operator with N graded runs produced an N-workflow ID and
    /// an N-entry evidence array — and a fresh durable row carrying both on every refresh that saw
    /// a new run. Total storage for a list of advisory suggestions therefore grew as N².
    ///
    /// Capping at the most recent runs keeps the ID a bounded width and the payload a bounded size
    /// while preserving the property the ID exists for: a new run still changes the evidence set,
    /// so it still supersedes and re-proposes. Twenty-five is comfortably above the point where
    /// ``confidence`` saturates — it reaches its 0.95 ceiling at nine workflows — so the cap cannot
    /// change *what* a recommendation says or how confident it is, only how much it cites.
    public static let maximumCitedWorkflows = 25

    public init() { }

    public func recommendations(for card: OperatorReportCard, createdAt: Date = .now) -> [ImprovementRecommendation] {
        // `evalResults` is newest-first (`OperatorReportCard.init` sorts it), so the prefix is the
        // most recent evidence; sorting afterwards keeps the set order-stable for the digest.
        let workflows = card.evalResults
            .prefix(Self.maximumCitedWorkflows)
            .map(\.correlationID)
            .sorted()
        var output: [ImprovementRecommendation] = []
        if card.incompleteTraceCount > 0 {
            output.append(make(card, workflows, .observability, .repairWorklogInstrumentation,
                "Repair incomplete worklog evidence before trusting this operator's grades.", createdAt))
        }
        if !card.recurringFailures.isEmpty {
            output.append(make(card, workflows, .reliability, .reviewOperatorInstructions,
                "Review recurring execution failures and tighten the operator's instructions.", createdAt))
        }
        // A *provable* miss only. `shortfalls` also lists criteria the trace merely could not decide,
        // and a latency criterion goes inconclusive whenever a run recorded no trace at all — so
        // matching on the criterion alone would tell someone to review a latency budget on the
        // evidence of a logging regression, pointing them away from the instrumentation that is
        // actually broken. This mirrors the outcome-quality branch below.
        if card.shortfalls.contains(where: {
            if case .completedWithin = $0.criterion { $0.missCount > 0 } else { false }
        }) {
            output.append(make(card, workflows, .latency, .reviewLatencyBudget,
                "Review the latency budget and the slow steps evidenced by recent runs.", createdAt))
        }
        if card.shortfalls.contains(where: { $0.missCount > 0 }) {
            output.append(make(card, workflows, .outcomeQuality, .reviewSuccessCriteria,
                "Review repeated outcome shortfalls before changing this operator.", createdAt))
        }
        return output
    }

    private func make(
        _ card: OperatorReportCard,
        _ workflows: [String],
        _ category: ImprovementRecommendationCategory,
        _ change: ImprovementProposedChange,
        _ summary: String,
        _ createdAt: Date
    ) -> ImprovementRecommendation {
        ImprovementRecommendation(
            id: "\(card.playbookID)|\(category.rawValue)|\(Self.evidenceDigest(workflows))",
            operatorID: card.playbookID,
            evidenceWorkflowIDs: workflows,
            category: category,
            summary: summary,
            proposedChange: change,
            confidence: workflows.isEmpty ? 0.25 : min(0.95, 0.5 + Double(workflows.count) * 0.05),
            createdAt: createdAt
        )
    }

    /// A short, fixed-width fingerprint of an evidence set.
    ///
    /// Digested rather than joined because this string is part of the `@Attribute(.unique)` primary
    /// key of the durable recommendation row, and a primary key should not be as long as the data
    /// it identifies. Identical evidence still yields an identical digest, which is exactly the
    /// property `RuntimeHost.refreshImprovementRecommendations` relies on to recognise a
    /// recommendation it has already proposed. Eight bytes is ample: a collision would only mean a
    /// re-proposal is skipped, never that authority or a review decision is confused.
    static func evidenceDigest(_ workflows: [String]) -> String {
        SHA256.hash(data: Data(workflows.joined(separator: ",").utf8))
            .prefix(8)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
