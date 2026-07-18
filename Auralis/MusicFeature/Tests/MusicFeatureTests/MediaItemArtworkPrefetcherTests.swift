import AuralisTestSupport
@testable import MusicFeature
import Foundation
import Testing

@Suite(.tags(.networking))
struct MediaItemArtworkPrefetcherTests {
    @Test("artwork prefetch downloads and stores uncached artwork responses")
    func prefetchStoresDownloadedArtwork() async throws {
        let recorder = ArtworkRequestRecorder()
        let cache = Self.makeCache()
        let prefetcher = Self.makePrefetcher(recorder: recorder, cache: cache)

        await prefetcher.prefetch(artworkURLs: ["https://example.com/art1.png", "https://example.com/art2.png"])

        let art1Request = URLRequest(url: try #require(URL(string: "https://example.com/art1.png")))
        let art2Request = URLRequest(url: try #require(URL(string: "https://example.com/art2.png")))
        #expect(recorder.methods.sorted() == ["GET", "GET", "HEAD", "HEAD"])
        #expect(cache.cachedResponse(for: art1Request)?.data == Data("image-1".utf8))
        #expect(cache.cachedResponse(for: art2Request)?.data == Data("image-2".utf8))
    }

    @Test("artwork prefetch skips GET downloads when artwork is already cached")
    func prefetchSkipsCachedArtworkDownload() async throws {
        let recorder = ArtworkRequestRecorder()
        let cache = Self.makeCache()
        let url = try #require(URL(string: "https://example.com/cached.png"))
        let request = URLRequest(url: url)
        let response = try #require(HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "image/png"]
        ))
        cache.storeCachedResponse(
            CachedURLResponse(response: response, data: Data("cached-image".utf8)),
            for: request
        )
        let prefetcher = Self.makePrefetcher(recorder: recorder, cache: cache)

        await prefetcher.prefetch(artworkURLs: [url.absoluteString])

        #expect(recorder.methods == ["HEAD"])
        #expect(cache.cachedResponse(for: request)?.data == Data("cached-image".utf8))
    }

    @Test("artwork prefetch skips oversized artwork payloads")
    func prefetchSkipsOversizedArtwork() async throws {
        let recorder = ArtworkRequestRecorder(responseMode: .oversized)
        let cache = Self.makeCache()
        let prefetcher = Self.makePrefetcher(recorder: recorder, cache: cache)
        let url = try #require(URL(string: "https://example.com/huge.png"))

        await prefetcher.prefetch(artworkURLs: [url.absoluteString])

        #expect(recorder.methods == ["HEAD", "GET"])
        #expect(cache.cachedResponse(for: URLRequest(url: url)) == nil)
    }

    @Test("artwork prefetch returns immediately in Low Power Mode")
    func prefetchSkipsAllWorkInLowPowerMode() async {
        let recorder = ArtworkRequestRecorder()
        let cache = Self.makeCache()
        let prefetcher = Self.makePrefetcher(
            recorder: recorder,
            cache: cache,
            isLowPowerModeEnabled: { true }
        )

        await prefetcher.prefetch(artworkURLs: ["https://example.com/art1.png"])

        #expect(recorder.methods.isEmpty)
    }

    private static func makePrefetcher(
        recorder: ArtworkRequestRecorder,
        cache: URLCache,
        isLowPowerModeEnabled: @escaping @Sendable () -> Bool = { false }
    ) -> MediaItemArtworkPrefetcher {
        let session = URLSession.mocked { request in
            recorder.record(request)
            return recorder.response(for: request)
        }
        let resolver = URLResolver(configuration: fixtureConfiguration)
        let gatewayChain = GatewayFallbackChain(
            resolver: resolver,
            configuration: fixtureConfiguration,
            urlSession: session
        )

        return MediaItemArtworkPrefetcher(
            gatewayFallbackChain: gatewayChain,
            urlSession: session,
            urlCache: cache,
            isLowPowerModeEnabled: isLowPowerModeEnabled
        )
    }

    private static func makeCache() -> URLCache {
        URLCache(memoryCapacity: 512_000, diskCapacity: 0, directory: nil)
    }

    private static let fixtureConfiguration = AuraPlayStorageResolutionConfiguration(
        ipfsGatewayURL: URL(string: "https://media.example"),
        arweaveGatewayURL: URL(string: "https://ar.example"),
        fallbackIPFSGatewayURLs: [],
        fallbackArweaveGatewayURLs: []
    )
}

private final class ArtworkRequestRecorder: @unchecked Sendable {
    enum ResponseMode: Sendable {
        case success
        case oversized
    }

    private let lock = NSLock()
    private let responseMode: ResponseMode
    private var requests: [URLRequest] = []

    init(responseMode: ResponseMode = .success) {
        self.responseMode = responseMode
    }

    var methods: [String] {
        lock.withLock {
            requests.compactMap(\.httpMethod)
        }
    }

    func record(_ request: URLRequest) {
        lock.withLock {
            requests.append(request)
        }
    }

    func response(for request: URLRequest) -> (URLResponse, Data) {
        if request.httpMethod == "HEAD" {
            return httpResponse(statusCode: 200, request: request)
        }

        switch responseMode {
        case .success:
            let imageName = request.url?.lastPathComponent == "art2.png" ? "image-2" : "image-1"
            return httpResponse(
                statusCode: 200,
                request: request,
                body: Data(imageName.utf8),
                headerFields: ["Content-Type": "image/png"]
            )
        case .oversized:
            return httpResponse(
                statusCode: 200,
                request: request,
                body: Data("too-large".utf8),
                headerFields: ["Content-Length": "\(10 * 1024 * 1024 + 1)"]
            )
        }
    }

    private func httpResponse(
        statusCode: Int,
        request: URLRequest,
        body: Data = Data(),
        headerFields: [String: String]? = nil
    ) -> (URLResponse, Data) {
        let url = request.url ?? URL(string: "https://example.com")!
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: headerFields
        )!
        return (response, body)
    }
}
