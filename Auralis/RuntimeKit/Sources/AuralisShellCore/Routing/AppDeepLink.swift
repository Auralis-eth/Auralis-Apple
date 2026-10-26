import AuralisPrimaryModels
import Foundation

public enum AppDeepLink: Hashable, Sendable {
    case account(address: String, chain: Chain?, destination: AppDeepLinkDestination?)
    case destination(AppDeepLinkDestination)
}
