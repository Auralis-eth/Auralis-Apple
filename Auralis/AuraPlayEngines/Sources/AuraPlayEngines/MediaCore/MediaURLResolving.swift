import Foundation

public protocol MediaURLResolving: Sendable {
    func resolve(_ url: URL) async throws -> URL
}

public protocol MediaGatewayFallbackResolving: Sendable {
    func nextResolvedURL(after failedURL: URL) async throws -> URL?
}

public struct OrderedMediaGatewayFallbackResolver: MediaGatewayFallbackResolving {
    private let resolvedURLs: [URL]

    public init(resolvedURLs: [URL]) {
        self.resolvedURLs = resolvedURLs
    }

    public func nextResolvedURL(after failedURL: URL) async throws -> URL? {
        guard !resolvedURLs.isEmpty else {
            return nil
        }

        guard let failedIndex = resolvedURLs.firstIndex(of: failedURL) else {
            return resolvedURLs.first { $0 != failedURL }
        }

        let nextIndex = resolvedURLs.index(after: failedIndex)
        guard nextIndex < resolvedURLs.endIndex else {
            return nil
        }
        return resolvedURLs[nextIndex]
    }
}

public struct GatewayMediaURLResolver: MediaURLResolving {
    private let ipfsGateway: URL
    private let arweaveGateway: URL

    public init(
        ipfsGateway: URL = URL(string: "https://ipfs.io/ipfs/")!,
        arweaveGateway: URL = URL(string: "https://arweave.net/")!
    ) {
        self.ipfsGateway = ipfsGateway
        self.arweaveGateway = arweaveGateway
    }

    public func resolve(_ url: URL) async throws -> URL {
        switch url.scheme?.lowercased() {
        case "http", "https", "file":
            return url
        case "ipfs":
            let identifier = url.host.map { host in
                url.path.isEmpty ? host : host + url.path
            } ?? Self.strippingScheme("ipfs", from: url)
            return Self.gatewayURL(base: ipfsGateway, identifier: identifier, preservingComponentsOf: url)
        case "ar":
            let identifier = url.host ?? Self.strippingScheme("ar", from: url)
            return Self.gatewayURL(base: arweaveGateway, identifier: identifier, preservingComponentsOf: url)
        default:
            throw AuraPlayError.invalidMediaURL(url)
        }
    }

    private static func gatewayURL(base: URL, identifier: String, preservingComponentsOf url: URL) -> URL {
        let resolved = base.appending(path: identifier.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        let query = url.query(percentEncoded: true)
        let fragment = url.fragment(percentEncoded: true)
        guard
            query?.isEmpty == false || fragment?.isEmpty == false,
            var components = URLComponents(url: resolved, resolvingAgainstBaseURL: false)
        else {
            return resolved
        }
        if let query, !query.isEmpty {
            components.percentEncodedQuery = query
        }
        if let fragment, !fragment.isEmpty {
            components.percentEncodedFragment = fragment
        }
        return components.url ?? resolved
    }

    private static func strippingScheme(_ scheme: String, from url: URL) -> String {
        let raw = url.absoluteString
        for prefix in ["\(scheme)://", "\(scheme):"] where raw.lowercased().hasPrefix(prefix) {
            let stripped = raw.dropFirst(prefix.count)
            // The query and fragment are re-attached by gatewayURL; keep only the
            // path part so appending(path:) doesn't percent-encode "?…" or "#…".
            let end = stripped.firstIndex { $0 == "?" || $0 == "#" } ?? stripped.endIndex
            return String(stripped[..<end])
        }
        return raw
    }
}
