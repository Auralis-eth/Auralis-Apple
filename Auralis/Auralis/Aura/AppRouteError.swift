import Foundation

struct AppRouteError: Error, Identifiable, Hashable {
    let id = UUID()
    let title: String
    let message: String
    let urlString: String?

    var trustLabelKind: AuraUntrustedValueKind? {
        guard urlString != nil else {
            return nil
        }

        return .deepLink
    }
}
