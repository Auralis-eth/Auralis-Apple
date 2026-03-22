import Foundation

enum AppDeepLinkDestination: Hashable {
    case nft(id: String)
    case token(contractAddress: String, chain: Chain?, symbol: String)
    case receipt(id: String)
}

enum AppDeepLink: Hashable {
    case account(address: String, chain: Chain?, destination: AppDeepLinkDestination?)
    case destination(AppDeepLinkDestination)
}

struct AppRouteError: Error, Identifiable, Hashable {
    let id = UUID()
    let title: String
    let message: String
    let urlString: String?
}

struct PendingDeepLinkContext: Equatable {
    let currentAddress: String
    let currentAccountAddress: String?
    let canResolveDeferredLink: Bool
    let shouldFailDeferredLink: Bool
}

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

struct AppDeepLinkParser {
    func parse(url: URL) -> Result<AppDeepLink, AppRouteError> {
        let segments = routeSegments(for: url)

        guard let route = segments.first?.lowercased() else {
            return .failure(
                AppRouteError(
                    title: "Invalid Link",
                    message: "This link does not include a valid route.",
                    urlString: url.absoluteString
                )
            )
        }

        switch route {
        case "account":
            return parseAccountLink(url: url, segments: segments)
        case "nft":
            return wrapTopLevelDestination(
                parseDestination(url: url, segments: segments, requireTokenChain: true),
                url: url,
                routeName: "NFT"
            )
        case "token":
            return wrapTopLevelDestination(
                parseDestination(url: url, segments: segments, requireTokenChain: true),
                url: url,
                routeName: "Token"
            )
        case "receipt", "receipts":
            return wrapTopLevelDestination(
                parseDestination(url: url, segments: segments, requireTokenChain: true),
                url: url,
                routeName: "Receipt"
            )
        default:
            return .failure(
                AppRouteError(
                    title: "Unknown Route",
                    message: "The link route '\(route)' is not supported.",
                    urlString: url.absoluteString
                )
            )
        }
    }

    private func wrapTopLevelDestination(
        _ result: Result<AppDeepLinkDestination?, AppRouteError>,
        url: URL,
        routeName: String
    ) -> Result<AppDeepLink, AppRouteError> {
        switch result {
        case .success(let destination):
            guard let destination else {
                return .failure(
                    AppRouteError(
                        title: "Invalid \(routeName) Link",
                        message: "The \(routeName.lowercased()) deep link must include a valid payload.",
                        urlString: url.absoluteString
                    )
                )
            }
            return .success(.destination(destination))
        case .failure(let error):
            return .failure(error)
        }
    }

    private func routeSegments(for url: URL) -> [String] {
        let pathSegments = url.pathComponents.filter { $0 != "/" }
        let hostLooksLikeDomain = (url.host ?? "").contains(".")

        if let host = url.host, !host.isEmpty, !hostLooksLikeDomain {
            return [host] + pathSegments
        }

        return pathSegments
    }

    private func parseAccountLink(url: URL, segments: [String]) -> Result<AppDeepLink, AppRouteError> {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let pathAddressCandidate = segments.dropFirst().first
        let accountCandidate = queryValue(named: "address", in: components) ?? pathAddressCandidate

        guard let accountCandidate, let address = accountCandidate.extractedEthereumAddress else {
            return .failure(
                AppRouteError(
                    title: "Invalid Account Link",
                    message: "The account deep link must include a valid wallet address.",
                    urlString: url.absoluteString
                )
            )
        }

        let remainingSegments: [String]
        if let pathAddressCandidate, pathAddressCandidate.extractedEthereumAddress != nil {
            remainingSegments = Array(segments.dropFirst(2))
        } else {
            remainingSegments = Array(segments.dropFirst())
        }

        let destinationResult = parseDestination(
            url: url,
            segments: remainingSegments,
            requireTokenChain: false
        )

        switch destinationResult {
        case .failure(let error):
            return .failure(error)
        case .success(let destination):
            let chainCandidate = queryValue(named: "chain", in: components)

            if let chainCandidate {
                guard let chain = Chain(rawValue: chainCandidate) else {
                    return .failure(
                        AppRouteError(
                            title: "Invalid Chain",
                            message: "The deep link included an unknown chain value.",
                            urlString: url.absoluteString
                        )
                    )
                }

                return .success(.account(address: address, chain: chain, destination: destination))
            }

            return .success(.account(address: address, chain: nil, destination: destination))
        }
    }

    private func parseDestination(
        url: URL,
        segments: [String],
        requireTokenChain: Bool
    ) -> Result<AppDeepLinkDestination?, AppRouteError> {
        guard let route = segments.first?.lowercased() else {
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)

            if let nftID = queryValue(named: "nftId", in: components), !nftID.isEmpty {
                return .success(.nft(id: nftID))
            }

            if let receiptID = queryValue(named: "receiptId", in: components), !receiptID.isEmpty {
                return .success(.receipt(id: receiptID))
            }

            return .success(nil)
        }

        switch route {
        case "nft":
            switch parseNFTDestination(url: url, segments: segments) {
            case .success(let destination):
                return .success(destination)
            case .failure(let error):
                return .failure(error)
            }
        case "token":
            switch parseTokenDestination(url: url, segments: segments, requireChain: requireTokenChain) {
            case .success(let destination):
                return .success(destination)
            case .failure(let error):
                return .failure(error)
            }
        case "receipt", "receipts":
            switch parseReceiptDestination(url: url, segments: segments) {
            case .success(let destination):
                return .success(destination)
            case .failure(let error):
                return .failure(error)
            }
        default:
            return .failure(
                AppRouteError(
                    title: "Invalid Nested Route",
                    message: "The nested route '\(route)' is not supported.",
                    urlString: url.absoluteString
                )
            )
        }
    }

    private func parseNFTDestination(
        url: URL,
        segments: [String]
    ) -> Result<AppDeepLinkDestination, AppRouteError> {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let identifier = queryValue(named: "id", in: components) ?? segments.dropFirst().first

        guard let identifier, !identifier.isEmpty else {
            return .failure(
                AppRouteError(
                    title: "Invalid NFT Link",
                    message: "The NFT deep link must include an NFT identifier.",
                    urlString: url.absoluteString
                )
            )
        }

        return .success(.nft(id: identifier))
    }

    private func parseTokenDestination(
        url: URL,
        segments: [String],
        requireChain: Bool
    ) -> Result<AppDeepLinkDestination, AppRouteError> {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let tokenSegments = Array(segments.dropFirst())
        let contractCandidate = queryValue(named: "address", in: components)
            ?? queryValue(named: "contractAddress", in: components)
            ?? tokenSegments.first
        let queriedChain = queryValue(named: "chain", in: components)
        let queriedSymbol = queryValue(named: "symbol", in: components)

        let trailingSegments = Array(tokenSegments.dropFirst())
        let inferredPathChain: String?
        let inferredPathSymbol: String?

        if queriedChain != nil {
            inferredPathChain = nil
            inferredPathSymbol = trailingSegments.first
        } else if let firstTrailing = trailingSegments.first, Chain(rawValue: firstTrailing) != nil {
            inferredPathChain = firstTrailing
            inferredPathSymbol = trailingSegments.dropFirst().first
        } else {
            inferredPathChain = nil
            inferredPathSymbol = trailingSegments.first
        }

        let chainCandidate = queriedChain ?? inferredPathChain
        let symbol = queriedSymbol ?? inferredPathSymbol

        guard let contractCandidate, let contractAddress = contractCandidate.extractedEthereumAddress else {
            return .failure(
                AppRouteError(
                    title: "Invalid Token Link",
                    message: "The token deep link must include a valid ERC-20 contract address.",
                    urlString: url.absoluteString
                )
            )
        }

        let chain = chainCandidate.flatMap { Chain(rawValue: $0) }
        if requireChain && chain == nil {
            return .failure(
                AppRouteError(
                    title: "Invalid Token Link",
                    message: "The token deep link must include a supported chain.",
                    urlString: url.absoluteString
                )
            )
        }

        if chainCandidate != nil && chain == nil {
            return .failure(
                AppRouteError(
                    title: "Invalid Token Link",
                    message: "The token deep link included an unknown chain.",
                    urlString: url.absoluteString
                )
            )
        }

        guard let symbol, !symbol.isEmpty else {
            return .failure(
                AppRouteError(
                    title: "Invalid Token Link",
                    message: "The token deep link must include a symbol.",
                    urlString: url.absoluteString
                )
            )
        }

        return .success(
            .token(
                contractAddress: contractAddress,
                chain: chain,
                symbol: symbol.uppercased()
            )
        )
    }

    private func parseReceiptDestination(
        url: URL,
        segments: [String]
    ) -> Result<AppDeepLinkDestination, AppRouteError> {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let identifier = queryValue(named: "id", in: components) ?? segments.dropFirst().first

        guard let identifier, !identifier.isEmpty else {
            return .failure(
                AppRouteError(
                    title: "Invalid Receipt Link",
                    message: "The receipt deep link must include a receipt identifier.",
                    urlString: url.absoluteString
                )
            )
        }

        return .success(.receipt(id: identifier))
    }

    private func queryValue(named name: String, in components: URLComponents?) -> String? {
        components?.queryItems?.first(where: { $0.name == name })?.value
    }
}
