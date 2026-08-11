import CapabilitiesCore
import Foundation

/// One inspectable step in a ``Plan``.
///
/// Every step names the ``CapabilityID`` it would exercise, so the same canonical
/// vocabulary the policy, capability, and receipt layers already speak also describes
/// what an agent intends to do — before it does anything. The `title` and `rationale`
/// are for the user-facing plan review ("here's what I'll do, and why").
public struct PlanStep: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let capability: CapabilityID
    public let kind: PlanStepKind
    /// A short, user-facing description of the step, e.g. "Create the playlist".
    public let title: String
    /// Why this step is part of the plan, shown in the plan review.
    public let rationale: String

    public init(
        id: UUID = UUID(),
        capability: CapabilityID,
        kind: PlanStepKind,
        title: String,
        rationale: String
    ) {
        self.id = id
        self.capability = capability
        self.kind = kind
        self.title = title
        self.rationale = rationale
    }
}
