import Foundation
import NFTDomain

public protocol NFTArtworkPrefetching: Sendable {
    func prefetchArtwork(for nfts: [NFTInventoryItemSnapshot]) async
}

public actor URLCacheNFTArtworkPrefetcher: NFTArtworkPrefetching {
    private let session: URLSession
    private let cache: URLCache
    private let maxImageBytes: Int
    private let batchSize: Int
    private let isLowPowerModeEnabled: @Sendable () -> Bool

    public init(
        session: URLSession = .shared,
        cache: URLCache = .shared,
        maxImageBytes: Int = 10 * 1024 * 1024,
        batchSize: Int = 5,
        isLowPowerModeEnabled: @escaping @Sendable () -> Bool = { ProcessInfo.processInfo.isLowPowerModeEnabled }
    ) {
        self.session = session
        self.cache = cache
        self.maxImageBytes = maxImageBytes
        self.batchSize = max(batchSize, 1)
        self.isLowPowerModeEnabled = isLowPowerModeEnabled
    }

    public func prefetchArtwork(for nfts: [NFTInventoryItemSnapshot]) async {
        guard !isLowPowerModeEnabled() else {
            return
        }

        let urls = artworkURLs(from: nfts)
        guard !urls.isEmpty else {
            return
        }

        for batch in urls.chunked(into: batchSize) {
            await withTaskGroup(of: Void.self) { group in
                for url in batch {
                    group.addTask { [session, cache, maxImageBytes] in
                        await Self.prefetch(url: url, session: session, cache: cache, maxImageBytes: maxImageBytes)
                    }
                }
            }
        }
    }
}

private extension URLCacheNFTArtworkPrefetcher {
    func artworkURLs(from nfts: [NFTInventoryItemSnapshot]) -> [URL] {
        var seen = Set<String>()
        return nfts.compactMap { nft in
            let candidates = [nft.image?.secureURL, nft.image?.thumbnailURL, nft.image?.originalURL]
            guard let url = candidates.lazy.compactMap({ $0 }).compactMap(URL.sanitizedRemoteMediaURL(from:)).first else {
                return nil
            }
            return seen.insert(url.absoluteString).inserted ? url : nil
        }
    }

    static func prefetch(url: URL, session: URLSession, cache: URLCache, maxImageBytes: Int) async {
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad

        if cache.cachedResponse(for: request) != nil {
            return
        }

        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return
            }
            if let byteCount = declaredContentLength(from: response, httpResponse: httpResponse),
               byteCount > maxImageBytes {
                return
            }

            var data = Data()
            if let byteCount = declaredContentLength(from: response, httpResponse: httpResponse) {
                data.reserveCapacity(min(byteCount, maxImageBytes))
            }

            var buffer: [UInt8] = []
            buffer.reserveCapacity(16_384)
            for try await byte in bytes {
                buffer.append(byte)
                if data.count + buffer.count > maxImageBytes {
                    return
                }
                if buffer.count == 16_384 {
                    data.append(contentsOf: buffer)
                    buffer.removeAll(keepingCapacity: true)
                }
            }
            if !buffer.isEmpty {
                data.append(contentsOf: buffer)
            }

            cache.storeCachedResponse(CachedURLResponse(response: httpResponse, data: data), for: request)
        } catch { }
    }

    static func declaredContentLength(from response: URLResponse, httpResponse: HTTPURLResponse) -> Int? {
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
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
