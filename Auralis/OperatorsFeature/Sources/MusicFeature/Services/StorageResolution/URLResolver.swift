import CryptoKit
import Foundation

public struct URLResolver: Sendable {
    private let configuration: AuraPlayStorageResolutionConfiguration
    private let temporaryDirectory: URL

    public init(
        configuration: AuraPlayStorageResolutionConfiguration = .liveDefault,
        temporaryDirectory: URL? = nil
    ) {
        self.configuration = configuration
        self.temporaryDirectory = temporaryDirectory ?? FileManager.default.temporaryDirectory
    }

    public func resolve(_ uri: String) -> URL? {
        switch URIScheme.detect(from: uri) {
        case .ipfsNative(let cid), .ipfsPath(let cid):
            resolveIPFS(cid: cid)
        case .arweave(let txID):
            resolveArweave(txID: txID)
        case .http(let url), .https(let url):
            resolveHTTP(url)
        case .dataURI(let mimeType, let isBase64, let body):
            resolveDataURI(mimeType: mimeType, isBase64: isBase64, body: body)
        case .unknown:
            nil
        }
    }

    private func resolveIPFS(cid: String) -> URL? {
        guard let reference = ResourceReference(rawValue: cid, maximumIdentifierLength: 512, fixedIdentifierLength: nil) else {
            return nil
        }
        return Self.makeGatewayURL(
            gatewayURL: configuration.ipfsGatewayURL,
            pathPrefix: "ipfs",
            reference: reference
        )
    }

    private func resolveArweave(txID: String) -> URL? {
        guard let reference = ResourceReference(rawValue: txID, maximumIdentifierLength: 43, fixedIdentifierLength: 43),
              reference.identifier.range(of: #"^[A-Za-z0-9_-]{43}$"#, options: .regularExpression) != nil else {
            return nil
        }
        return Self.makeGatewayURL(
            gatewayURL: configuration.arweaveGatewayURL,
            pathPrefix: nil,
            reference: reference
        )
    }

    private func resolveHTTP(_ url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host,
              !host.isEmpty,
              isAllowedPort(components.port) else {
            return nil
        }

        components.scheme = "https"
        return components.url
    }

    private func resolveDataURI(mimeType: String, isBase64: Bool, body: String) -> URL? {
        let data: Data?
        if isBase64 {
            data = Data(base64Encoded: body)
        } else {
            data = body.removingPercentEncoding?.data(using: .utf8)
        }

        guard let data,
              data.count <= 50 * 1024 * 1024 else {
            return nil
        }

        let filename = "auraplay_data_\(Self.dataURIHash(mimeType: mimeType, isBase64: isBase64, body: body)).\(Self.fileExtension(for: mimeType))"
        let fileURL = temporaryDirectory.appendingPathComponent(filename, isDirectory: false)

        do {
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                try data.write(to: fileURL, options: .atomic)
            }
            return fileURL
        } catch {
            return nil
        }
    }

    private func isAllowedPort(_ port: Int?) -> Bool {
        guard let port else {
            return true
        }
        if port == 80 || port == 443 {
            return true
        }
        return port > 1023
    }

    static func makeGatewayURL(
        gatewayURL: URL,
        pathPrefix: String?,
        reference: ResourceReference
    ) -> URL? {
        guard var components = URLComponents(url: gatewayURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        var pathComponents = components.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        if let pathPrefix {
            pathComponents.append(pathPrefix)
        }
        pathComponents.append(reference.identifier)
        pathComponents.append(contentsOf: reference.subpathComponents)
        components.path = "/" + pathComponents.joined(separator: "/")
        components.query = reference.query
        components.fragment = reference.fragment
        return components.url
    }

    private static func dataURIHash(mimeType: String, isBase64: Bool, body: String) -> String {
        let identity = "\(mimeType.lowercased())|\(isBase64 ? "base64" : "plain")|\(body)"
        let digest = SHA256.hash(data: Data(identity.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func fileExtension(for mimeType: String) -> String {
        switch mimeType.lowercased() {
        case "audio/mpeg":
            "mp3"
        case "audio/flac":
            "flac"
        case "video/mp4":
            "mp4"
        case "image/png":
            "png"
        case "image/svg+xml":
            "svg"
        default:
            "bin"
        }
    }
}

struct ResourceReference: Equatable, Sendable {
    let identifier: String
    let subpathComponents: [String]
    let query: String?
    let fragment: String?

    init?(rawValue: String, maximumIdentifierLength: Int, fixedIdentifierLength: Int?) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              !trimmed.localizedCaseInsensitiveContains("%2e%2e"),
              !trimmed.contains("..") else {
            return nil
        }

        var remaining = trimmed
        let fragment = remaining.takeSuffix(after: "#")
        let query = remaining.takeSuffix(after: "?")
        let parts = remaining
            .split(separator: "/", omittingEmptySubsequences: false)
            .map(String.init)
        guard let identifier = parts.first,
              !identifier.isEmpty,
              identifier.count <= maximumIdentifierLength else {
            return nil
        }
        if let fixedIdentifierLength, identifier.count != fixedIdentifierLength {
            return nil
        }

        let subpathComponents = Array(parts.dropFirst())
        guard !subpathComponents.contains(where: { $0 == "." || $0 == ".." || $0.isEmpty }) else {
            return nil
        }

        self.identifier = identifier
        self.subpathComponents = subpathComponents
        self.query = query
        self.fragment = fragment
    }
}

private extension String {
    mutating func takeSuffix(after separator: Character) -> String? {
        guard let index = firstIndex(of: separator) else {
            return nil
        }

        let suffix = String(self[self.index(after: index)...])
        self = String(self[..<index])
        return suffix
    }
}
