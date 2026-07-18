import AuralisTestSupport
@testable import MusicFeature
import Foundation
import Testing

struct MetadataFetcherTests {
    @Test("metadata fetcher decodes JSON data URIs without network calls")
    func fetcherDecodesDataURI() async throws {
        let recorder = RequestRecorder()
        let fetcher = Self.makeFetcher(recorder: recorder)

        let json = try await fetcher.fetch(metadataURL: "data:application/json;base64,eyJuYW1lIjoiVGVzdCJ9")

        #expect(json == "{\"name\":\"Test\"}")
        #expect(recorder.urls.isEmpty)
    }

    @Test("metadata fetcher resolves IPFS through gateway chain and returns JSON")
    func fetcherResolvesGatewayURL() async throws {
        let recorder = RequestRecorder()
        let fetcher = Self.makeFetcher(recorder: recorder)

        let json = try await fetcher.fetch(metadataURL: "ipfs://QmMetadata")

        #expect(json == "{\"name\":\"Fetched\"}")
        #expect(recorder.methods == ["HEAD", "GET"])
        #expect(recorder.urls.map(\.absoluteString) == [
            "https://media.example/ipfs/QmMetadata",
            "https://media.example/ipfs/QmMetadata"
        ])
    }

    @Test("metadata fetcher returns cached JSON without a second GET")
    func fetcherUsesURLCache() async throws {
        let recorder = RequestRecorder()
        let cache = URLCache(memoryCapacity: 512_000, diskCapacity: 0, directory: nil)
        let fetcher = Self.makeFetcher(recorder: recorder, urlCache: cache)

        let first = try await fetcher.fetch(metadataURL: "ipfs://QmCached")
        let second = try await fetcher.fetch(metadataURL: "ipfs://QmCached")

        #expect(first == "{\"name\":\"Fetched\"}")
        #expect(second == first)
        #expect(recorder.methods == ["HEAD", "GET"])
    }

    @Test("metadata fetcher rejects oversized metadata payloads")
    func fetcherRejectsOversizedPayload() async throws {
        let recorder = RequestRecorder(responseMode: .oversized)
        let fetcher = Self.makeFetcher(recorder: recorder, retryCount: 1)

        await #expect(throws: AuraPlayError.self) {
            _ = try await fetcher.fetch(metadataURL: "ipfs://QmLarge")
        }
    }

    @Test("metadata fetcher negative-caches repeated failures")
    func fetcherNegativeCachesFailures() async throws {
        let recorder = RequestRecorder(responseMode: .notFound)
        let suiteName = "metadata-fetcher-\(UUID().uuidString)"
        _ = try #require(UserDefaults(suiteName: suiteName))
        let fetcher = Self.makeFetcher(
            recorder: recorder,
            negativeCacheSuiteName: suiteName,
            retryCount: 1
        )

        await #expect(throws: AuraPlayError.self) {
            _ = try await fetcher.fetch(metadataURL: "ipfs://QmMissing")
        }
        await #expect(throws: AuraPlayError.self) {
            _ = try await fetcher.fetch(metadataURL: "ipfs://QmMissing")
        }

        #expect(recorder.methods == ["HEAD", "GET"])
    }

    private static func makeFetcher(
        recorder: RequestRecorder,
        urlCache: URLCache = URLCache(memoryCapacity: 512_000, diskCapacity: 0, directory: nil),
        negativeCacheSuiteName: String = "metadata-fetcher-\(UUID().uuidString)",
        retryCount: Int = 3
    ) -> MetadataFetcher {
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

        return MetadataFetcher(
            gatewayFallbackChain: gatewayChain,
            urlSession: session,
            urlCache: urlCache,
            negativeCache: UserDefaults(suiteName: negativeCacheSuiteName)!,
            retryCount: retryCount,
            retryDelayNanoseconds: 1
        )
    }

    private static let fixtureConfiguration = AuraPlayStorageResolutionConfiguration(
        ipfsGatewayURL: URL(string: "https://media.example"),
        arweaveGatewayURL: URL(string: "https://ar.example"),
        fallbackIPFSGatewayURLs: [],
        fallbackArweaveGatewayURLs: []
    )
}

private final class RequestRecorder: @unchecked Sendable {
    enum ResponseMode: Sendable {
        case success
        case oversized
        case notFound
    }

    private let lock = NSLock()
    private let responseMode: ResponseMode
    private var requests: [URLRequest] = []

    init(responseMode: ResponseMode = .success) {
        self.responseMode = responseMode
    }

    var urls: [URL] {
        lock.withLock {
            requests.compactMap(\.url)
        }
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
            return httpResponse(
                statusCode: 200,
                request: request,
                body: Data("{\"name\":\"Fetched\"}".utf8),
                headerFields: ["Content-Type": "text/html"]
            )
        case .oversized:
            return httpResponse(
                statusCode: 200,
                request: request,
                body: Data("{\"name\":\"Too Large\"}".utf8),
                headerFields: ["Content-Length": "\(5 * 1024 * 1024 + 1)"]
            )
        case .notFound:
            return httpResponse(statusCode: 404, request: request)
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
