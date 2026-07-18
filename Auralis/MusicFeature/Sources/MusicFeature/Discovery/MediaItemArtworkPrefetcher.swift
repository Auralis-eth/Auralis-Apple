import Foundation

public actor MediaItemArtworkPrefetcher: ArtworkPrefetching {
    private let gatewayFallbackChain: GatewayFallbackChain
    private let urlSession: URLSession
    private let urlCache: URLCache
    private let maxImageBytes: Int
    private let batchSize: Int
    private let isLowPowerModeEnabled: @Sendable () -> Bool

    public init(
        gatewayFallbackChain: GatewayFallbackChain,
        urlSession: URLSession = .shared,
        urlCache: URLCache = .shared,
        maxImageBytes: Int = 10 * 1024 * 1024,
        batchSize: Int = 5,
        isLowPowerModeEnabled: @escaping @Sendable () -> Bool = { ProcessInfo.processInfo.isLowPowerModeEnabled }
    ) {
        self.gatewayFallbackChain = gatewayFallbackChain
        self.urlSession = urlSession
        self.urlCache = urlCache
        self.maxImageBytes = maxImageBytes
        self.batchSize = max(batchSize, 1)
        self.isLowPowerModeEnabled = isLowPowerModeEnabled
    }

    public func prefetch(artworkURLs: [String]) async {
        guard !isLowPowerModeEnabled() else {
            return
        }

        let uniqueURLs = Array(Set(artworkURLs)).sorted()
        for batch in uniqueURLs.chunked(into: batchSize) {
            await withTaskGroup(of: Void.self) { group in
                for artworkURL in batch {
                    group.addTask { [gatewayFallbackChain, urlSession, urlCache, maxImageBytes] in
                        await Self.prefetch(
                            artworkURL: artworkURL,
                            gatewayFallbackChain: gatewayFallbackChain,
                            urlSession: urlSession,
                            urlCache: urlCache,
                            maxImageBytes: maxImageBytes
                        )
                    }
                }
            }
        }
    }
}

private extension MediaItemArtworkPrefetcher {
    static func prefetch(
        artworkURL: String,
        gatewayFallbackChain: GatewayFallbackChain,
        urlSession: URLSession,
        urlCache: URLCache,
        maxImageBytes: Int
    ) async {
        do {
            let resolvedURL = try await gatewayFallbackChain.resolve(artworkURL)
            var request = URLRequest(url: resolvedURL)
            request.cachePolicy = .returnCacheDataElseLoad

            if urlCache.cachedResponse(for: request) != nil {
                return
            }

            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  data.count <= maxImageBytes else {
                return
            }
            if let contentLength = httpResponse.value(forHTTPHeaderField: "Content-Length"),
               let byteCount = Int(contentLength),
               byteCount > maxImageBytes {
                return
            }

            urlCache.storeCachedResponse(CachedURLResponse(response: httpResponse, data: data), for: request)
        } catch { }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
