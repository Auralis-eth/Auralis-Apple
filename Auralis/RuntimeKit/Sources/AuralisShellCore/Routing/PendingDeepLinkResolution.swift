import AuralisPrimaryModels
import Foundation

public struct PendingDeepLinkResolution: Equatable {
    public let chainOverride: Chain?
    public let action: Action

    public init(chainOverride: Chain?, action: Action) {
        self.chainOverride = chainOverride
        self.action = action
    }

    public enum Action: Equatable {
        case wait
        case switchAccount(address: String)
        case showHome
        case route(destination: AppDeepLinkDestination, inheritedChain: Chain?)
        case showError(AppRouteError)
    }
}
