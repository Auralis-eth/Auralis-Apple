import CapabilitiesCore
import RuntimeCore

/// One option the planner weighed while deciding what to do, and whether it made the cut.
///
/// Capturing *rejected* options — not just the chosen plan — is what lets Mission Control show how
/// the planner reasoned operationally: which templates or tools it considered, and why it dropped
/// the ones it didn't use. A plan alone answers "what will happen"; the candidates answer "what else
/// was on the table, and why not".
public struct PlanCandidate: Equatable, Sendable {
    /// A short, user-facing label for the option (a template id, a proposed step title, …).
    public let title: String
    /// The capability the option would exercise, when one is known.
    public let capability: CapabilityID?
    /// Whether the option was chosen for the plan.
    public let isSelected: Bool
    /// Why the option was selected, or — for rejected options — why it was dropped.
    public let rationale: String

    public init(
        title: String,
        capability: CapabilityID? = nil,
        isSelected: Bool,
        rationale: String
    ) {
        self.title = title
        self.capability = capability
        self.isSelected = isSelected
        self.rationale = rationale
    }
}

/// The planner's deliberation over a goal: every option it considered, each tagged selected or
/// rejected. Threaded onto ``Plan`` so a caller (or the runtime worklog) can surface the reasoning
/// without re-running the planner.
public struct PlanDeliberation: Equatable, Sendable {
    /// The planner that actually wrote this plan's steps ("deterministic", "model", …).
    ///
    /// The single source of truth for run attribution, and the only one: ``GoalPlanning/name`` is a
    /// constant chosen before planning starts and cannot know that a model-backed planner would
    /// degrade to its template fallback, so attributing from it reported a model on runs the
    /// templates planned. Read this instead — including for the proposal actor — so a proposal and
    /// the `considered` worklog entry for the same run carry one identity.
    public let planner: String
    public let candidates: [PlanCandidate]
    public let telemetry: InferenceTelemetry?

    public init(
        planner: String,
        candidates: [PlanCandidate] = [],
        telemetry: InferenceTelemetry? = nil
    ) {
        self.planner = planner
        self.candidates = candidates
        self.telemetry = telemetry
    }

    /// An empty deliberation, for plans produced without recording their reasoning.
    public static let none = PlanDeliberation(planner: "", candidates: [])

    public var isEmpty: Bool { candidates.isEmpty }
    public var selected: [PlanCandidate] { candidates.filter(\.isSelected) }
    public var rejected: [PlanCandidate] { candidates.filter { !$0.isSelected } }
}
