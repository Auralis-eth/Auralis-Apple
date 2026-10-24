import CapabilitiesCore
import Foundation

/// A request from the runtime for the app to present a *trusted*, schema-driven UI surface.
///
/// Operator packs and workflows cannot render arbitrary UI; they can only ask for one of these
/// known request kinds, which the app renders with its own trusted components (PermissionCard,
/// ApprovalSheet, ReceiptCard, …). This enum is the schema; the SwiftUI components that consume it —
/// and the governed `TrustedUIComponentRegistry` that maps each case onto one — live in the
/// `TrustedUIKit` package (P0.5-502).
///
/// Receipts and drafts are referenced by identifier so this type stays free of the receipt/storage
/// packages — the presenting layer resolves the id.
public enum TrustedUIRequest: Equatable, Sendable {
    case approveAction(ApprovalRequest)
    case editDraft(proposalID: UUID)
    case inspectCapability(CapabilityID)
    case reviewReceipt(receiptID: UUID)
    case inspectContextBundle(ContextBundle)
    case presentSuggestion(TrustedUISuggestion)
    case presentRiskBanner(ActionImpactClass)
}

/// A proactive, non-blocking suggestion the runtime asks the app to present via a trusted
/// `SuggestionCard`. Carries only data — the trusted presenting layer supplies the action handler,
/// never the suggestion's author. Lives in RuntimeCore (not TrustedUIKit) so it can be carried by a
/// ``TrustedUIRequest`` case without a dependency cycle.
public struct TrustedUISuggestion: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let detail: String
    /// When present, the card offers a single action button with this label.
    public let actionLabel: String?

    public init(id: UUID = UUID(), title: String, detail: String, actionLabel: String? = nil) {
        self.id = id
        self.title = title
        self.detail = detail
        self.actionLabel = actionLabel
    }
}
