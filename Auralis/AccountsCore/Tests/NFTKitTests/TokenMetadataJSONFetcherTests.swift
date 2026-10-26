import AuralisTestSupport
import Foundation
import NFTPresentation
import Testing

struct TokenMetadataJSONFetcherTests {
    @Test("metadata fetcher rejects oversized declared payloads before decoding")
    func rejectsOversizedDeclaredPayloads() async {
        let session = URLSession.mocked { request in
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.com/metadata.json")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Length": "128"]
            )!
            return (response, Data(#"{"name":"Too Large"}"#.utf8))
        }
        let fetcher = LiveTokenMetadataJSONFetcher(
            session: session,
            cache: URLCache(memoryCapacity: 0, diskCapacity: 0),
            maxPayloadBytes: 16
        )

        let metadata = await fetcher.fetchMetadataJSON(from: "https://example.com/metadata.json")

        #expect(metadata == nil)
    }

    @Test("metadata fetcher rejects streamed payloads that cross the byte cap")
    func rejectsOversizedStreamedPayloads() async {
        let session = URLSession.mocked { request in
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.com/metadata.json")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(#"{"name":"This payload is too large"}"#.utf8))
        }
        let fetcher = LiveTokenMetadataJSONFetcher(
            session: session,
            cache: URLCache(memoryCapacity: 0, diskCapacity: 0),
            maxPayloadBytes: 16
        )

        let metadata = await fetcher.fetchMetadataJSON(from: "https://example.com/metadata.json")

        #expect(metadata == nil)
    }
}
