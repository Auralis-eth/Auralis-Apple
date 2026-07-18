import AuralisPrimaryModels
import AuralisTestSupport
@testable import MusicFeature
import Foundation
import Testing

struct AlchemyNFTClientTests {
    @Test("Alchemy client paginates getNFTsForOwner and maps token DTOs")
    func alchemyClientPaginatesAndMapsTokens() async throws {
        let recorder = AlchemyRequestRecorder(mode: .twoPages)
        let client = Self.makeClient(recorder: recorder, pageSize: 100)

        let tokens = try await client.fetchAll(owner: "0xOwner", chain: .ethMainnet)

        #expect(tokens.count == 147)
        #expect(tokens.prefix(3).map(\.tokenId) == ["1", "2", "3"])
        #expect(tokens.last?.tokenId == "147")
        #expect(tokens.allSatisfy { $0.provider == .alchemy })
        #expect(tokens.allSatisfy { $0.chain == .ethMainnet })
        #expect(tokens.first?.contractAddress == "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd")
        #expect(tokens.first?.imageURL == "https://cdn.example/1.png")
        #expect(tokens.first?.metadataURL == "ipfs://metadata-1")
        #expect(tokens.first?.metadataRaw?.contains("\"Track 1\"") == true)
        #expect(recorder.pageKeys == [nil, "next"])
        #expect(recorder.endpointURLs.allSatisfy { !$0.absoluteString.contains("real-api-key") })
    }

    @Test("Alchemy client stops on an empty response")
    func alchemyClientReturnsEmptyResults() async throws {
        let recorder = AlchemyRequestRecorder(mode: .empty)
        let client = Self.makeClient(recorder: recorder, pageSize: 100)

        let tokens = try await client.fetchAll(owner: "0xOwner", chain: .ethMainnet)

        #expect(tokens.isEmpty)
        #expect(recorder.pageKeys == [nil])
    }

    @Test("Alchemy client keeps one DTO per ERC-1155 token regardless of balance")
    func alchemyClientDoesNotMultiplyERC1155Balances() async throws {
        let recorder = AlchemyRequestRecorder(mode: .erc1155Balance)
        let client = Self.makeClient(recorder: recorder, pageSize: 100)

        let tokens = try await client.fetchAll(owner: "0xOwner", chain: .polygonMainnet)

        #expect(tokens.count == 1)
        #expect(tokens.first?.tokenStandard == "ERC1155")
        #expect(tokens.first?.tokenId == "1155")
    }

    @Test("Alchemy client retries rate limits and throws typed network error")
    func alchemyClientRetriesRateLimits() async throws {
        let recorder = AlchemyRequestRecorder(mode: .rateLimited)
        let client = Self.makeClient(recorder: recorder, pageSize: 100, retryCount: 3)

        do {
            _ = try await client.fetchAll(owner: "0xOwner", chain: .ethMainnet)
            Issue.record("Expected Alchemy rate limit to throw.")
        } catch let error as AuraPlayError {
            #expect(error == .network(.rateLimited))
        } catch {
            Issue.record("Expected AuraPlayError.network(.rateLimited), got \(error).")
        }

        #expect(recorder.pageKeys == [nil, nil, nil])
    }

    private static func makeClient(
        recorder: AlchemyRequestRecorder,
        pageSize: Int,
        retryCount: Int = 3
    ) -> AlchemyNFTClient {
        let session = URLSession.mocked { request in
            recorder.record(request)
            return recorder.response(for: request)
        }

        return AlchemyNFTClient(
            apiKey: "test-key",
            urlSession: session,
            endpointBaseURLs: [
                .ethMainnet: URL(string: "https://alchemy.example/nft/v3/test-key")!,
                .polygonMainnet: URL(string: "https://polygon-alchemy.example/nft/v3/test-key")!,
            ],
            pageSize: pageSize,
            retryCount: retryCount,
            retryDelayNanoseconds: 1
        )
    }
}

private final class AlchemyRequestRecorder: @unchecked Sendable {
    enum Mode: Sendable {
        case twoPages
        case empty
        case erc1155Balance
        case rateLimited
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

    var pageKeys: [String?] {
        lock.withLock {
            requests.map { request in
                guard let url = request.url,
                      let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                    return nil
                }
                return components.queryItems?.first { $0.name == "pageKey" }?.value
            }
        }
    }

    func record(_ request: URLRequest) {
        lock.withLock {
            requests.append(request)
        }
    }

    func response(for request: URLRequest) -> (URLResponse, Data) {
        switch mode {
        case .twoPages:
            return successResponse(request: request, payload: twoPagePayload(pageKey: pageKeys.last ?? nil))
        case .empty:
            return successResponse(request: request, payload: """
            {"ownedNfts":[],"totalCount":0}
            """)
        case .erc1155Balance:
            return successResponse(request: request, payload: """
            {"ownedNfts":[\(nftJSON(tokenId: "1155", tokenType: "ERC1155", balance: "5"))],"totalCount":1}
            """)
        case .rateLimited:
            return httpResponse(statusCode: 429, request: request)
        }
    }

    private func twoPagePayload(pageKey: String?) -> String {
        if pageKey == nil {
            let nfts = (1...100)
                .map { nftJSON(tokenId: "\($0)", tokenType: "ERC721") }
                .joined(separator: ",")
            return """
            {
              "ownedNfts": [\(nfts)],
              "pageKey": "next",
              "totalCount": 147
            }
            """
        }

        let nfts = (101...147)
            .map { nftJSON(tokenId: "\($0)", tokenType: "ERC721") }
            .joined(separator: ",")
        return """
        {
          "ownedNfts": [\(nfts)],
          "totalCount": 147
        }
        """
    }

    private func nftJSON(tokenId: String, tokenType: String, balance: String? = nil) -> String {
        """
        {
          "contract": {
            "address": "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd"
          },
          "tokenId": "\(tokenId)",
          "tokenType": "\(tokenType)",
          "name": "Track \(tokenId)",
          "description": "Description \(tokenId)",
          "image": {
            "cachedUrl": "https://cdn.example/\(tokenId).png",
            "originalUrl": "ipfs://image-\(tokenId).png"
          },
          "raw": {
            "metadata": {
              "name": "Track \(tokenId)",
              "animation_url": "ipfs://track-\(tokenId).mp3"
            },
            "tokenUri": "ipfs://metadata-\(tokenId)"
          },
          "collection": {
            "name": "Alchemy Collection"
          },
          "timeLastUpdated": "2026-01-01T00:00:00Z",
          "balance": \(balance.map { "\"\($0)\"" } ?? "null")
        }
        """
    }

    private func successResponse(request: URLRequest, payload: String) -> (URLResponse, Data) {
        httpResponse(statusCode: 200, request: request, body: Data(payload.utf8))
    }

    private func httpResponse(
        statusCode: Int,
        request: URLRequest,
        body: Data = Data()
    ) -> (URLResponse, Data) {
        let url = request.url ?? URL(string: "https://example.com")!
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response, body)
    }
}
