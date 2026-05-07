import AuralisPrimaryModels
import Foundation

enum ShellRoutingEffect: Equatable {
    case resetAllRoutes
    case selectTab(AppTab)
    case routeDeepLink(
        destination: AppDeepLinkDestination,
        selection: ActiveShellSelection,
        inheritedChain: Chain?
    )
}
