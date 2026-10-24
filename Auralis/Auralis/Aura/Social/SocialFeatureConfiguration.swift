import Foundation

struct SocialFeatureConfiguration: Equatable, Sendable {
    let relayEnabled: Bool

    init(infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]) {
        self.relayEnabled = Self.boolValue(for: infoDictionary["AURALIS_SOCIAL_RELAY_ENABLED"])
    }

    private static func boolValue(for rawValue: Any?) -> Bool {
        switch rawValue {
        case let value as Bool:
            return value
        case let value as String:
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "1", "true", "yes", "enabled":
                return true
            default:
                return false
            }
        case let value as NSNumber:
            return value.boolValue
        default:
            return false
        }
    }
}
