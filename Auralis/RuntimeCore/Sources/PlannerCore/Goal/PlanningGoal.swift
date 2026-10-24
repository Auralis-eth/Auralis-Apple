import Foundation

/// A user-stated goal to be decomposed into an inspectable, capability-grounded plan.
///
/// A goal is deliberately thin: the natural-language ask plus optional context about
/// where it originated. Planners turn a `PlanningGoal` into a ``Plan``; they never act
/// on it directly. Acting is the orchestrator's job, and every state-changing step is
/// gated before it runs.
public struct PlanningGoal: Equatable, Sendable {
    /// The natural-language goal, e.g. "organize my music library".
    public let text: String

    /// Optional hint about the surface the goal came from (a screen, a command),
    /// carried through to receipts and authorization context.
    public let surface: String?

    public init(text: String, surface: String? = nil) {
        self.text = text
        self.surface = surface
    }

    /// The goal text folded to lowercase for keyword matching by deterministic planners.
    public var normalizedText: String {
        text.lowercased()
    }
}
