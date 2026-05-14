import AuraUI
import AuralisShellCore

extension AppRouteError {
    var trustLabelKind: AuraUntrustedValueKind? {
        guard urlString != nil else {
            return nil
        }

        return .deepLink
    }
}
