import AuralisPrimaryModels

public enum ExternalLinkOpenProvenance: String, Equatable, Sendable {
    case userConfirmedTap = "user_confirmed_tap"
    case operatorConfirmed = "operator_confirmed"
    case pluginConfirmed = "plugin_confirmed"

    public var receiptActor: ReceiptActor {
        switch self {
        case .userConfirmedTap:
            return .user
        case .operatorConfirmed, .pluginConfirmed:
            return .system
        }
    }
}
