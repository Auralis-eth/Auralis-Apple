import AuralisPrimaryModels
import AuralisTestSupport
@testable import MusicFeature
import Foundation
import Testing

struct HeliusNFTClientTests {
    @Test("Helius client paginates getAssetsByOwner and maps Solana token DTOs")
    func heliusClientPaginatesAndMapsTokens() async throws {
        let recorder = HeliusRequestRecorder(mode: .twoPages)
        let client = Self.makeClient(recorder: recorder, pageLimit: 1000)

        let tokens = try await client.fetchAll(owner: "OwnerAddress")

        #expect(tokens.count == 1250)
        #expect(tokens.prefix(3).map { $0.tokenId } == ["mint-1", "mint-2", "mint-3"])
        #expect(tokens.last?.tokenId == "mint-1250")
        #expect(tokens.allSatisfy { $0.chain == Chain.solanaMainnet })
        #expect(tokens.allSatisfy { $0.provider == NFTDiscoveryProvider.helius })
        #expect(tokens.first?.contractAddress == "collection-1")
        #expect(tokens.first?.metadataURL == "https://example.com/1.json")
        #expect(tokens.first?.metadataRaw?.contains("\"mint-1\"") == true)
        #expect(recorder.requestPages == [1, 2])
        #expect(recorder.requestMethods == ["getAssetsByOwner", "getAssetsByOwner"])
        #expect(recorder.tokenTypes.isEmpty)
        #expect(recorder.optionValues(for: "showUnverifiedCollections") == [true, true])
        #expect(recorder.optionValues(for: "showCollectionMetadata") == [true, true])
        #expect(recorder.optionValues(for: "showFungible") == [false, false])
        #expect(recorder.optionValues(for: "showZeroBalance") == [false, false])
        #expect(recorder.optionValues(for: "showGrandTotal").isEmpty)
        #expect(recorder.endpointURLs.allSatisfy { $0.query == "api-key=test-key" })
    }

    @Test("Helius client skips assets whose ownership owner does not match")
    func heliusClientSkipsOwnerMismatch() async throws {
        let recorder = HeliusRequestRecorder(mode: .ownerMismatch)
        let warnings = WarningRecorder()
        let client = Self.makeClient(recorder: recorder, pageLimit: 2, warningRecorder: warnings)

        let tokens = try await client.fetchAll(owner: "OwnerAddress")

        #expect(tokens.map { $0.tokenId } == ["mint-owned"])
        #expect(warnings.messages.count == 1)
        #expect(warnings.messages.first?.contains("mint-skipped") == true)
    }

    @Test("Helius client retries rate limits and then throws")
    func heliusClientRetriesRateLimits() async throws {
        let recorder = HeliusRequestRecorder(mode: .rateLimited)
        let client = Self.makeClient(recorder: recorder, pageLimit: 2, retryCount: 3)

        do {
            _ = try await client.fetchAll(owner: "OwnerAddress")
            Issue.record("Expected Helius rate limit to throw.")
        } catch let error as AuraPlayError {
            #expect(error == .network(.rateLimited))
        } catch {
            Issue.record("Expected AuraPlayError.network(.rateLimited), got \(error).")
        }

        #expect(recorder.requestPages == [1, 1, 1])
    }

    @Test("Helius client maps JSON-RPC authorization errors")
    func heliusClientMapsRPCAuthorizationErrors() async throws {
        let recorder = HeliusRequestRecorder(mode: .rpcUnauthorized)
        let client = Self.makeClient(recorder: recorder, pageLimit: 2)

        do {
            _ = try await client.fetchAll(owner: "OwnerAddress")
            Issue.record("Expected Helius authorization error to throw.")
        } catch let error as AuraPlayError {
            #expect(error == .library("Helius NFT discovery is not authorized for this API key."))
        } catch {
            Issue.record("Expected AuraPlayError.library authorization message, got \(error).")
        }
    }

    @Test("Helius client treats documented empty-owner 404s as an empty library")
    func heliusClientMapsDocumentedEmptyOwner404ToEmptyLibrary() async throws {
        let recorder = HeliusRequestRecorder(mode: .emptyNotFound)
        let client = Self.makeClient(recorder: recorder, pageLimit: 2)

        let tokens = try await client.fetchAll(owner: "OwnerAddress")

        #expect(tokens.isEmpty)
        #expect(recorder.requestCount == 1)
    }

    @Test("Helius client retries HTTP rate limits with Retry-After")
    func heliusClientRetriesRateLimitsWithRetryAfter() async throws {
        let recorder = HeliusRequestRecorder(mode: .rateLimitedThenSuccess)
        let client = Self.makeClient(recorder: recorder, pageLimit: 1000, retryCount: 2)

        let tokens = try await client.fetchAll(owner: "OwnerAddress")

        #expect(tokens.count == 1250)
        #expect(recorder.requestPages == [1, 1, 2])
    }

    private static func makeClient(
        recorder: HeliusRequestRecorder,
        pageLimit: Int,
        retryCount: Int = 3,
        warningRecorder: WarningRecorder? = nil
    ) -> HeliusNFTClient {
        let session = URLSession.mocked { request in
            recorder.record(request)
            return recorder.response(for: request)
        }

        return HeliusNFTClient(
            apiKey: "test-key",
            urlSession: session,
            endpointBaseURL: URL(string: "https://helius.example")!,
            pageLimit: pageLimit,
            retryCount: retryCount,
            retryDelayNanoseconds: 1,
            warningLogger: { warningRecorder?.record($0) }
        )
    }
}

private final class WarningRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []

    var messages: [String] {
        lock.withLock { values }
    }

    func record(_ message: String) {
        lock.withLock {
            values.append(message)
        }
    }
}

private final class HeliusRequestRecorder: @unchecked Sendable {
    enum Mode: Sendable {
        case twoPages
        case ownerMismatch
        case rateLimited
        case rpcUnauthorized
        case emptyNotFound
        case rateLimitedThenSuccess
    }

    private let lock = NSLock()
    private let mode: Mode
    private var requests: [URLRequest] = []

    init(mode: Mode) {
        self.mode = mode
    }

    var endpointURLs: [URL] {
        lock.withLock {
            requests.compactMap(\.url)
        }
    }

    var requestCount: Int {
        lock.withLock { requests.count }
    }

    var requestPages: [Int] {
        lock.withLock {
            requests.compactMap { request in
                Self.requestParams(from: request)?["page"] as? Int
            }
        }
    }

    var requestMethods: [String] {
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
        lock.withLock {
            requests.append(request)
        }
    }

    private static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let bodyStream = request.httpBodyStream else {
            return nil
        }

        bodyStream.open()
        defer { bodyStream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while bodyStream.hasBytesAvailable {
            let count = bodyStream.read(&buffer, maxLength: buffer.count)
            if count > 0 {
                data.append(buffer, count: count)
            } else {
                break
            }
        }
        return data
    }

    private static func requestDictionary(from request: URLRequest) -> [String: Any]? {
        guard let body = bodyData(from: request),
              let object = try? JSONSerialization.jsonObject(with: body) else {
            return nil
        }
        return object as? [String: Any]
    }

    private static func requestParams(from request: URLRequest) -> [String: Any]? {
        requestDictionary(from: request)?["params"] as? [String: Any]
    }

    func response(for request: URLRequest) -> (URLResponse, Data) {
        switch mode {
        case .twoPages:
            return successResponse(request: request, payload: payloadForTwoPages(page: requestPages.last ?? 1))
        case .ownerMismatch:
            return successResponse(request: request, payload: ownerMismatchPayload)
        case .rateLimited:
            return httpResponse(statusCode: 429, request: request)
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
            return successResponse(request: request, payload: payloadForTwoPages(page: requestPages.last ?? 1))
        }
    }

    private func payloadForTwoPages(page: Int) -> String {
        if page == 1 {
            let assets = (1...1000)
                .map { assetJSON(id: "mint-\($0)", owner: "OwnerAddress", collection: "collection-\($0)", name: "Asset \($0)") }
                .joined(separator: ",")
            return """
            {
              "jsonrpc": "2.0",
              "result": {
                "page": 1,
                "items": [\(assets)]
              }
            }
            """
        }

        let assets = (1001...1250)
            .map { assetJSON(id: "mint-\($0)", owner: "OwnerAddress", collection: "collection-\($0)", name: "Asset \($0)") }
            .joined(separator: ",")
        return """
        {
          "jsonrpc": "2.0",
          "result": {
            "page": 2,
            "items": [\(assets)]
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
              \(assetJSON(id: "mint-owned", owner: "OwnerAddress", collection: "collection-1", name: "Owned")),
              \(assetJSON(id: "mint-skipped", owner: "OtherOwner", collection: "collection-2", name: "Skipped"))
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

    private func assetJSON(id: String, owner: String, collection: String, name: String) -> String {
        """
        {
          "id": "\(id)",
          "interface": "ProgrammableNFT",
          "content": {
            "metadata": {
              "name": "\(name)",
              "description": "Description",
              "symbol": "AURA"
            },
            "links": {
              "image": "https://example.com/\(id).png",
              "animation_url": null,
              "audio_url": null
            },
            "json_uri": "https://example.com/\(id.replacingOccurrences(of: "mint-", with: "")).json",
            "files": []
          },
          "grouping": [
            {"group_key": "collection", "group_value": "\(collection)"}
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
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: headers
        )!
        return (response, body)
    }
}
