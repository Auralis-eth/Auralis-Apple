import Foundation

public protocol MediaURLResolving: Sendable {
    func resolve(_ url: URL) async throws -> URL
}

public protocol MediaGatewayFallbackResolving: Sendable {
    func nextResolvedURL(after failedURL: URL) async throws -> URL?
}

public actor OrderedMediaGatewayFallbackResolver: MediaGatewayFallbackResolving {
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
            } ?? url.absoluteString.replacingOccurrences(of: "ipfs://", with: "")
            return ipfsGateway.appending(path: identifier.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        case "ar":
            let identifier = url.host ?? url.absoluteString.replacingOccurrences(of: "ar://", with: "")
            return arweaveGateway.appending(path: identifier.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        default:
            throw AuraPlayError.invalidMediaURL(url)
        }
    }
}
