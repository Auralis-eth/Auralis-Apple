import AuralisPrimaryModels
import Foundation

public protocol TokenMetadataJSONFetching: Sendable {
    func fetchMetadataJSON(from metadataURL: String) async -> [String: JSONValue]?
}

public actor LiveTokenMetadataJSONFetcher: TokenMetadataJSONFetching {
    private let session: URLSession
    private let cache: URLCache
    private let maxPayloadBytes: Int

    public init(
        session: URLSession = .shared,
        cache: URLCache = .shared,
        maxPayloadBytes: Int = 5 * 1024 * 1024
    ) {
        self.session = session
        self.cache = cache
        self.maxPayloadBytes = maxPayloadBytes
    }

    public func fetchMetadataJSON(from metadataURL: String) async -> [String: JSONValue]? {
        guard let url = resolvedMetadataURL(from: metadataURL) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.cachePolicy = .returnCacheDataElseLoad
        request.addValue("application/json, text/plain;q=0.9, */*;q=0.5", forHTTPHeaderField: "Accept")

        if let cachedResponse = cache.cachedResponse(for: request),
           let decoded = decodeMetadata(cachedResponse.data) {
            return decoded
        }

        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return nil
            }
            if let byteCount = declaredContentLength(from: response, httpResponse: httpResponse),
               byteCount > maxPayloadBytes {
                return nil
            }

            var data = Data()
            if let byteCount = declaredContentLength(from: response, httpResponse: httpResponse) {
                data.reserveCapacity(min(byteCount, maxPayloadBytes))
            }

            var buffer: [UInt8] = []
            buffer.reserveCapacity(16_384)
            for try await byte in bytes {
                buffer.append(byte)
                if data.count + buffer.count > maxPayloadBytes {
                    return nil
                }
                if buffer.count == 16_384 {
                    data.append(contentsOf: buffer)
                    buffer.removeAll(keepingCapacity: true)
                }
            }
            if !buffer.isEmpty {
                data.append(contentsOf: buffer)
            }

            guard let decoded = decodeMetadata(data) else {
                return nil
            }

            cache.storeCachedResponse(CachedURLResponse(response: httpResponse, data: data), for: request)
            return decoded
        } catch {
            return nil
        }
    }
}

private extension LiveTokenMetadataJSONFetcher {
    func decodeMetadata(_ data: Data) -> [String: JSONValue]? {
        guard !data.isEmpty, data.count <= maxPayloadBytes else {
            return nil
        }
        return try? JSONDecoder().decode([String: JSONValue].self, from: data)
    }

    func declaredContentLength(from response: URLResponse, httpResponse: HTTPURLResponse) -> Int? {
        if let contentLength = httpResponse.value(forHTTPHeaderField: "Content-Length"),
           let byteCount = Int(contentLength) {
            return byteCount
        }
        guard response.expectedContentLength >= 0,
              response.expectedContentLength <= Int64(Int.max) else {
            return nil
        }
        return Int(response.expectedContentLength)
    }

    func resolvedMetadataURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if let mediaURL = URL.sanitizedRemoteMediaURL(from: trimmed) {
            return mediaURL
        }

        guard var components = URLComponents(string: trimmed) else {
            return nil
        }
        if components.scheme?.lowercased() == "http" {
            components.scheme = "https"
        }
        return components.url.flatMap { $0.scheme == "https" ? $0 : nil }
    }
}
