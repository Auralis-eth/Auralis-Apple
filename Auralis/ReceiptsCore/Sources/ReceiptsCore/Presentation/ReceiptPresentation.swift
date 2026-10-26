import Foundation

/// The single, canonical receipt view-model shared by every Auralis receipt surface.
///
/// Both the standalone Receipts tab (`Auralis/Receipts/*`) and the Mission Control console
/// (`MissionControlFeature`) build their views from this type, so section titles, ordering,
/// searchable text, the postflight outcome, the "what changed" rows, and artifact links can
/// never drift between surfaces. UI layers keep their own chrome (styling, layout, navigation)
/// and map ``ReceiptContentRow``/``ReceiptOutcomeKind`` onto their own display types.
public struct ReceiptPresentation: Equatable, Sendable {
    public let outcome: ReceiptOutcomeKind
    public let searchableText: String
    /// Non-empty categorized sections in canonical presentation order.
    public let sections: [ReceiptPresentationSection]
    public let changeRows: [ReceiptContentRow]
    public let artifactIDs: [UUID]

    public init(
        summary: String,
        trigger: String,
        scope: String,
        actor: String,
        mode: String,
        provenance: String,
        correlationID: String?,
        isSuccess: Bool,
        details: [String: ReceiptJSONValue]
    ) {
        let categorized = ReceiptContentPresenter.categorizedRows(details: details)
        let outcome = ReceiptContentPresenter.outcome(
            trigger: trigger,
            isSuccess: isSuccess,
            details: details
        )
        let changeRows = ReceiptContentPresenter.changeRows(
            trigger: trigger,
            isSuccess: isSuccess,
            details: details
        )
        let artifactIDs = ReceiptContentPresenter.artifactIDs(in: details)

        let sections = ReceiptContentCategory.presentationOrder.compactMap { category -> ReceiptPresentationSection? in
            let rows = categorized[category] ?? []
            guard !rows.isEmpty else { return nil }
            return ReceiptPresentationSection(category: category, rows: rows)
        }

        let searchableParts = [
            summary,
            trigger,
            scope,
            actor,
            mode,
            provenance,
            correlationID ?? "",
            outcome.rawValue
        ]
        + sections.flatMap { section in
            [section.title] + section.rows.flatMap { [$0.label, $0.value] }
        }
        + changeRows.flatMap { [$0.label, $0.value] }

        self.outcome = outcome
        self.searchableText = searchableParts.joined(separator: " ")
        self.sections = sections
        self.changeRows = changeRows
        self.artifactIDs = artifactIDs
    }
}

/// A categorized, human-readable section of a receipt, carrying its canonical title.
public struct ReceiptPresentationSection: Identifiable, Equatable, Sendable {
    public let category: ReceiptContentCategory
    public let rows: [ReceiptContentRow]

    public init(category: ReceiptContentCategory, rows: [ReceiptContentRow]) {
        self.category = category
        self.rows = rows
    }

    public var title: String { category.displayTitle }
    public var id: String { category.rawValue }
}

public extension ReceiptContentCategory {
    /// Canonical, human-readable section title shared by every Auralis receipt surface.
    var displayTitle: String {
        switch self {
        case .intent: return "Requested Intent"
        case .plan: return "Interpreted Plan"
        case .approval: return "Approvals"
        case .action: return "Actions"
        case .inference: return "AI Provenance"
        case .output: return "Outputs"
        case .policy: return "Policy Reasons"
        case .capability: return "Related Capabilities"
        case .failure: return "Blocked Or Failure Reasons"
        case .additional: return "Additional Details"
        }
    }

    /// Canonical top-to-bottom ordering for presenting categorized receipt content.
    static var presentationOrder: [ReceiptContentCategory] {
        [.intent, .plan, .approval, .action, .inference, .output, .policy, .capability, .failure, .additional]
    }
}
