import AuralisAppShell
import AuraUI

extension AppRouteError {
    var trustLabelKind: AuraUntrustedValueKind? {
        guard urlString != nil else {
            return nil
        }

        return .deepLink
    }
}
