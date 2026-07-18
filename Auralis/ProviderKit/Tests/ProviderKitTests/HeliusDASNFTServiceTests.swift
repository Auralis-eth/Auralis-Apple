import AuralisPrimaryModels
import AuralisTestSupport
import Foundation
import Testing
@testable import ProviderKit

struct HeliusDASNFTServiceTests {
    @Test("Helius DAS service maps paged Solana assets into NFT rows")
    func mapsPagedAssetsIntoNFTs() async throws {
        let recorder = HeliusDASRequestRecorder()
        let session = URLSession.mocked { request in
            recorder.record(request)
            return recorder.response(for: request)
        }
        let service = HeliusDASNFTService(
            apiKey: "helius-test-key",
            session: session,
            endpointBaseURL: URL(string: "https://helius.example")!,
            pageLimit: 2
        )

        let firstPage = try await service.nftsForOwner(owner: "Owner111111111111111111111111111111111111", pageKey: nil)
        let secondPage = try await service.nftsForOwner(owner: "Owner111111111111111111111111111111111111", pageKey: firstPage.pageKey)

        #expect(firstPage.ownedNfts.count == 2)
        #expect(firstPage.pageKey == "2")
        #expect(secondPage.ownedNfts.count == 1)
        #expect(secondPage.pageKey == nil)
        let firstNFT = try #require(firstPage.ownedNfts.first)
        #expect(firstNFT.contract?.chain == .solanaMainnet)
        #expect(firstNFT.tokenURI == "https://example.com/mint-1.json")
        let content = try #require(firstNFT.raw?.metadata?["content"]?.objectValue)
        let files = try #require(content["files"]?.arrayValue)
        let firstFile = try #require(files.first?.objectValue)
        #expect(firstFile["cdn_uri"]?.stringValue == "https://cdn.example/mint-1.mp3")
        #expect(firstFile["mime"]?.stringValue == "audio/mpeg")
        #expect(recorder.pages == [1, 2])
        #expect(recorder.methods == ["getAssetsByOwner", "getAssetsByOwner"])
        #expect(recorder.tokenTypes.isEmpty)
        #expect(recorder.optionValues(for: "showUnverifiedCollections") == [true, true])
        #expect(recorder.optionValues(for: "showCollectionMetadata") == [true, true])
        #expect(recorder.optionValues(for: "showFungible") == [false, false])
        #expect(recorder.optionValues(for: "showZeroBalance") == [false, false])
        #expect(recorder.optionValues(for: "showGrandTotal").isEmpty)
        #expect(recorder.urls.allSatisfy { $0.query == "api-key=helius-test-key" })
    }

    @Test("Helius DAS service skips assets not owned by the requested wallet")
    func skipsOwnerMismatch() async throws {
        let recorder = HeliusDASRequestRecorder(mode: .ownerMismatch)
        let session = URLSession.mocked { request in
            recorder.record(request)
            return recorder.response(for: request)
        }
        let service = HeliusDASNFTService(
            apiKey: "helius-test-key",
            session: session,
            endpointBaseURL: URL(string: "https://helius.example")!,
            pageLimit: 2
        )

        let page = try await service.nftsForOwner(owner: "Owner111111111111111111111111111111111111", pageKey: nil)

        #expect(page.ownedNfts.map(\.tokenId) == ["mint-owned"])
    }

    @Test("Helius DAS service maps JSON-RPC authorization errors")
    func mapsRPCAuthorizationErrors() async throws {
        let recorder = HeliusDASRequestRecorder(mode: .rpcUnauthorized)
        let session = URLSession.mocked { request in
            recorder.record(request)
            return recorder.response(for: request)
        }
        let service = HeliusDASNFTService(
            apiKey: "helius-test-key",
            session: session,
            endpointBaseURL: URL(string: "https://helius.example")!,
            pageLimit: 2
        )

        await #expect(throws: ProviderAbstractionError.unauthorized) {
            _ = try await service.nftsForOwner(owner: "Owner111111111111111111111111111111111111", pageKey: nil)
        }
    }

    @Test("Helius DAS service treats documented empty-owner 404s as empty NFT pages")
    func mapsDocumentedEmptyOwner404ToEmptyPage() async throws {
        let recorder = HeliusDASRequestRecorder(mode: .emptyNotFound)
        let session = URLSession.mocked { request in
            recorder.record(request)
            return recorder.response(for: request)
        }
        let service = HeliusDASNFTService(
            apiKey: "helius-test-key",
            session: session,
            endpointBaseURL: URL(string: "https://helius.example")!,
            pageLimit: 2
        )

        let page = try await service.nftsForOwner(owner: "Owner111111111111111111111111111111111111", pageKey: nil)

        #expect(page.ownedNfts.isEmpty)
        #expect(page.totalCount == 0)
        #expect(page.pageKey == nil)
    }

    @Test("Helius DAS service retries HTTP rate limits before mapping the final page")
    func retriesRateLimitedHTTPResponses() async throws {
        let recorder = HeliusDASRequestRecorder(mode: .rateLimitedThenSuccess)
        let session = URLSession.mocked { request in
            recorder.record(request)
            return recorder.response(for: request)
        }
        let service = HeliusDASNFTService(
            apiKey: "helius-test-key",
            session: session,
            endpointBaseURL: URL(string: "https://helius.example")!,
            pageLimit: 2,
            maxRetryCount: 2,
            baseDelayNanoseconds: 1,
            maxDelayNanoseconds: 1
        )

        let page = try await service.nftsForOwner(owner: "Owner111111111111111111111111111111111111", pageKey: nil)

        #expect(page.ownedNfts.map(\.tokenId) == ["mint-1", "mint-2"])
        #expect(recorder.requestCount == 2)
    }
}

private final class HeliusDASRequestRecorder: @unchecked Sendable {
    enum Mode: Sendable {
        case paged
        case ownerMismatch
        case rpcUnauthorized
        case emptyNotFound
        case rateLimitedThenSuccess
    }

    private let lock = NSLock()
    private let mode: Mode
    private var requests: [URLRequest] = []

    init(mode: Mode = .paged) {
        self.mode = mode
    }

    var urls: [URL] {
        lock.withLock { requests.compactMap(\.url) }
    }

    var requestCount: Int {
        lock.withLock { requests.count }
    }

    var pages: [Int] {
        lock.withLock {
            requests.compactMap { Self.requestParams(from: $0)?["page"] as? Int }
        }
    }

    var methods: [String] {
        lock.withLock {
            requests.compactMap { Self.requestDictionary(from: $0)?["method"] as? String }
        }
    }

    var tokenTypes: [String] {
        lock.withLock {
            requests.compactMap { Self.requestParams(from: $0)?["tokenType"] as? String }
        }
    }

    func optionValues(for key: String) -> [Bool] {
        lock.withLock {
            requests.compactMap { request in
                let options = Self.requestParams(from: request)?["options"] as? [String: Any]
                return options?[key] as? Bool
            }
        }
    }

    func record(_ request: URLRequest) {
        lock.withLock { requests.append(request) }
    }

    func response(for request: URLRequest) -> (URLResponse, Data) {
        switch mode {
        case .paged:
            return successResponse(request: request, payload: pagedPayload(page: pages.last ?? 1))
        case .ownerMismatch:
            return successResponse(request: request, payload: ownerMismatchPayload)
        case .rpcUnauthorized:
            return successResponse(request: request, payload: rpcUnauthorizedPayload)
        case .emptyNotFound:
            return httpResponse(statusCode: 404, request: request)
        case .rateLimitedThenSuccess:
            if requestCount == 1 {
                return httpResponse(
                    statusCode: 429,
                    request: request,
                    headers: ["Retry-After": "0"]
                )
            }
            return successResponse(request: request, payload: pagedPayload(page: pages.last ?? 1))
        }
    }

    private static func requestDictionary(from request: URLRequest) -> [String: Any]? {
        guard let body = request.httpBody,
              let object = try? JSONSerialization.jsonObject(with: body) else {
            return nil
        }
        return object as? [String: Any]
    }

    private static func requestParams(from request: URLRequest) -> [String: Any]? {
        requestDictionary(from: request)?["params"] as? [String: Any]
    }

    private func pagedPayload(page: Int) -> String {
        if page == 1 {
            return """
            {
              "jsonrpc": "2.0",
              "result": {
                "page": 1,
                "items": [
                  \(assetJSON(id: "mint-1", owner: "Owner111111111111111111111111111111111111")),
                  \(assetJSON(id: "mint-2", owner: "Owner111111111111111111111111111111111111"))
                ]
              }
            }
            """
        }

        return """
        {
          "jsonrpc": "2.0",
          "result": {
            "page": 2,
            "items": [
              \(assetJSON(id: "mint-3", owner: "Owner111111111111111111111111111111111111"))
            ]
          }
        }
        """
    }

    private var ownerMismatchPayload: String {
        """
        {
          "jsonrpc": "2.0",
          "result": {
            "page": 1,
            "items": [
              \(assetJSON(id: "mint-owned", owner: "Owner111111111111111111111111111111111111")),
              \(assetJSON(id: "mint-skipped", owner: "OtherOwner111111111111111111111111111111111"))
            ]
          }
        }
        """
    }

    private var rpcUnauthorizedPayload: String {
        """
        {
          "jsonrpc": "2.0",
          "error": {
            "code": -32001,
            "message": "Authentication failed. Missing or invalid API key."
          },
          "id": "1"
        }
        """
    }

    private func assetJSON(id: String, owner: String) -> String {
        """
        {
          "id": "\(id)",
          "interface": "ProgrammableNFT",
          "content": {
            "metadata": {
              "name": "\(id)",
              "description": "Description",
              "symbol": "AURA"
            },
            "links": {
              "image": "https://example.com/\(id).png",
              "animation_url": null,
              "audio_url": null
            },
            "json_uri": "https://example.com/\(id).json",
            "files": [
              {"uri": "https://example.com/\(id).mp3", "cdn_uri": "https://cdn.example/\(id).mp3", "mime": "audio/mpeg"}
            ]
          },
          "grouping": [
            {"group_key": "collection", "group_value": "collection-1"}
          ],
          "creators": [],
          "ownership": {
            "owner": "\(owner)"
          }
        }
        """
    }

    private func successResponse(request: URLRequest, payload: String) -> (URLResponse, Data) {
        httpResponse(statusCode: 200, request: request, body: Data(payload.utf8))
    }

    private func httpResponse(
        statusCode: Int,
        request: URLRequest,
        headers: [String: String]? = nil,
        body: Data = Data()
    ) -> (URLResponse, Data) {
        let url = request.url ?? URL(string: "https://example.com")!
        let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: headers)!
        return (response, body)
    }
}
