import Foundation

public actor MetadataFetcher: TokenMetadataFetching {
    public typealias Clock = @Sendable () -> Date

    private let gatewayFallbackChain: GatewayFallbackChain
    private let urlSession: URLSession
    private let urlCache: URLCache
    private let negativeCache: UserDefaults
    private let clock: Clock
    private let maxPayloadBytes: Int
    private let retryCount: Int
    private let retryDelayNanoseconds: UInt64
    private var resolvedURLCache: [String: URL]

    public init(
        gatewayFallbackChain: GatewayFallbackChain,
        urlSession: URLSession = .shared,
        urlCache: URLCache = .shared,
        negativeCache: UserDefaults = .standard,
        clock: @escaping Clock = Date.init,
        maxPayloadBytes: Int = 5 * 1024 * 1024,
        retryCount: Int = 3,
        retryDelayNanoseconds: UInt64 = 2_000_000_000
    ) {
        self.gatewayFallbackChain = gatewayFallbackChain
        self.urlSession = urlSession
        self.urlCache = urlCache
        self.negativeCache = negativeCache
        self.clock = clock
        self.maxPayloadBytes = maxPayloadBytes
        self.retryCount = max(retryCount, 1)
        self.retryDelayNanoseconds = retryDelayNanoseconds
        self.resolvedURLCache = [:]
    }

    public func fetch(metadataURL: String) async throws -> String {
        let trimmedURL = metadataURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else {
            throw AuraPlayError.mediaResolution("Metadata URL is empty.")
        }

        if case .dataURI(let mimeType, let isBase64, let body) = URIScheme.detect(from: trimmedURL) {
            return try decodeDataURI(mimeType: mimeType, isBase64: isBase64, body: body)
        }

        if isNegativeCached(trimmedURL) {
            throw AuraPlayError.mediaResolution("Metadata fetch was skipped because this URL recently failed: \(trimmedURL)")
        }

        let resolvedURL = try await resolvedURL(for: trimmedURL)
        var request = URLRequest(url: resolvedURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.cachePolicy = .returnCacheDataElseLoad
        request.addValue("application/json, text/plain;q=0.9, */*;q=0.5", forHTTPHeaderField: "Accept")

        if let cachedResponse = urlCache.cachedResponse(for: request),
           let cachedJSON = String(data: cachedResponse.data, encoding: .utf8) {
            return cachedJSON
        }

        var lastError: Error?
        for attempt in 1...retryCount {
            do {
                let json = try await fetchOnce(request: request, metadataURL: trimmedURL)
                clearNegativeCache(trimmedURL)
                return json
            } catch {
                lastError = error
                if attempt < retryCount {
                    try await Task.sleep(nanoseconds: retryDelayNanoseconds)
                }
            }
        }

        storeNegativeCache(trimmedURL)
        throw lastError ?? AuraPlayError.mediaResolution("Metadata fetch failed for \(trimmedURL).")
    }
}

private extension MetadataFetcher {
    func resolvedURL(for metadataURL: String) async throws -> URL {
        if let cachedURL = resolvedURLCache[metadataURL] {
            return cachedURL
        }

        let resolvedURL = try await gatewayFallbackChain.resolve(metadataURL)
        resolvedURLCache[metadataURL] = resolvedURL
        return resolvedURL
    }

    func fetchOnce(request: URLRequest, metadataURL: String) async throws -> String {
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuraPlayError.mediaResolution("Metadata fetch returned a non-HTTP response for \(metadataURL).")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw AuraPlayError.mediaResolution("Metadata fetch failed with HTTP \(httpResponse.statusCode) for \(metadataURL).")
        }

        if let contentLength = httpResponse.value(forHTTPHeaderField: "Content-Length"),
           let byteCount = Int(contentLength),
           byteCount > maxPayloadBytes {
            throw AuraPlayError.mediaResolution("Metadata payload is too large for \(metadataURL).")
        }

        guard !data.isEmpty else {
            throw AuraPlayError.mediaResolution("Metadata response was empty for \(metadataURL).")
        }
        guard data.count <= maxPayloadBytes else {
            throw AuraPlayError.mediaResolution("Metadata payload is too large for \(metadataURL).")
        }
        guard let json = String(data: data, encoding: .utf8),
              canParseJSON(data) else {
            throw AuraPlayError.mediaResolution("Metadata response was not valid UTF-8 JSON for \(metadataURL).")
        }

        let cachedResponse = CachedURLResponse(response: httpResponse, data: data)
        urlCache.storeCachedResponse(cachedResponse, for: request)
        return json
    }

    func decodeDataURI(mimeType: String, isBase64: Bool, body: String) throws -> String {
        guard mimeType.lowercased().contains("json") else {
            throw AuraPlayError.mediaResolution("Metadata data URI is not JSON.")
        }

        let data: Data?
        if isBase64 {
            data = Data(base64Encoded: body)
        } else {
            data = body.removingPercentEncoding?.data(using: .utf8)
        }

        guard let data,
              !data.isEmpty,
              data.count <= maxPayloadBytes,
              let json = String(data: data, encoding: .utf8),
              canParseJSON(data) else {
            throw AuraPlayError.mediaResolution("Metadata data URI could not be decoded as JSON.")
        }

        return json
    }

    func canParseJSON(_ data: Data) -> Bool {
        (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    func isNegativeCached(_ metadataURL: String) -> Bool {
        let key = negativeCacheKey(metadataURL)
        guard let failedAt = negativeCache.object(forKey: key) as? Date else {
            return false
        }

        if clock().timeIntervalSince(failedAt) < 24 * 60 * 60 {
            return true
        }
        negativeCache.removeObject(forKey: key)
        return false
    }

    func storeNegativeCache(_ metadataURL: String) {
        negativeCache.set(clock(), forKey: negativeCacheKey(metadataURL))
    }

    func clearNegativeCache(_ metadataURL: String) {
        negativeCache.removeObject(forKey: negativeCacheKey(metadataURL))
    }

    func negativeCacheKey(_ metadataURL: String) -> String {
        "com.auraplay.metadata-fetch.failure.\(metadataURL)"
    }
}
