import Foundation

public struct ExternalLinkPolicy {
    private let allowedHosts: Set<String>
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
        "ipfs.io",
        "cloudflare-ipfs.com",
        "gateway.pinata.cloud",
        "arweave.net"
    ]

    public init(allowedHosts: Set<String> = Self.defaultAllowedHosts) {
        self.allowedHosts = allowedHosts
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

        guard allowedHosts.contains(host) else {
            return .failure(.unsupportedHost(host))
        }

        let pathDisplay = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
        return .success(
            ExternalLinkConfirmationDestination(
                label: candidate.label,
                url: candidate.url,
                hostDisplay: host,
                pathDisplay: pathDisplay,
                fullURLDisplay: components.string ?? candidate.url.absoluteString
            )
        )
    }
}
