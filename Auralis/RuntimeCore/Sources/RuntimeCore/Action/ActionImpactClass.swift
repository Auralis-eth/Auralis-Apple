/// The blast radius of a proposed action.
///
/// This is the typed successor to the ad hoc `requiresHighRiskReceipt` / `isBlockedInObserveMode`
/// booleans that `PolicyControlledAction` carries today. Impact class is what UI, policy, approvals,
/// and (later) runtime routing all read to decide how much ceremony an action needs.
///
/// The derived requirements below are intentionally conservative defaults. They describe the *floor*
/// of what governance should demand for a class of action; a policy gate may always demand more.
public enum ActionImpactClass: String, Codable, CaseIterable, Equatable, Sendable, Comparable {
    /// Reads only. Nothing changes; safe to run unattended.
    case readOnly = "read_only"

    /// Writes local, undoable state (e.g. a draft, a local reorder).
    case reversibleWrite = "reversible_write"

    /// Reaches outside the device or produces an effect a user would want to see first
    /// (e.g. opening an external link, exporting data).
    case externalImpact = "external_impact"

    /// Irreversible or funds-affecting (e.g. signing, spending approval).
    case highRisk = "high_risk"

    /// Whether a durable receipt should be recorded for actions of this class.
    public var requiresReceipt: Bool {
        switch self {
        case .readOnly:
            return false
        case .reversibleWrite, .externalImpact, .highRisk:
            return true
        }
    }

    /// Ordered by blast radius, so two classes can be compared and a *floor* applied — the
    /// `max(declared, minimum)` that keeps a caller's claim about an action from sinking below what
    /// the capability makes possible. Declared explicitly rather than taken from `allCases` order so
    /// reordering the cases for readability cannot silently reorder severity.
    ///
    /// Deliberately not `Int`-backed on the case itself: the raw value is the persisted wire form
    /// and must stay a stable string.
    private var severityRank: Int {
        switch self {
        case .readOnly: return 0
        case .reversibleWrite: return 1
        case .externalImpact: return 2
        case .highRisk: return 3
        }
    }

    public static func < (lhs: ActionImpactClass, rhs: ActionImpactClass) -> Bool {
        lhs.severityRank < rhs.severityRank
    }

    /// Whether an explicit human confirmation step should precede execution.
    public var requiresConfirmation: Bool {
        switch self {
        case .readOnly, .reversibleWrite:
            return false
        case .externalImpact, .highRisk:
            return true
        }
    }
}
