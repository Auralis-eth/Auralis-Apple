import Foundation

extension URL {
    fileprivate var isIPFS: Bool {
        scheme == "ipfs"
    }

    fileprivate var isSupportedRemoteMediaURL: Bool {
        guard let scheme = scheme?.lowercased(),
              let host,
              !host.isEmpty else {
            return false
        }

        return scheme == "https"
    }

    static func sanitizedAuralisRemoteMediaURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        guard let candidateURL = Self.normalizedAuralisRemoteMediaURL(from: trimmed) else {
            return nil
        }

        if candidateURL.isIPFS,
           let gatewayURL = candidateURL.toPinataGatewayURL(),
           gatewayURL.isSupportedRemoteMediaURL {
            return gatewayURL
        }

        guard candidateURL.isSupportedRemoteMediaURL else {
            return nil
        }

        return candidateURL
    }

    private static func normalizedAuralisRemoteMediaURL(from rawValue: String) -> URL? {
        guard var components = URLComponents(string: rawValue) else {
            return nil
        }

        if components.scheme?.lowercased() == "http" {
            components.scheme = "https"
        }

        return components.url ?? URL(string: rawValue)
    }

    fileprivate func toPinataGatewayURL() -> URL? {
        guard scheme != nil else {
            return nil
        }

        guard let originalHost = host, !originalHost.isEmpty else {
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
