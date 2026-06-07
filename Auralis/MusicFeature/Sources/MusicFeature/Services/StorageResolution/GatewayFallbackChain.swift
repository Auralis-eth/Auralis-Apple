import Foundation

public actor GatewayFallbackChain {
    public typealias Clock = @Sendable () -> Date

    private let resolver: URLResolver
    private let configuration: AuraPlayStorageResolutionConfiguration
    private let urlSession: URLSession
    private let clock: Clock
    private let healthCacheTTL: TimeInterval
    private var failedGatewayDates: [String: Date]

    public init(
        resolver: URLResolver,
        configuration: AuraPlayStorageResolutionConfiguration = .liveDefault,
        urlSession: URLSession = .shared,
        clock: @escaping Clock = Date.init,
        healthCacheTTL: TimeInterval = 60
    ) {
        self.resolver = resolver
        self.configuration = configuration
        self.urlSession = urlSession
        self.clock = clock
        self.healthCacheTTL = healthCacheTTL
        self.failedGatewayDates = [:]
    }

    public func resolve(_ uri: String) async throws -> URL {
        guard let primaryURL = resolver.resolve(uri) else {
            throw AuraPlayError.mediaResolution("Unsupported media URI scheme: \(uri)")
        }

        if primaryURL.isFileURL {
            return primaryURL
        }

        let scheme = URIScheme.detect(from: uri)
        let gatewayURLs = gatewayURLs(for: scheme)
        guard !gatewayURLs.isEmpty else {
            if await probeIgnoringTransportErrors(primaryURL) {
                return primaryURL
            }
            throw AuraPlayError.mediaResolution("HEAD request failed for media URL: \(primaryURL.absoluteString)")
        }

        for gatewayURL in gatewayURLs {
            guard !recentlyFailed(gatewayURL) else {
                continue
            }
            guard let candidateURL = rewrite(primaryURL, toGateway: gatewayURL, scheme: scheme) else {
                continue
            }

            if await probeIgnoringTransportErrors(candidateURL) {
                return candidateURL
            }
            markFailed(gatewayURL)
        }

        throw AuraPlayError.mediaResolution("All media gateways failed for URI: \(uri)")
    }

    private func gatewayURLs(for scheme: URIScheme) -> [URL] {
        switch scheme {
        case .ipfsNative, .ipfsPath:
            configuration.ipfsGatewayChain
        case .arweave:
            configuration.arweaveGatewayChain
        case .http, .https, .dataURI, .unknown:
            []
        }
    }

    private func rewrite(_ url: URL, toGateway gatewayURL: URL, scheme: URIScheme) -> URL? {
        switch scheme {
        case .ipfsNative(let cid), .ipfsPath(let cid):
            guard let reference = ResourceReference(
                rawValue: cid,
                maximumIdentifierLength: 512,
                fixedIdentifierLength: nil
            ) else {
                return nil
            }
            return URLResolver.makeGatewayURL(
                gatewayURL: gatewayURL,
                pathPrefix: "ipfs",
                reference: reference
            )
        case .arweave(let txID):
            guard let reference = ResourceReference(
                rawValue: txID,
                maximumIdentifierLength: 43,
                fixedIdentifierLength: 43
            ),
                  reference.identifier.range(of: #"^[A-Za-z0-9_-]{43}$"#, options: .regularExpression) != nil else {
                return nil
            }
            return URLResolver.makeGatewayURL(
                gatewayURL: gatewayURL,
                pathPrefix: nil,
                reference: reference
            )
        case .http, .https, .dataURI, .unknown:
            return url
        }
    }

    private func probe(_ url: URL) async throws -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 8

        let (_, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }
        return isUsableProbeStatus(httpResponse.statusCode)
    }

    private func isUsableProbeStatus(_ statusCode: Int) -> Bool {
        if (200...299).contains(statusCode) {
            return true
        }

        // Some gateways serve media correctly with GET but reject HEAD. Let the
        // download path perform the authoritative request and status handling.
        return statusCode == 403 || statusCode == 405
    }

    private func probeIgnoringTransportErrors(_ url: URL) async -> Bool {
        do {
            return try await probe(url)
        } catch {
            return false
        }
    }

    private func recentlyFailed(_ gatewayURL: URL) -> Bool {
        let key = healthCacheKey(for: gatewayURL)
        guard let failedAt = failedGatewayDates[key] else {
            return false
        }
        if clock().timeIntervalSince(failedAt) < healthCacheTTL {
            return true
        }
        failedGatewayDates[key] = nil
        return false
    }

    private func markFailed(_ gatewayURL: URL) {
        failedGatewayDates[healthCacheKey(for: gatewayURL)] = clock()
    }

    private func healthCacheKey(for gatewayURL: URL) -> String {
        guard let components = URLComponents(url: gatewayURL, resolvingAgainstBaseURL: false) else {
            return gatewayURL.absoluteString
        }
        return [
            components.scheme?.lowercased(),
            components.host?.lowercased(),
            components.port.map(String.init)
        ]
        .compactMap { $0 }
        .joined(separator: "://")
    }
}
