import Foundation

enum AppDeepLink: Hashable {
    case account(address: String, chain: Chain?, destination: AppDeepLinkDestination?)
    case destination(AppDeepLinkDestination)
}
