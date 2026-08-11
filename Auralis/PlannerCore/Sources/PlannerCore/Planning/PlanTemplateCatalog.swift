import CapabilitiesCore

/// A named, keyword-triggered blueprint for a common goal. Templates make the
/// deterministic planner's behavior legible and testable: a goal that mentions any of
/// `keywords` produces `steps`. The step order encodes the Observe → Assist → Confirm
/// ladder within a single task (look first, recommend, then change state).
public struct PlanTemplate: Equatable, Sendable {
    public let id: String
    public let keywords: [String]
    public let summary: String
    public let steps: [PlanStep]

    public init(id: String, keywords: [String], summary: String, steps: [PlanStep]) {
        self.id = id
        self.keywords = keywords
        self.summary = summary
        self.steps = steps
    }

    /// Whether the goal text triggers this template (any keyword appears as a substring).
    public func matches(_ normalizedGoal: String) -> Bool {
        keywords.contains { normalizedGoal.contains($0) }
    }
}

/// The built-in template catalog, expressed against Auralis's canonical capabilities.
///
/// This is intentionally small and demonstrative — the point of the package is the
/// planning/orchestration machinery, not an exhaustive skill library. New templates are
/// added here without touching the planner or orchestrator.
public enum PlanTemplateCatalog {
    public static let builtIn: [PlanTemplate] = [
        PlanTemplate(
            id: "organize-library",
            keywords: ["organize", "organise", "clean up", "tidy", "sort my"],
            summary: "Review the library, propose an organization, then apply it.",
            steps: [
                PlanStep(
                    capability: .musicLibraryClassification,
                    kind: .observe,
                    title: "Classify the library",
                    rationale: "Understand what's in the library before changing anything."
                ),
                PlanStep(
                    capability: .autoOrganization,
                    kind: .assist,
                    title: "Propose an organization",
                    rationale: "Draft a tidy structure for you to review."
                ),
                PlanStep(
                    capability: .autoOrganization,
                    kind: .execute,
                    title: "Apply the organization",
                    rationale: "Reorganize the library once you approve the plan."
                ),
            ]
        ),
        PlanTemplate(
            id: "make-playlist",
            keywords: ["playlist", "mix", "queue up a set"],
            summary: "Find matching tracks, draft a playlist, then create it.",
            steps: [
                PlanStep(
                    capability: .musicLibraryClassification,
                    kind: .observe,
                    title: "Find matching tracks",
                    rationale: "Select tracks that fit the request."
                ),
                PlanStep(
                    capability: .playlistManagement,
                    kind: .assist,
                    title: "Draft the playlist",
                    rationale: "Assemble a draft tracklist for you to review."
                ),
                PlanStep(
                    capability: .playlistManagement,
                    kind: .execute,
                    title: "Create the playlist",
                    rationale: "Save the playlist once you approve it."
                ),
            ]
        ),
        PlanTemplate(
            id: "export-library",
            keywords: ["export", "back up", "backup", "download my"],
            summary: "Review what would be exported, then create the export.",
            steps: [
                PlanStep(
                    capability: .musicLibraryClassification,
                    kind: .observe,
                    title: "Review exportable items",
                    rationale: "Confirm what's included before exporting."
                ),
                PlanStep(
                    capability: .musicExport,
                    kind: .execute,
                    title: "Create the export",
                    rationale: "Produce the export once you approve it."
                ),
            ]
        ),
        PlanTemplate(
            id: "send-value",
            keywords: ["tip", "send", "pay", "transfer", "donate"],
            summary: "Draft a transaction and prepare it for signing.",
            steps: [
                PlanStep(
                    capability: .draftTransaction,
                    kind: .assist,
                    title: "Draft the transaction",
                    rationale: "Prepare the details for you to review."
                ),
                PlanStep(
                    capability: .signMessage,
                    kind: .execute,
                    title: "Sign and submit",
                    rationale: "Sign the prepared transaction once you approve it."
                ),
            ]
        ),
    ]
}
