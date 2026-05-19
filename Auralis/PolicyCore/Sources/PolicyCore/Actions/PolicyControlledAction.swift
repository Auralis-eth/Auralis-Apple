import CapabilitiesCore

/// Actions evaluated by the app policy gate before execution-style behavior runs.
public enum PolicyControlledAction: String, CaseIterable, Sendable {
    case signMessage = "sign_message"
    case approveSpending = "approve_spending"
    case draftTransaction = "draft_transaction"
    case runPlugin = "run_plugin"

    public var title: String {
        switch self {
        case .signMessage:
            return "Sign Message"
        case .approveSpending:
            return "Approve Spending"
        case .draftTransaction:
            return "Draft Transaction"
        case .runPlugin:
            return "Run Plugin"
        }
    }

    public var summary: String {
        switch self {
        case .signMessage:
            return "Signing messages is not available in Observe mode."
        case .approveSpending:
            return "Token approvals are not available in Observe mode."
        case .draftTransaction:
            return "Transaction drafting is not available in Observe mode."
        case .runPlugin:
            return "Tool and plugin execution is not available in Observe mode."
        }
    }

    public var isBlockedInObserveMode: Bool {
        switch self {
        case .signMessage, .approveSpending, .draftTransaction, .runPlugin:
            return true
        }
    }

    public var requiresHighRiskReceipt: Bool {
        switch self {
        case .signMessage, .approveSpending, .draftTransaction, .runPlugin:
            return true
        }
    }

    public var capabilityID: CapabilityID {
        switch self {
        case .signMessage:
            return .signMessage
        case .approveSpending:
            return .approveSpending
        case .draftTransaction:
            return .draftTransaction
        case .runPlugin:
            return .runPlugin
        }
    }
}
