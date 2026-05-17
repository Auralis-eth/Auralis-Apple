import Foundation

public struct ExternalLinkPolicy {
    public struct ExternalLinkRule: Equatable, Sendable {
        public let host: String
        public let allowedPathPrefixes: [String]
        public let routeType: String

        public init(host: String, allowedPathPrefixes: [String], routeType: String) {
            self.host = host.lowercased()
            self.allowedPathPrefixes = allowedPathPrefixes
            self.routeType = routeType
        }

        func allows(path: String) -> Bool {
            allowedPathPrefixes.contains { prefix in
                if prefix == "/" {
                    return path == "/"
                }
                return path == prefix || path.hasPrefix(prefix)
            }
        }
    }

    private let rulesByHost: [String: ExternalLinkRule]
    public static let defaultAllowedHosts: Set<String> = [
        "opensea.io",
        "etherscan.io",
        "sepolia.etherscan.io",
        "basescan.org",
        "sepolia.basescan.org",
        "arbiscan.io",
        "sepolia.arbiscan.io",
        "nova.arbiscan.io",
        "optimistic.etherscan.io",
        "sepolia-optimism.etherscan.io",
        "polygonscan.com",
        "amoy.polygonscan.com",
        "worldscan.org",
        "sepolia.worldscan.org",
        "shapescan.xyz",
        "sepolia.shapescan.xyz",
        "explorer.inkonchain.com",
        "explorer-sepolia.inkonchain.com",
        "uniscan.xyz",
        "sepolia.uniscan.xyz",
        "soneium.blockscout.com",
        "soneium-minato.blockscout.com",
        "berascan.com",
        "explorer.zora.energy",
        "sepolia.explorer.zora.energy",
        "polynomialscan.io",
        "sepolia.polynomialscan.io",
        "ipfs.io",
        "cloudflare-ipfs.com",
        "gateway.pinata.cloud",
        "arweave.net"
    ]

    public static let defaultRules: [ExternalLinkRule] = {
        let explorerPaths = ["/", "/token/", "/address/", "/tx/"]
        let explorerHosts = defaultAllowedHosts.subtracting([
            "opensea.io",
            "ipfs.io",
            "cloudflare-ipfs.com",
            "gateway.pinata.cloud",
            "arweave.net"
        ])
        return explorerHosts.map {
            ExternalLinkRule(host: $0, allowedPathPrefixes: explorerPaths, routeType: "Explorer")
        } + [
            ExternalLinkRule(host: "opensea.io", allowedPathPrefixes: ["/", "/assets/", "/collection/"], routeType: "Marketplace"),
            ExternalLinkRule(host: "ipfs.io", allowedPathPrefixes: ["/ipfs/"], routeType: "IPFS gateway"),
            ExternalLinkRule(host: "cloudflare-ipfs.com", allowedPathPrefixes: ["/ipfs/"], routeType: "IPFS gateway"),
            ExternalLinkRule(host: "gateway.pinata.cloud", allowedPathPrefixes: ["/ipfs/"], routeType: "IPFS gateway"),
            ExternalLinkRule(host: "arweave.net", allowedPathPrefixes: ["/", "/tx/"], routeType: "Arweave")
        ]
    }()

    public init(allowedHosts: Set<String> = Self.defaultAllowedHosts) {
        self.init(
            rules: Self.defaultRules.filter { allowedHosts.contains($0.host) }
        )
    }

    public init(rules: [ExternalLinkRule]) {
        self.rulesByHost = Dictionary(
            uniqueKeysWithValues: rules.map { ($0.host, $0) }
        )
    }

    public func validate(_ candidate: ExternalLinkCandidateDestination) -> Result<ExternalLinkConfirmationDestination, ExternalLinkValidationFailure> {
        guard let components = URLComponents(url: candidate.url, resolvingAgainstBaseURL: false) else {
            return .failure(.invalidScheme(nil))
        }

        guard components.scheme?.lowercased() == "https" else {
            return .failure(.invalidScheme(components.scheme))
        }

        guard let host = components.host?.lowercased(), !host.isEmpty else {
            return .failure(.missingHost)
        }

        guard let rule = rulesByHost[host] else {
            return .failure(.unsupportedHost(host))
        }

        let pathDisplay = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
        guard rule.allows(path: pathDisplay) else {
            return .failure(.unsupportedPath(host: host, path: pathDisplay))
        }

        let fullURLDisplay = components.string ?? candidate.url.absoluteString
        return .success(
            ExternalLinkConfirmationDestination(
                label: candidate.label,
                url: candidate.url,
                hostDisplay: host,
                pathDisplay: pathDisplay,
                routeTypeDisplay: rule.routeType,
                fullURLDisplay: fullURLDisplay
            )
        )
    }
}
