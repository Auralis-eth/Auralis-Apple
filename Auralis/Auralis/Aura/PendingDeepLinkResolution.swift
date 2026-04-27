import Foundation

struct PendingDeepLinkResolution: Equatable {
    let chainOverride: Chain?
    let action: Action

    enum Action: Equatable {
        case wait
        case switchAccount(address: String)
        case showHome
        case route(destination: AppDeepLinkDestination, inheritedChain: Chain?)
        case showError(AppRouteError)
    }
}
