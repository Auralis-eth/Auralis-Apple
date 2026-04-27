import Foundation

struct PendingDeepLinkResolver {
    func resolve(_ deepLink: AppDeepLink, context: PendingDeepLinkContext) -> PendingDeepLinkResolution {
        switch deepLink {
        case .account(let address, let chain, let destination):
            if context.currentAddress != address {
                return PendingDeepLinkResolution(
                    chainOverride: chain,
                    action: .switchAccount(address: address)
                )
            }

            guard context.canResolveDeferredLink else {
                guard context.shouldFailDeferredLink else {
                    return PendingDeepLinkResolution(chainOverride: chain, action: .wait)
                }

                let message = destination == nil
                    ? "Open or restore an account before using this account link."
                    : "Open or restore an account before routing this deep link."
                return PendingDeepLinkResolution(
                    chainOverride: chain,
                    action: .showError(
                        AppRouteError(
                            title: "No Active Account",
                            message: message,
                            urlString: nil
                        )
                    )
                )
            }

            guard context.currentAccountAddress == address else {
                return PendingDeepLinkResolution(chainOverride: chain, action: .wait)
            }

            if let destination {
                return PendingDeepLinkResolution(
                    chainOverride: chain,
                    action: .route(destination: destination, inheritedChain: chain)
                )
            }

            return PendingDeepLinkResolution(chainOverride: chain, action: .showHome)

        case .destination(let destination):
            guard context.canResolveDeferredLink else {
                guard context.shouldFailDeferredLink else {
                    return PendingDeepLinkResolution(chainOverride: nil, action: .wait)
                }

                return PendingDeepLinkResolution(
                    chainOverride: nil,
                    action: .showError(
                        AppRouteError(
                            title: "No Active Account",
                            message: "Open or restore an account before routing this deep link.",
                            urlString: nil
                        )
                    )
                )
            }

            return PendingDeepLinkResolution(
                chainOverride: nil,
                action: .route(destination: destination, inheritedChain: nil)
            )
        }
    }
}
