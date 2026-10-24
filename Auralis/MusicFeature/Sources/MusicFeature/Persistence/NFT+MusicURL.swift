import AuralisPrimaryPersistence
import Foundation

public extension NFT {
    var musicURL: URL? {
        guard let audioUrl else {
            return nil
        }
        return URL.sanitizedAuraPlayRemoteMediaURL(from: audioUrl)
    }
}

private extension URL {
    var isIPFS: Bool {
        scheme == "ipfs"
    }

    var isSupportedRemoteMediaURL: Bool {
        guard let scheme = scheme?.lowercased(), let host, !host.isEmpty else {
            return false
        }
        return scheme == "https"
    }

    static func sanitizedAuraPlayRemoteMediaURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let candidateURL = normalizedAuraPlayRemoteMediaURL(from: trimmed) else {
            return nil
        }

        if candidateURL.isIPFS,
           let gatewayURL = candidateURL.pinataGatewayURL,
           gatewayURL.isSupportedRemoteMediaURL {
            return gatewayURL
        }

        return candidateURL.isSupportedRemoteMediaURL ? candidateURL : nil
    }

    static func normalizedAuraPlayRemoteMediaURL(from rawValue: String) -> URL? {
        guard var components = URLComponents(string: rawValue) else {
            return nil
        }
        if components.scheme?.lowercased() == "http" {
            components.scheme = "https"
        }
        return components.url ?? URL(string: rawValue)
    }

    var pinataGatewayURL: URL? {
        guard scheme != nil, let originalHost = host, !originalHost.isEmpty else {
            return nil
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "gateway.pinata.cloud"
        components.path = "/ipfs/\(originalHost)"
        if path != "/" {
            components.path += path
        }
        components.query = query
        components.fragment = fragment
        return components.url
    }
}
