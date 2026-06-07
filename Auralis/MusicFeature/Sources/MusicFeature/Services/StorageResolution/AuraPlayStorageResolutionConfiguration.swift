import Foundation

public struct AuraPlayStorageResolutionConfiguration: Equatable, Sendable {
    public let ipfsGatewayURL: URL
    public let arweaveGatewayURL: URL
    public let fallbackIPFSGatewayURLs: [URL]
    public let fallbackArweaveGatewayURLs: [URL]

    public init(
        ipfsGatewayURL: URL? = nil,
        arweaveGatewayURL: URL? = nil,
        fallbackIPFSGatewayURLs: [URL] = Self.defaultFallbackIPFSGatewayURLs,
        fallbackArweaveGatewayURLs: [URL] = Self.defaultFallbackArweaveGatewayURLs
    ) {
        self.ipfsGatewayURL = Self.normalizedGatewayURL(
            ipfsGatewayURL,
            fallback: Self.defaultIPFSGatewayURL
        ) ?? Self.defaultIPFSGatewayURL
        self.arweaveGatewayURL = Self.normalizedGatewayURL(
            arweaveGatewayURL,
            fallback: Self.defaultArweaveGatewayURL
        ) ?? Self.defaultArweaveGatewayURL
        self.fallbackIPFSGatewayURLs = fallbackIPFSGatewayURLs
            .compactMap { Self.normalizedGatewayURL($0, fallback: nil) }
        self.fallbackArweaveGatewayURLs = fallbackArweaveGatewayURLs
            .compactMap { Self.normalizedGatewayURL($0, fallback: nil) }
    }

    public static let liveDefault = AuraPlayStorageResolutionConfiguration()

    public static let defaultIPFSGatewayURL = URL.auraplayHTTPSURL(host: "cloudflare-ipfs.com")
    public static let defaultArweaveGatewayURL = URL.auraplayHTTPSURL(host: "arweave.net")
    public static let defaultFallbackIPFSGatewayURLs = [
        URL.auraplayHTTPSURL(host: "ipfs.io"),
        URL.auraplayHTTPSURL(host: "dweb.link")
    ]
    public static let defaultFallbackArweaveGatewayURLs = [
        URL.auraplayHTTPSURL(host: "arweave.dev")
    ]

    public var ipfsGatewayChain: [URL] {
        [ipfsGatewayURL] + fallbackIPFSGatewayURLs.filter { $0 != ipfsGatewayURL }
    }

    public var arweaveGatewayChain: [URL] {
        [arweaveGatewayURL] + fallbackArweaveGatewayURLs.filter { $0 != arweaveGatewayURL }
    }

    private static func normalizedGatewayURL(_ url: URL?, fallback: URL?) -> URL? {
        guard let url,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              scheme == "https",
              let host = components.host,
              !host.isEmpty else {
            return fallback
        }

        components.scheme = "https"
        components.path = components.path.trimmingTrailingSlashes()
        components.query = nil
        components.fragment = nil
        return components.url ?? fallback
    }
}

private extension URL {
    static func auraplayHTTPSURL(host: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host

        guard let url = components.url else {
            preconditionFailure("Invalid bundled AuraPlay gateway host: \(host)")
        }
        return url
    }
}

private extension String {
    func trimmingTrailingSlashes() -> String {
        var value = self
        while value.count > 1, value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }
}
