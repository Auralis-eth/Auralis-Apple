import Foundation

/// A declaration of what a successful outcome looks like for a goal, workflow, or playbook.
///
/// No longer a stub. ``criteria`` carries the machine-checkable form that `AuralisRuntime`'s evaluator
/// grades a worklog trace against; ``proseCriteria`` retains the free-text form this type originally
/// held, which stays useful as authored intent a person can read but nothing can decide.
///
/// Both are kept rather than one replacing the other. Prose states *why* a run matters in language
/// no enum will capture, and the criteria state what can actually be verified — collapsing them
/// would either discard the reasoning or pretend a sentence is executable.
public struct OutcomeSpec: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public let summary: String
    /// Expectations the evaluator can decide from recorded evidence.
    public let criteria: [SuccessCriterion]
    /// Authored intent that is not mechanically checkable. Descriptive; never graded.
    public let proseCriteria: [String]

    public init(
        id: UUID = UUID(),
        summary: String,
        criteria: [SuccessCriterion] = [],
        proseCriteria: [String] = []
    ) {
        self.id = id
        self.summary = summary
        self.criteria = criteria
        self.proseCriteria = proseCriteria
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case summary
        case criteria
        /// The original key, from when this type held only prose. Still read *and* written, so a spec
        /// survives a round trip through a build on either side of this migration.
        case successCriteria
    }

    /// Tolerant decoding across the prose → structured migration.
    ///
    /// Legacy prose is *not* converted into criteria. Inferring a criterion from a sentence would
    /// fabricate an expectation the author never declared and then grade real runs against it, so a
    /// spec written before ``criteria`` existed decodes with none — which the evaluator reports as
    /// inconclusive rather than as a pass.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        summary = try container.decode(String.self, forKey: .summary)
        criteria = try container.decodeIfPresent([SuccessCriterion].self, forKey: .criteria) ?? []
        proseCriteria = try container.decodeIfPresent([String].self, forKey: .successCriteria) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(summary, forKey: .summary)
        try container.encode(criteria, forKey: .criteria)
        try container.encode(proseCriteria, forKey: .successCriteria)
    }
}

/// A lightweight evaluation snapshot for a session/outcome. (P0.5-902)
///
/// This is the intentionally small, framework-free P0.5 contract. `AuralisRuntime.EvalResult` carries a
/// criterion-by-criterion verdict, while `AuralisRuntime.PerformanceEvent` records operational
/// playbook history and aggregates. Those richer records do not replace this type's role as the
/// portable summary primitive at the runtime boundary.
public struct PerformanceRecord: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public let sessionID: UUID?
    public let outcomeID: UUID?
    public let succeeded: Bool
    public let durationSeconds: Double
    public let recordedAt: Date

    public init(
        id: UUID = UUID(),
        sessionID: UUID? = nil,
        outcomeID: UUID? = nil,
        succeeded: Bool,
        durationSeconds: Double,
        recordedAt: Date = .now
    ) {
        self.id = id
        self.sessionID = sessionID
        self.outcomeID = outcomeID
        self.succeeded = succeeded
        self.durationSeconds = durationSeconds
        self.recordedAt = recordedAt
    }
}
