import Foundation

enum URIScheme: Equatable, Sendable {
    case ipfsNative(cid: String)
    case ipfsPath(cid: String)
    case arweave(txID: String)
    case http(url: URL)
    case https(url: URL)
    case dataURI(mimeType: String, isBase64: Bool, body: String)
    case unknown

    static func detect(from raw: String) -> URIScheme {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .unknown
        }

        let lowercased = trimmed.lowercased()
        if lowercased.hasPrefix("ipfs://") {
            return .ipfsNative(cid: String(trimmed.dropFirst("ipfs://".count)))
        }
        if lowercased.hasPrefix("/ipfs/") {
            return .ipfsPath(cid: String(trimmed.dropFirst("/ipfs/".count)))
        }
        if lowercased.hasPrefix("ipfs/") {
            return .ipfsPath(cid: String(trimmed.dropFirst("ipfs/".count)))
        }
        if lowercased.hasPrefix("ar://") {
            return .arweave(txID: String(trimmed.dropFirst("ar://".count)))
        }
        if lowercased.hasPrefix("data:") {
            return detectDataURI(from: trimmed)
        }
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased() else {
            return .unknown
        }
        switch scheme {
        case "http":
            return .http(url: url)
        case "https":
            return .https(url: url)
        default:
            return .unknown
        }
    }

    private static func detectDataURI(from trimmed: String) -> URIScheme {
        let payload = String(trimmed.dropFirst("data:".count))
        guard let commaIndex = payload.firstIndex(of: ",") else {
            return .unknown
        }

        let metadata = String(payload[..<commaIndex])
        let body = String(payload[payload.index(after: commaIndex)...])
        let metadataParts = metadata
            .split(separator: ";", omittingEmptySubsequences: false)
            .map(String.init)

        let mimeType = metadataParts.first?.isEmpty == false
            ? metadataParts[0].lowercased()
            : "application/octet-stream"
        let isBase64 = metadataParts.dropFirst().contains { $0.lowercased() == "base64" }

        return .dataURI(mimeType: mimeType, isBase64: isBase64, body: body)
    }
}
