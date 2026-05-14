import AuralisPrimaryModels
import Foundation

public enum ShellRoutingEffect: Equatable {
    case resetAllRoutes
    case selectTab(AppTab)
    case routeDeepLink(
        destination: AppDeepLinkDestination,
        selection: ActiveShellSelection,
        inheritedChain: Chain?
    )
}
