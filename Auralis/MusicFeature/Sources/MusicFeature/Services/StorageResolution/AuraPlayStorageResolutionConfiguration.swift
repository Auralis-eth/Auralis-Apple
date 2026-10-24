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

    /// Loads optional deployment overrides from an Info.plist-style dictionary.
    /// Missing keys retain the audited defaults; present values must be HTTPS URLs.
    public init(infoDictionary: [String: Any]) throws {
        let ipfsGatewayURL = try Self.gatewayURL(
            from: infoDictionary,
            key: "AURALIS_AURAPLAY_IPFS_GATEWAY_URL"
        )
        let arweaveGatewayURL = try Self.gatewayURL(
            from: infoDictionary,
            key: "AURALIS_AURAPLAY_ARWEAVE_GATEWAY_URL"
        )
        let fallbackIPFSGatewayURLs = try Self.gatewayURLs(
            from: infoDictionary,
            key: "AURALIS_AURAPLAY_IPFS_FALLBACK_GATEWAY_URLS",
            defaultValue: Self.defaultFallbackIPFSGatewayURLs
        )
        let fallbackArweaveGatewayURLs = try Self.gatewayURLs(
            from: infoDictionary,
            key: "AURALIS_AURAPLAY_ARWEAVE_FALLBACK_GATEWAY_URLS",
            defaultValue: Self.defaultFallbackArweaveGatewayURLs
        )

        self.init(
            ipfsGatewayURL: ipfsGatewayURL,
            arweaveGatewayURL: arweaveGatewayURL,
            fallbackIPFSGatewayURLs: fallbackIPFSGatewayURLs,
            fallbackArweaveGatewayURLs: fallbackArweaveGatewayURLs
        )
    }

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

    private static func gatewayURL(from dictionary: [String: Any], key: String) throws -> URL? {
        guard let rawValue = dictionary[key] else { return nil }
        guard let string = rawValue as? String else {
            throw AuraPlayStorageConfigurationError.invalidValueType(key: key)
        }

        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              normalizedGatewayURL(url, fallback: nil) != nil else {
            throw AuraPlayStorageConfigurationError.invalidGatewayURL(key: key, value: string)
        }
        return url
    }

    private static func gatewayURLs(
        from dictionary: [String: Any],
        key: String,
        defaultValue: [URL]
    ) throws -> [URL] {
        guard let rawValue = dictionary[key] else { return defaultValue }
        guard let strings = rawValue as? [String] else {
            throw AuraPlayStorageConfigurationError.invalidValueType(key: key)
        }

        return try strings.map { string in
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let url = URL(string: trimmed),
                  normalizedGatewayURL(url, fallback: nil) != nil else {
                throw AuraPlayStorageConfigurationError.invalidGatewayURL(key: key, value: string)
            }
            return url
        }
    }
}

public enum AuraPlayStorageConfigurationError: Error, Equatable, LocalizedError, Sendable {
    case invalidValueType(key: String)
    case invalidGatewayURL(key: String, value: String)

    public var errorDescription: String? {
        switch self {
        case .invalidValueType(let key):
            "The \(key) configuration value has the wrong type."
        case .invalidGatewayURL(let key, _):
            "The \(key) configuration value must contain an HTTPS gateway URL."
        }
    }

    public var recoverySuggestion: String? {
        "Use an HTTPS URL with a non-empty host, or remove the override to use AuraPlay defaults."
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
