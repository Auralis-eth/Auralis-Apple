@testable import Auralis
import AuralisPrimaryModels
import AuralisPrimaryPersistence
import Foundation
import ProviderKit
import Testing
import NFTDomain
import NFTPersistence
import NFTPresentation
import NFTProviderAdapters

@Suite(.serialized)
struct ProviderAbstractionTests {
    @Test("provider configuration resolves centralized Alchemy endpoints for an EVM chain")
    func resolverBuildsExpectedEndpoints() throws {
        let resolver = LiveProviderConfigurationResolver { provider in
            provider == .alchemy ? "alchemy-key" : nil
        }

        let configuration = try resolver.configuration(for: .baseMainnet)

        #expect(configuration.alchemyNFTBaseURL?.absoluteString == "https://base-mainnet.g.alchemy.com/nft/v3/alchemy-key")
        #expect(configuration.alchemyDataAPIBaseURL?.absoluteString == "https://api.g.alchemy.com/data/v1/alchemy-key")
        #expect(configuration.alchemyRPCURL?.absoluteString == "https://base-mainnet.g.alchemy.com/v2/alchemy-key")
    }

    @Test("provider configuration leaves unsupported RPC-backed endpoints empty for Solana")
    func resolverDropsUnsupportedRPCEndpoints() throws {
        let resolver = LiveProviderConfigurationResolver { _ in "shared-key" }

        let configuration = try resolver.configuration(for: .solanaMainnet)

        #expect(configuration.alchemyNFTBaseURL?.absoluteString == "https://solana-mainnet.g.alchemy.com/nft/v3/shared-key")
        #expect(configuration.alchemyDataAPIBaseURL?.absoluteString == "https://api.g.alchemy.com/data/v1/shared-key")
        #expect(configuration.alchemyRPCURL == nil)
    }

    @Test("Retry-After parser accepts numeric seconds")
    func retryAfterParserAcceptsNumericSeconds() {
        #expect(RetryAfterSupport.parse("2.5") == 2.5)
    }

    @Test("Retry-After parser accepts HTTP-date values")
    func retryAfterParserAcceptsHTTPDates() throws {
        let now = try #require(DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(secondsFromGMT: 0),
            year: 2026,
            month: 5,
            day: 8,
            hour: 12
        ).date)

        #expect(RetryAfterSupport.parse("Fri, 08 May 2026 12:00:05 GMT", now: now) == 5)
    }

    @Test("native balance provider maps missing RPC configuration to missing API key")
    func nativeBalanceProviderMapsMissingRPCConfiguration() async {
        let provider = AlchemyRPCProvider(
            configurationResolver: StubProviderConfigurationResolver(
                configuration: ProviderEndpointConfiguration(
                    chain: .baseMainnet,
                    alchemyNFTBaseURL: nil,
                    alchemyDataAPIBaseURL: nil,
                    alchemyRPCURL: nil
                )
            ),
            maxRetryCount: 1
        )

        await #expect(throws: ProviderAbstractionError.missingAPIKey(.alchemy)) {
            try await provider.nativeBalance(
                for: "0x1234567890abcdef1234567890abcdef12345678",
                chain: .baseMainnet
            )
        }
    }

    @Test("native balance provider forwards invalid endpoint configuration")
    func nativeBalanceProviderForwardsInvalidEndpointConfiguration() async {
        let provider = AlchemyRPCProvider(
            configurationResolver: ThrowingProviderConfigurationResolver(error: .invalidURL),
            maxRetryCount: 1
        )

        await #expect(throws: ProviderAbstractionError.invalidURL) {
            try await provider.nativeBalance(
                for: "0x1234567890abcdef1234567890abcdef12345678",
                chain: .baseMainnet
            )
        }
    }

    @Test("Alchemy NFT service throws DecodingError when a success response body is malformed")
    @MainActor
    func alchemyNFTServiceSurfacesMalformedSuccessBody() async throws {
        let session = makeMockSession()
        let service = try AlchemyNFTService(
            chain: .ethMainnet,
            configurationResolver: LiveProviderConfigurationResolver { provider in
                provider == .alchemy ? "alchemy-key" : nil
            },
            session: session
        )

        ProviderMockURLProtocol.handler = { request in
            #expect(request.url?.absoluteString == "https://eth-mainnet.g.alchemy.com/nft/v3/alchemy-key/getNFTsForOwner?owner=0x1234567890abcdef1234567890abcdef12345678&withMetadata=true&pageSize=100")
            #expect(request.httpMethod == "GET")

            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let data = Data(#"{"ownedNfts":"definitely-not-an-array","totalCount":1}"#.utf8)
            return (response, data)
        }
        defer {
            ProviderMockURLProtocol.handler = nil
        }

        do {
            _ = try await service.nftsForOwner(
                owner: "0x1234567890abcdef1234567890abcdef12345678",
                pageKey: nil
            )
            Issue.record("Expected malformed success payload to throw DecodingError.")
        } catch is DecodingError {
        } catch {
            Issue.record("Expected DecodingError, got \(error)")
        }
    }

    @Test("Alchemy NFT service tolerates missing optional envelope fields when NFT rows still decode")
    @MainActor
    func alchemyNFTServiceAllowsMissingOptionalEnvelopeFields() async throws {
        let session = makeMockSession()
        let service = try AlchemyNFTService(
            chain: .ethMainnet,
            configurationResolver: LiveProviderConfigurationResolver { provider in
                provider == .alchemy ? "alchemy-key" : nil
            },
            session: session
        )

        ProviderMockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let payload = Data(
                """
                {
                  "ownedNfts": [],
                  "pageKey": "cursor-1"
                }
                """.utf8
            )
            return (response, payload)
        }
        defer {
            ProviderMockURLProtocol.handler = nil
        }

        let response = try await service.nftsForOwner(
            owner: "0x1234567890abcdef1234567890abcdef12345678",
            pageKey: nil
        )

        #expect(response.ownedNfts.isEmpty)
        #expect(response.totalCount == nil)
        #expect(response.validAt == nil)
        #expect(response.pageKey == "cursor-1")
    }

    @Test("Alchemy NFT service retries a single request in degraded mode without latching future calls")
    @MainActor
    func alchemyNFTServiceDoesNotLatchDegradedModeAcrossRequests() async throws {
        let session = makeMockSession()
        let service = try AlchemyNFTService(
            chain: .ethMainnet,
            configurationResolver: LiveProviderConfigurationResolver { provider in
                provider == .alchemy ? "alchemy-key" : nil
            },
            session: session
        )
        let requestedURLs = ArrayRecorder<String>()

        ProviderMockURLProtocol.handler = { request in
            let requestURL = try #require(request.url?.absoluteString)
            requestedURLs.append(requestURL)
            let attempt = requestedURLs.values().count

            if attempt == 1 {
                let response = HTTPURLResponse(
                    url: try #require(request.url),
                    statusCode: 503,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, Data(#"{"message":"temporarily unavailable"}"#.utf8))
            }

            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let payload = Data(
                """
                {
                  "ownedNfts": [],
                  "totalCount": 0,
                  "pageKey": null,
                  "validAt": {
                    "blockNumber": 1,
                    "blockHash": "0xabc",
                    "blockTimestamp": "2025-01-01T00:00:00Z"
                  }
                }
                """.utf8
            )
            return (response, payload)
        }
        defer {
            ProviderMockURLProtocol.handler = nil
        }

        _ = try await service.nftsForOwner(
            owner: "0x1234567890abcdef1234567890abcdef12345678",
            pageKey: nil
        )
        _ = try await service.nftsForOwner(
            owner: "0x1234567890abcdef1234567890abcdef12345678",
            pageKey: nil
        )

        let urls = requestedURLs.values()
        #expect(urls.count == 3)
        #expect(urls[0].contains("withMetadata=true"))
        #expect(urls[1].contains("withMetadata=false"))
        #expect(urls[1].contains("pageSize=50"))
        #expect(urls[2].contains("withMetadata=true"))
    }

    @Test("token balances provider calls the exact Alchemy balances endpoint and preserves pagination state")
    @MainActor
    func tokenBalancesProviderCallsExactEndpoint() async throws {
        let session = makeMockSession()
        let provider = AlchemyTokenHoldingsProvider(
            configurationResolver: LiveProviderConfigurationResolver { _ in "alchemy-key" },
            session: session
        )

        ProviderMockURLProtocol.handler = { request in
            #expect(request.url?.absoluteString == "https://api.g.alchemy.com/data/v1/alchemy-key/assets/tokens/balances/by-address")
            #expect(request.httpMethod == "POST")

            let body = try #require(request.bodyData)
            let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let addresses = try #require(payload["addresses"] as? [[String: Any]])
            #expect(addresses.count == 2)
            #expect(addresses[0]["address"] as? String == "0x1234567890abcdef1234567890abcdef12345678")
            #expect(addresses[0]["networks"] as? [String] == [Chain.baseMainnet.rawValue, Chain.ethMainnet.rawValue])
            #expect(addresses[1]["address"] as? String == "So11111111111111111111111111111111111111112")
            #expect(addresses[1]["networks"] as? [String] == [Chain.solanaMainnet.rawValue])
            #expect(payload["includeNativeTokens"] as? Bool == true)
            #expect(payload["includeErc20Tokens"] as? Bool == true)
            #expect(payload["pageKey"] as? String == "cursor-1")

            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let data = Data(
                """
                {
                  "data": {
                    "tokens": [
                      {
                        "address": "0x1234567890abcdef1234567890abcdef12345678",
                        "network": "base-mainnet",
                        "tokenAddress": "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
                        "tokenBalance": "1234567"
                      },
                      {
                        "address": "So11111111111111111111111111111111111111112",
                        "network": "solana-mainnet",
                        "tokenAddress": null,
                        "tokenBalance": "42"
                      }
                    ],
                    "pageKey": "cursor-2"
                  }
                }
                """.utf8
            )
            return (response, data)
        }
        defer {
            ProviderMockURLProtocol.handler = nil
        }

        let page = try await provider.tokenBalances(
            for: TokenBalancesRequest(
                addresses: [
                    TokenBalancesAddress(
                        address: "0x1234567890abcdef1234567890abcdef12345678",
                        networks: [Chain.baseMainnet.rawValue, Chain.ethMainnet.rawValue]
                    ),
                    TokenBalancesAddress(
                        address: "So11111111111111111111111111111111111111112",
                        networks: [Chain.solanaMainnet.rawValue]
                    )
                ],
                includeNativeTokens: true,
                includeErc20Tokens: true,
                pageKey: "cursor-1"
            )
        )

        #expect(page.pageKey == "cursor-2")
        #expect(page.tokens.count == 2)
        #expect(page.tokens[0] == TokenBalanceRecord(
            network: "base-mainnet",
            address: "0x1234567890abcdef1234567890abcdef12345678",
            tokenAddress: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
            tokenBalance: "1234567"
        ))
        #expect(page.tokens[1] == TokenBalanceRecord(
            network: "solana-mainnet",
            address: "So11111111111111111111111111111111111111112",
            tokenAddress: nil,
            tokenBalance: "42"
        ))
    }

    @Test("token holdings provider uses the shared Alchemy data API and formats ERC-20 balances for persistence")
    @MainActor
    func tokenHoldingsProviderLoadsFormattedERC20Rows() async throws {
        let session = makeMockSession()
        let fixedNow = Date(timeIntervalSince1970: 1_756_240_247)
        let provider = AlchemyTokenHoldingsProvider(
            configurationResolver: LiveProviderConfigurationResolver { _ in "alchemy-key" },
            session: session,
            nowProvider: { fixedNow }
        )

        let requestedURLs = ArrayRecorder<String>()
        ProviderMockURLProtocol.handler = { request in
            let requestURL = try #require(request.url?.absoluteString)
            requestedURLs.append(requestURL)
            #expect(request.httpMethod == "POST")
            let body = try #require(request.bodyData)
            let payload = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let addresses = try #require(payload?["addresses"] as? [[String: Any]])
            let firstAddress = try #require(addresses.first)
            #expect(firstAddress["address"] as? String == "0x1234567890abcdef1234567890abcdef12345678")
            #expect(firstAddress["networks"] as? [String] == [Chain.baseMainnet.rawValue])

            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!

            let data: Data
            switch requestURL {
            case "https://api.g.alchemy.com/data/v1/alchemy-key/assets/tokens/balances/by-address":
                #expect(payload?["includeNativeTokens"] as? Bool == false)
                #expect(payload?["includeErc20Tokens"] as? Bool == true)
                data = Data(
                    """
                    {
                      "data": {
                        "tokens": [
                          {
                            "address": "0x1234567890abcdef1234567890abcdef12345678",
                            "network": "base-mainnet",
                            "tokenAddress": "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
                            "tokenBalance": "1234567"
                          }
                        ]
                      }
                    }
                    """.utf8
                )
            case "https://api.g.alchemy.com/data/v1/alchemy-key/assets/tokens/by-address":
                #expect(payload?["includeNativeTokens"] as? Bool == false)
                #expect(payload?["includeErc20Tokens"] as? Bool == true)
                #expect(payload?["withMetadata"] as? Bool == true)
                #expect(payload?["withPrices"] as? Bool == false)
                data = Data(
                    """
                    {
                      "data": {
                        "tokens": [
                          {
                            "address": "0x1234567890abcdef1234567890abcdef12345678",
                            "network": "base-mainnet",
                            "tokenAddress": "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
                            "tokenBalance": "9999999",
                            "tokenMetadata": {
                              "decimals": 6,
                              "logo": "https://example.com/usdc.png",
                              "name": "USD Coin",
                              "symbol": "USDC"
                            },
                            "error": null
                          }
                        ]
                      }
                    }
                    """.utf8
                )
            default:
                Issue.record("Unexpected URL: \(requestURL)")
                data = Data()
            }
            return (response, data)
        }
        defer {
            ProviderMockURLProtocol.handler = nil
        }

        let result = try await provider.tokenHoldings(
            for: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .baseMainnet
        )
        let holdings = result.holdings

        #expect(requestedURLs.values() == [
            "https://api.g.alchemy.com/data/v1/alchemy-key/assets/tokens/balances/by-address",
            "https://api.g.alchemy.com/data/v1/alchemy-key/assets/tokens/by-address"
        ])
        #expect(holdings.count == 1)
        #expect(holdings[0].contractAddress == "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48")
        #expect(holdings[0].symbol == "USDC")
        #expect(holdings[0].displayName == "USD Coin")
        #expect(holdings[0].amountDisplay == "1.234567 USDC")
        #expect(holdings[0].updatedAt == fixedNow)
        #expect(holdings[0].isPlaceholder == false)
        #expect(holdings[0].isAmountHidden == false)
    }

    @Test("token holdings provider preserves HTTP status and API message for non-retryable fetch failures")
    @MainActor
    func tokenHoldingsProviderPreservesHTTPFailureContext() async {
        let session = makeMockSession()
        let provider = AlchemyTokenHoldingsProvider(
            configurationResolver: LiveProviderConfigurationResolver { provider in
                provider == .alchemy ? "alchemy-key" : nil
            },
            session: session,
            maxRetryCount: 1
        )

        ProviderMockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 400,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (
                response,
                Data(#"{"message":"invalid wallet scope"}"#.utf8)
            )
        }
        defer {
            ProviderMockURLProtocol.handler = nil
        }

        do {
            _ = try await provider.tokenHoldings(
                for: "0x1234567890abcdef1234567890abcdef12345678",
                chain: .baseMainnet
            )
            Issue.record("Expected token holdings HTTP failure to throw.")
        } catch let error as ProviderAbstractionError {
            #expect(error == .badStatus(400, message: "invalid wallet scope"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("token holdings provider skips malformed rows instead of failing the whole balances page")
    @MainActor
    func tokenHoldingsProviderSkipsMalformedRows() async throws {
        let session = makeMockSession()
        let provider = AlchemyTokenHoldingsProvider(
            configurationResolver: LiveProviderConfigurationResolver { provider in
                provider == .alchemy ? "alchemy-key" : nil
            },
            session: session
        )

        ProviderMockURLProtocol.handler = { request in
            let requestURL = try #require(request.url?.absoluteString)
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!

            switch requestURL {
            case "https://api.g.alchemy.com/data/v1/alchemy-key/assets/tokens/balances/by-address":
                return (
                    response,
                    Data(
                        """
                        {
                          "data": {
                            "tokens": [
                              {
                                "address": "0x1234567890abcdef1234567890abcdef12345678",
                                "network": "base-mainnet",
                                "tokenAddress": "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
                                "tokenBalance": "1000000"
                              },
                              {
                                "address": 42,
                                "network": "base-mainnet",
                                "tokenAddress": "0xbad",
                                "tokenBalance": "oops"
                              }
                            ]
                          }
                        }
                        """.utf8
                    )
                )
            case "https://api.g.alchemy.com/data/v1/alchemy-key/assets/tokens/by-address":
                return (
                    response,
                    Data(
                        """
                        {
                          "data": {
                            "tokens": [
                              {
                                "tokenAddress": "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
                                "tokenBalance": "1000000",
                                "tokenMetadata": {
                                  "decimals": 6,
                                  "name": "USD Coin",
                                  "symbol": "USDC"
                                },
                                "error": null
                              },
                              {
                                "tokenAddress": 42,
                                "tokenBalance": "broken"
                              }
                            ]
                          }
                        }
                        """.utf8
                    )
                )
            default:
                Issue.record("Unexpected URL: \(requestURL)")
                return (response, Data())
            }
        }
        defer {
            ProviderMockURLProtocol.handler = nil
        }

        let result = try await provider.tokenHoldings(
            for: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .baseMainnet
        )

        #expect(result.holdings.count == 1)
        #expect(result.holdings[0].symbol == "USDC")
        #expect(result.holdings[0].amountDisplay == "1 USDC")
    }

    @Test("token holdings provider maps offline transport failures into provider abstraction errors")
    @MainActor
    func tokenHoldingsProviderMapsOfflineTransportFailures() async {
        let session = makeMockSession()
        let provider = AlchemyTokenHoldingsProvider(
            configurationResolver: LiveProviderConfigurationResolver { provider in
                provider == .alchemy ? "alchemy-key" : nil
            },
            session: session,
            maxRetryCount: 1
        )

        ProviderMockURLProtocol.handler = { _ in
            throw URLError(.notConnectedToInternet)
        }
        defer {
            ProviderMockURLProtocol.handler = nil
        }

        do {
            _ = try await provider.tokenHoldings(
                for: "0x1234567890abcdef1234567890abcdef12345678",
                chain: .baseMainnet
            )
            Issue.record("Expected offline token holdings refresh to throw.")
        } catch let error as ProviderAbstractionError {
            #expect(error == .offline)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("token holdings provider hides ERC-20 amounts when decimals are unavailable instead of showing raw base units")
    @MainActor
    func tokenHoldingsProviderHidesAmountWhenEnrichmentFails() async throws {
        let session = makeMockSession()
        let provider = AlchemyTokenHoldingsProvider(
            configurationResolver: LiveProviderConfigurationResolver { _ in "alchemy-key" },
            session: session
        )

        ProviderMockURLProtocol.handler = { request in
            let requestURL = try #require(request.url?.absoluteString)
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!

            switch requestURL {
            case "https://api.g.alchemy.com/data/v1/alchemy-key/assets/tokens/balances/by-address":
                return (
                    response,
                    Data(
                        """
                        {
                          "data": {
                            "tokens": [
                              {
                                "address": "0x1234567890abcdef1234567890abcdef12345678",
                                "network": "base-mainnet",
                                "tokenAddress": "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
                                "tokenBalance": "1000000"
                              }
                            ]
                          }
                        }
                        """.utf8
                    )
                )
            case "https://api.g.alchemy.com/data/v1/alchemy-key/assets/tokens/by-address":
                throw URLError(.badServerResponse)
            default:
                Issue.record("Unexpected URL: \(requestURL)")
                return (response, Data())
            }
        }
        defer {
            ProviderMockURLProtocol.handler = nil
        }

        let result = try await provider.tokenHoldings(
            for: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .baseMainnet
        )
        let holdings = result.holdings

        #expect(holdings.count == 1)
        #expect(holdings[0].displayName == "0xa0b8...eb48")
        #expect(holdings[0].amountDisplay == "Amount hidden")
        #expect(holdings[0].isPlaceholder)
        #expect(holdings[0].isAmountHidden)
        #expect(result.warning?.message.isEmpty == false)
    }

    @Test("token holdings provider treats balances-by-address as the quantity authority even when enrichment disagrees")
    @MainActor
    func tokenHoldingsProviderUsesBalanceEndpointAsAmountAuthority() async throws {
        let session = makeMockSession()
        let provider = AlchemyTokenHoldingsProvider(
            configurationResolver: LiveProviderConfigurationResolver { provider in
                provider == .alchemy ? "alchemy-key" : nil
            },
            session: session
        )

        ProviderMockURLProtocol.handler = { request in
            let requestURL = try #require(request.url?.absoluteString)
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!

            switch requestURL {
            case "https://api.g.alchemy.com/data/v1/alchemy-key/assets/tokens/balances/by-address":
                return (
                    response,
                    Data(
                        """
                        {
                          "data": {
                            "tokens": [
                              {
                                "address": "0x1234567890abcdef1234567890abcdef12345678",
                                "network": "base-mainnet",
                                "tokenAddress": "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
                                "tokenBalance": "1234567"
                              }
                            ]
                          }
                        }
                        """.utf8
                    )
                )
            case "https://api.g.alchemy.com/data/v1/alchemy-key/assets/tokens/by-address":
                return (
                    response,
                    Data(
                        """
                        {
                          "data": {
                            "tokens": [
                              {
                                "address": "0x1234567890abcdef1234567890abcdef12345678",
                                "network": "base-mainnet",
                                "tokenAddress": "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
                                "tokenBalance": "9999999",
                                "tokenMetadata": {
                                  "decimals": 6,
                                  "name": "USD Coin",
                                  "symbol": "USDC"
                                },
                                "error": null
                              }
                            ]
                          }
                        }
                        """.utf8
                    )
                )
            default:
                Issue.record("Unexpected URL: \(requestURL)")
                return (response, Data())
            }
        }
        defer {
            ProviderMockURLProtocol.handler = nil
        }

        let result = try await provider.tokenHoldings(
            for: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .baseMainnet
        )
        let holdings = result.holdings

        #expect(holdings.count == 1)
        #expect(holdings[0].amountDisplay == "1.234567 USDC")
    }

    @Test("token holdings provider merges every balances page and every enrichment page into one scoped result set")
    @MainActor
    func tokenHoldingsProviderPaginatesBalancesAndEnrichments() async throws {
        let session = makeMockSession()
        let provider = AlchemyTokenHoldingsProvider(
            configurationResolver: LiveProviderConfigurationResolver { provider in
                provider == .alchemy ? "alchemy-key" : nil
            },
            session: session
        )

        let balancePageKeys = ArrayRecorder<String?>()
        let enrichmentPageKeys = ArrayRecorder<String?>()

        ProviderMockURLProtocol.handler = { request in
            let requestURL = try #require(request.url?.absoluteString)
            let body = try #require(request.bodyData)
            let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!

            switch requestURL {
            case "https://api.g.alchemy.com/data/v1/alchemy-key/assets/tokens/balances/by-address":
                let pageKey = payload["pageKey"] as? String
                balancePageKeys.append(pageKey)
                if pageKey == nil {
                    return (
                        response,
                        Data(
                            """
                            {
                              "data": {
                                "tokens": [
                                  {
                                    "address": "0x1234567890abcdef1234567890abcdef12345678",
                                    "network": "base-mainnet",
                                    "tokenAddress": "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
                                    "tokenBalance": "1000000"
                                  }
                                ],
                                "pageKey": "balances-page-2"
                              }
                            }
                            """.utf8
                        )
                    )
                }

                return (
                    response,
                    Data(
                        """
                        {
                          "data": {
                            "tokens": [
                              {
                                "address": "0x1234567890abcdef1234567890abcdef12345678",
                                "network": "base-mainnet",
                                "tokenAddress": "0x6b175474e89094c44da98b954eedeac495271d0f",
                                "tokenBalance": "2500000000000000000"
                              }
                            ]
                          }
                        }
                        """.utf8
                    )
                )
            case "https://api.g.alchemy.com/data/v1/alchemy-key/assets/tokens/by-address":
                let pageKey = payload["pageKey"] as? String
                enrichmentPageKeys.append(pageKey)
                if pageKey == nil {
                    return (
                        response,
                        Data(
                            """
                            {
                              "data": {
                                "tokens": [
                                  {
                                    "address": "0x1234567890abcdef1234567890abcdef12345678",
                                    "network": "base-mainnet",
                                    "tokenAddress": "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
                                    "tokenBalance": "1",
                                    "tokenMetadata": {
                                      "decimals": 6,
                                      "name": "USD Coin",
                                      "symbol": "USDC"
                                    },
                                    "error": null
                                  }
                                ],
                                "pageKey": "enrichment-page-2"
                              }
                            }
                            """.utf8
                        )
                    )
                }

                return (
                    response,
                    Data(
                        """
                        {
                          "data": {
                            "tokens": [
                              {
                                "address": "0x1234567890abcdef1234567890abcdef12345678",
                                "network": "base-mainnet",
                                "tokenAddress": "0x6b175474e89094c44da98b954eedeac495271d0f",
                                "tokenBalance": "1",
                                "tokenMetadata": {
                                  "decimals": 18,
                                  "name": "Dai",
                                  "symbol": "DAI"
                                },
                                "error": null
                              }
                            ]
                          }
                        }
                        """.utf8
                    )
                )
            default:
                Issue.record("Unexpected URL: \(requestURL)")
                return (response, Data())
            }
        }
        defer {
            ProviderMockURLProtocol.handler = nil
        }

        let result = try await provider.tokenHoldings(
            for: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .baseMainnet
        )
        let holdings = result.holdings

        #expect(balancePageKeys.values() == [nil, "balances-page-2"])
        #expect(enrichmentPageKeys.values() == [nil, "enrichment-page-2"])
        #expect(holdings.map(\.contractAddress) == [
            "0x6b175474e89094c44da98b954eedeac495271d0f",
            "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"
        ])
        #expect(holdings.map(\.amountDisplay) == ["2.5 DAI", "1 USDC"])
    }

    @Test("token holdings provider ignores enrichment rows that do not belong to the balances set")
    @MainActor
    func tokenHoldingsProviderDiscardsMismatchedEnrichmentRows() async throws {
        let session = makeMockSession()
        let provider = AlchemyTokenHoldingsProvider(
            configurationResolver: LiveProviderConfigurationResolver { provider in
                provider == .alchemy ? "alchemy-key" : nil
            },
            session: session
        )

        ProviderMockURLProtocol.handler = { request in
            let requestURL = try #require(request.url?.absoluteString)
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!

            switch requestURL {
            case "https://api.g.alchemy.com/data/v1/alchemy-key/assets/tokens/balances/by-address":
                return (
                    response,
                    Data(
                        """
                        {
                          "data": {
                            "tokens": [
                              {
                                "address": "0x1234567890abcdef1234567890abcdef12345678",
                                "network": "base-mainnet",
                                "tokenAddress": "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
                                "tokenBalance": "1000000"
                              }
                            ]
                          }
                        }
                        """.utf8
                    )
                )
            case "https://api.g.alchemy.com/data/v1/alchemy-key/assets/tokens/by-address":
                return (
                    response,
                    Data(
                        """
                        {
                          "data": {
                            "tokens": [
                              {
                                "address": "0x1234567890abcdef1234567890abcdef12345678",
                                "network": "base-mainnet",
                                "tokenAddress": "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
                                "tokenBalance": "1",
                                "tokenMetadata": {
                                  "decimals": 6,
                                  "name": "USD Coin",
                                  "symbol": "USDC"
                                },
                                "error": null
                              },
                              {
                                "address": "0x1234567890abcdef1234567890abcdef12345678",
                                "network": "base-mainnet",
                                "tokenAddress": "0x1111111111111111111111111111111111111111",
                                "tokenBalance": "1",
                                "tokenMetadata": {
                                  "decimals": 18,
                                  "name": "Ghost Token",
                                  "symbol": "GHOST"
                                },
                                "error": null
                              }
                            ]
                          }
                        }
                        """.utf8
                    )
                )
            default:
                Issue.record("Unexpected URL: \(requestURL)")
                return (response, Data())
            }
        }
        defer {
            ProviderMockURLProtocol.handler = nil
        }

        let result = try await provider.tokenHoldings(
            for: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .baseMainnet
        )
        let holdings = result.holdings

        #expect(holdings.count == 1)
        #expect(holdings[0].contractAddress == "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48")
    }

    @Test("token holdings provider skips enrichment entirely when balances are empty")
    @MainActor
    func tokenHoldingsProviderSkipsEnrichmentForEmptyWallets() async throws {
        let session = makeMockSession()
        let provider = AlchemyTokenHoldingsProvider(
            configurationResolver: LiveProviderConfigurationResolver { provider in
                provider == .alchemy ? "alchemy-key" : nil
            },
            session: session
        )

        let requestedURLs = ArrayRecorder<String>()
        ProviderMockURLProtocol.handler = { request in
            let requestURL = try #require(request.url?.absoluteString)
            requestedURLs.append(requestURL)
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!

            return (
                response,
                Data(
                    """
                    {
                      "data": {
                        "tokens": []
                      }
                    }
                    """.utf8
                )
            )
        }
        defer {
            ProviderMockURLProtocol.handler = nil
        }

        let result = try await provider.tokenHoldings(
            for: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .baseMainnet
        )
        let holdings = result.holdings

        #expect(holdings.isEmpty)
        #expect(requestedURLs.values() == [
            "https://api.g.alchemy.com/data/v1/alchemy-key/assets/tokens/balances/by-address"
        ])
    }

    @Test("token holdings provider formats tiny high-decimal balances without collapsing them to zero")
    @MainActor
    func tokenHoldingsProviderFormatsTinyHighDecimalBalances() async throws {
        let session = makeMockSession()
        let provider = AlchemyTokenHoldingsProvider(
            configurationResolver: LiveProviderConfigurationResolver { provider in
                provider == .alchemy ? "alchemy-key" : nil
            },
            session: session
        )

        ProviderMockURLProtocol.handler = { request in
            let requestURL = try #require(request.url?.absoluteString)
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!

            switch requestURL {
            case "https://api.g.alchemy.com/data/v1/alchemy-key/assets/tokens/balances/by-address":
                return (
                    response,
                    Data(
                        """
                        {
                          "data": {
                            "tokens": [
                              {
                                "address": "0x1234567890abcdef1234567890abcdef12345678",
                                "network": "base-mainnet",
                                "tokenAddress": "0x2222222222222222222222222222222222222222",
                                "tokenBalance": "1"
                              }
                            ]
                          }
                        }
                        """.utf8
                    )
                )
            case "https://api.g.alchemy.com/data/v1/alchemy-key/assets/tokens/by-address":
                return (
                    response,
                    Data(
                        """
                        {
                          "data": {
                            "tokens": [
                              {
                                "address": "0x1234567890abcdef1234567890abcdef12345678",
                                "network": "base-mainnet",
                                "tokenAddress": "0x2222222222222222222222222222222222222222",
                                "tokenBalance": "1",
                                "tokenMetadata": {
                                  "decimals": 18,
                                  "name": "Tiny Token",
                                  "symbol": "TINY"
                                },
                                "error": null
                              }
                            ]
                          }
                        }
                        """.utf8
                    )
                )
            default:
                Issue.record("Unexpected URL: \(requestURL)")
                return (response, Data())
            }
        }
        defer {
            ProviderMockURLProtocol.handler = nil
        }

        let result = try await provider.tokenHoldings(
            for: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .baseMainnet
        )
        let holdings = result.holdings

        #expect(holdings.count == 1)
        #expect(holdings[0].amountDisplay == "<0.000001 TINY")
    }

    @Test("token holdings provider retries transient balance endpoint timeouts before succeeding")
    @MainActor
    func tokenHoldingsProviderRetriesTransientTimeouts() async throws {
        let session = makeMockSession()
        let provider = AlchemyTokenHoldingsProvider(
            configurationResolver: LiveProviderConfigurationResolver { provider in
                provider == .alchemy ? "alchemy-key" : nil
            },
            session: session,
            maxRetryCount: 3,
            baseDelayNanoseconds: 0,
            maxDelayNanoseconds: 0
        )
        let balanceAttempts = ArrayRecorder<Int>()

        ProviderMockURLProtocol.handler = { request in
            let requestURL = try #require(request.url?.absoluteString)
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!

            switch requestURL {
            case "https://api.g.alchemy.com/data/v1/alchemy-key/assets/tokens/balances/by-address":
                balanceAttempts.append(1)
                if balanceAttempts.values().count < 3 {
                    throw URLError(.timedOut)
                }

                return (
                    response,
                    Data(
                        """
                        {
                          "data": {
                            "tokens": [
                              {
                                "address": "0x1234567890abcdef1234567890abcdef12345678",
                                "network": "base-mainnet",
                                "tokenAddress": "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
                                "tokenBalance": "1000000"
                              }
                            ]
                          }
                        }
                        """.utf8
                    )
                )
            case "https://api.g.alchemy.com/data/v1/alchemy-key/assets/tokens/by-address":
                return (
                    response,
                    Data(
                        """
                        {
                          "data": {
                            "tokens": [
                              {
                                "address": "0x1234567890abcdef1234567890abcdef12345678",
                                "network": "base-mainnet",
                                "tokenAddress": "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
                                "tokenBalance": "1",
                                "tokenMetadata": {
                                  "decimals": 6,
                                  "name": "USD Coin",
                                  "symbol": "USDC"
                                },
                                "error": null
                              }
                            ]
                          }
                        }
                        """.utf8
                    )
                )
            default:
                Issue.record("Unexpected URL: \(requestURL)")
                return (response, Data())
            }
        }
        defer {
            ProviderMockURLProtocol.handler = nil
        }

        let result = try await provider.tokenHoldings(
            for: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .baseMainnet
        )

        #expect(balanceAttempts.values().count == 3)
        #expect(result.holdings.count == 1)
        #expect(result.holdings[0].amountDisplay == "1 USDC")
        #expect(result.warning == nil)
    }

    @Test("native balance provider retries transient RPC timeouts before succeeding")
    @MainActor
    func nativeBalanceProviderRetriesTransientTimeouts() async throws {
        let session = makeMockSession()
        let provider = AlchemyRPCProvider(
            configurationResolver: LiveProviderConfigurationResolver { provider in
                provider == .alchemy ? "alchemy-key" : nil
            },
            session: session,
            maxRetryCount: 3,
            baseDelayNanoseconds: 0,
            maxDelayNanoseconds: 0
        )
        let requestCount = ArrayRecorder<Int>()

        ProviderMockURLProtocol.handler = { request in
            let requestURL = try #require(request.url?.absoluteString)
            #expect(requestURL == "https://eth-mainnet.g.alchemy.com/v2/alchemy-key")
            requestCount.append(1)
            let attempt = requestCount.values().count

            if attempt < 3 {
                throw URLError(.timedOut)
            }

            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (
                response,
                Data(
                    """
                    {
                      "jsonrpc": "2.0",
                      "id": 1,
                      "result": "0x14d1120d7b160000"
                    }
                    """.utf8
                )
            )
        }
        defer {
            ProviderMockURLProtocol.handler = nil
        }

        let balance = try await provider.nativeBalance(
            for: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .ethMainnet
        )

        #expect(requestCount.values().count == 3)
        #expect(balance.formattedEtherDisplay == "1.5 ETH")
    }

    @Test("native balance provider maps JSON-RPC method errors from HTTP 200 envelopes")
    @MainActor
    func nativeBalanceProviderMapsRPCErrorEnvelope() async {
        let session = makeMockSession()
        let provider = AlchemyRPCProvider(
            configurationResolver: LiveProviderConfigurationResolver { provider in
                provider == .alchemy ? "alchemy-key" : nil
            },
            session: session,
            maxRetryCount: 1
        )

        ProviderMockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (
                response,
                Data(
                    """
                    {
                      "jsonrpc": "2.0",
                      "id": 1,
                      "error": {
                        "code": -32601,
                        "message": "Method not found"
                      }
                    }
                    """.utf8
                )
            )
        }
        defer {
            ProviderMockURLProtocol.handler = nil
        }

        do {
            _ = try await provider.nativeBalance(
                for: "0x1234567890abcdef1234567890abcdef12345678",
                chain: .ethMainnet
            )
            Issue.record("Expected JSON-RPC error envelope to throw.")
        } catch let error as ProviderAbstractionError {
            #expect(error == .unsupportedMethod)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("native balance provider preserves HTTP status and API message for non-retryable failures")
    @MainActor
    func nativeBalanceProviderPreservesHTTPFailureContext() async {
        let session = makeMockSession()
        let provider = AlchemyRPCProvider(
            configurationResolver: LiveProviderConfigurationResolver { provider in
                provider == .alchemy ? "alchemy-key" : nil
            },
            session: session,
            maxRetryCount: 1
        )

        ProviderMockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 400,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (
                response,
                Data(#"{"message":"wallet scope mismatch"}"#.utf8)
            )
        }
        defer {
            ProviderMockURLProtocol.handler = nil
        }

        do {
            _ = try await provider.nativeBalance(
                for: "0x1234567890abcdef1234567890abcdef12345678",
                chain: .ethMainnet
            )
            Issue.record("Expected native balance HTTP failure to throw.")
        } catch let error as ProviderAbstractionError {
            #expect(error == .badStatus(400, message: #"{"message":"wallet scope mismatch"}"#))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("gas pricing provider maps JSON-RPC rate limits from HTTP 200 envelopes")
    @MainActor
    func gasPricingProviderMapsRPCErrorEnvelope() async {
        let session = makeMockSession()
        let provider = AlchemyGasPricingProvider(
            configurationResolver: LiveProviderConfigurationResolver { provider in
                provider == .alchemy ? "alchemy-key" : nil
            },
            session: session
        )

        ProviderMockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (
                response,
                Data(
                    """
                    {
                      "jsonrpc": "2.0",
                      "id": 1,
                      "error": {
                        "code": 429,
                        "message": "rate limit exceeded"
                      }
                    }
                    """.utf8
                )
            )
        }
        defer {
            ProviderMockURLProtocol.handler = nil
        }

        do {
            _ = try await provider.gasPriceEstimate(for: .ethMainnet)
            Issue.record("Expected JSON-RPC rate limit envelope to throw.")
        } catch let error as AlchemyGasPricingProvider.GasPricingError {
            switch error {
            case .rateLimited(let message, _):
                #expect(message == "rate limit exceeded")
            default:
                Issue.record("Unexpected gas pricing error: \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("gas pricing provider maps HTTP unauthorized responses to an auth-specific error")
    @MainActor
    func gasPricingProviderMapsUnauthorizedHTTPFailures() async {
        let session = makeMockSession()
        let provider = AlchemyGasPricingProvider(
            configurationResolver: LiveProviderConfigurationResolver { provider in
                provider == .alchemy ? "alchemy-key" : nil
            },
            session: session
        )

        ProviderMockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 401,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (
                response,
                Data(#"{"message":"invalid api key"}"#.utf8)
            )
        }
        defer {
            ProviderMockURLProtocol.handler = nil
        }

        do {
            _ = try await provider.gasPriceEstimate(for: .ethMainnet)
            Issue.record("Expected unauthorized gas pricing response to throw.")
        } catch let error as AlchemyGasPricingProvider.GasPricingError {
            switch error {
            case .unauthorized(let message):
                #expect(message == "invalid api key")
            default:
                Issue.record("Unexpected gas pricing error: \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("NFT fetcher uses the injected inventory provider factory instead of constructing Alchemy inline")
    @MainActor
    func nftFetcherUsesInjectedInventoryProvider() async throws {
        let provider = StubNFTInventoryProvider()
        let fetcher = NFTFetcher(
            nftProviderFactory: { chain in
                #expect(chain == .ethMainnet)
                return provider
            }
        )

        let response = try await fetcher.fetchAllNFTs(
            for: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .ethMainnet,
            correlationID: "provider-test",
            eventRecorder: NoOpNFTRefreshEventRecorder()
        )

        #expect(await provider.receivedOwners() == ["0x1234567890abcdef1234567890abcdef12345678"])
        #expect(response.isEmpty)
        #expect(fetcher.total == 0)
        #expect(fetcher.itemsLoaded == 0)
    }

    @Test("retry exhaustion throws and records failure instead of success")
    @MainActor
    func retryExhaustionThrowsAndSkipsSuccessReceipt() async {
        let provider = ExhaustingPaginationNFTInventoryProvider()
        let recorder = SpyNFTRefreshEventRecorder()
        let fetcher = NFTFetcher(
            maxRetryCount: 1,
            baseDelayNanoseconds: 0,
            maxDelayNanoseconds: 0,
            nftProviderFactory: { _ in provider }
        )

        do {
            _ = try await fetcher.fetchAllNFTs(
                for: "0x1234567890abcdef1234567890abcdef12345678",
                chain: .ethMainnet,
                correlationID: "retry-exhausted",
                eventRecorder: recorder
            )
            Issue.record("Expected retry exhaustion to throw.")
        } catch let error as NFTFetcher.FetcherError {
            switch error {
            case .retryExhausted:
                break
            default:
                Issue.record("Expected retryExhausted, got \(error)")
            }
        } catch {
            Issue.record("Expected NFTFetcher.FetcherError, got \(error)")
        }

        let failedCount = recorder.fetchFailedCount()
        let succeededCount = recorder.fetchSucceededCount()
        #expect(failedCount == 1)
        #expect(succeededCount == 0)
    }

    @Test("large successful paginated collections do not exhaust retry budget just because they span many pages")
    @MainActor
    func largeSuccessfulPaginationDoesNotExhaust() async throws {
        let provider = ManyPageNFTInventoryProvider(pageCount: 40, itemsPerPage: 1)
        let fetcher = NFTFetcher(
            maxRetryCount: 1,
            baseDelayNanoseconds: 0,
            maxDelayNanoseconds: 0,
            nftProviderFactory: { _ in provider }
        )

        let response = try await fetcher.fetchAllNFTs(
            for: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .ethMainnet,
            correlationID: "many-pages",
            eventRecorder: NoOpNFTRefreshEventRecorder()
        )

        #expect(response.count == 40)
        let requestedPageKeys = await provider.requestedPageKeys()
        #expect(requestedPageKeys.count == 40)
        #expect(fetcher.error == nil)
    }

    @Test("later-page failures throw instead of returning a partial collection")
    @MainActor
    func partialPaginationThrowsInsteadOfReturningPartialCollection() async {
        let provider = PartiallyFailingNFTInventoryProvider(successfulPageCount: 3, itemsPerPage: 2)
        let recorder = SpyNFTRefreshEventRecorder()
        let fetcher = NFTFetcher(
            maxRetryCount: 1,
            baseDelayNanoseconds: 0,
            maxDelayNanoseconds: 0,
            nftProviderFactory: { _ in provider }
        )

        do {
            _ = try await fetcher.fetchAllNFTs(
                for: "0x1234567890abcdef1234567890abcdef12345678",
                chain: .ethMainnet,
                correlationID: "partial-pages",
                eventRecorder: recorder
            )
            Issue.record("Expected later-page failure to throw.")
        } catch {}

        #expect(fetcher.error != nil)
        let partialFailureCount = recorder.fetchFailedCount()
        let partialSuccessCount = recorder.fetchSucceededCount()
        #expect(partialFailureCount == 1)
        #expect(partialSuccessCount == 0)
    }

    @Test("NFT fetcher honors provider Retry-After delays when rate limited")
    @MainActor
    func nftFetcherHonorsProviderRetryAfterDelay() async {
        let provider = RetryLimitedNFTInventoryProvider()
        let fetcher = NFTFetcher(
            maxRetryCount: 2,
            baseDelayNanoseconds: 0,
            maxDelayNanoseconds: 2_000_000_000,
            nftProviderFactory: { _ in provider }
        )

        let start = ContinuousClock.now

        do {
            _ = try await fetcher.fetchAllNFTs(
                for: "0x1234567890abcdef1234567890abcdef12345678",
                chain: .ethMainnet,
                correlationID: "retry-after",
                eventRecorder: NoOpNFTRefreshEventRecorder()
            )
            Issue.record("Expected rate-limited refresh to throw.")
        } catch let error as AlchemyNFTService.APIError {
            switch error {
            case .rateLimited(let retryAfter, _):
                #expect(retryAfter == 0.2)
            default:
                Issue.record("Expected rateLimited error, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        let elapsed = start.duration(to: .now)
        #expect(elapsed >= .milliseconds(180))
        #expect(await provider.requestCount() == 2)
    }
}

private final class StubNFTInventoryProvider: NFTInventoryProviding, @unchecked Sendable {
    // Safety invariant: mutation and reads flow through the nested actor state only.
    private let state = State()

    private actor State {
        var owners: [String] = []

        func record(owner: String) {
            owners.append(owner)
        }

        func snapshot() -> [String] {
            owners
        }
    }

    func nftsForOwner(
        owner: String,
        pageKey: String?
    ) async throws -> AlchemyNFTResponse {
        await state.record(owner: owner)
        return AlchemyNFTResponse(
            ownedNfts: [],
            totalCount: 0,
            pageKey: nil,
            validAt: .init(
                blockNumber: 1,
                blockHash: "0xabc",
                blockTimestamp: "2025-01-01T00:00:00Z"
            )
        )
    }

    func receivedOwners() async -> [String] {
        await state.snapshot()
    }
}

// Helper names in this section prioritize test intent over SwiftLint's length heuristic.
private final class RetryLimitedNFTInventoryProvider: NFTInventoryProviding, @unchecked Sendable {
    private let state = State()

    func nftsForOwner(owner: String, pageKey: String?) async throws -> AlchemyNFTResponse {
        await state.recordRequest()
        throw AlchemyNFTService.APIError.rateLimited(retryAfter: 0.2, message: "slow down")
    }

    func requestCount() async -> Int {
        await state.requestCount
    }

    actor State {
        private(set) var requestCount = 0

        func recordRequest() {
            requestCount += 1
        }
    }
}

private final class ExhaustingPaginationNFTInventoryProvider: NFTInventoryProviding {
    func nftsForOwner(
        owner: String,
        pageKey: String?
    ) async throws -> AlchemyNFTResponse {
        AlchemyNFTResponse(
            ownedNfts: [],
            totalCount: 1,
            pageKey: "next-page",
            validAt: .init(
                blockNumber: 1,
                blockHash: "0xabc",
                blockTimestamp: "2025-01-01T00:00:00Z"
            )
        )
    }
}

private final class ManyPageNFTInventoryProvider: NFTInventoryProviding, @unchecked Sendable {
    let pageCount: Int
    let itemsPerPage: Int
    // Safety invariant: mutation and reads flow through the nested actor state only.
    private let state = State()

    private actor State {
        var pageKeys: [String?] = []

        func record(pageKey: String?) {
            pageKeys.append(pageKey)
        }

        func snapshot() -> [String?] {
            pageKeys
        }
    }

    init(pageCount: Int, itemsPerPage: Int) {
        self.pageCount = pageCount
        self.itemsPerPage = itemsPerPage
    }

    func nftsForOwner(
        owner: String,
        pageKey: String?
    ) async throws -> AlchemyNFTResponse {
        await state.record(pageKey: pageKey)

        let pageIndex = pageKey.flatMap { Int($0, radix: 10) } ?? 0
        let nextPageKey = pageIndex + 1 < pageCount ? String(pageIndex + 1) : nil
        let ownedNfts = (0..<itemsPerPage).map { itemOffset in
            let tokenNumber = pageIndex * itemsPerPage + itemOffset
            return NFT(
                id: "temp-\(tokenNumber)",
                contract: NFT.Contract(address: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
                tokenId: String(tokenNumber),
                name: "NFT \(tokenNumber)",
                raw: nil,
                collection: NFT.Collection(
                    name: "Paged Collection",
                    chain: .ethMainnet,
                    contractAddress: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
                ),
                tokenUri: "ipfs://\(tokenNumber)",
                network: .ethMainnet,
                accountAddress: owner
            )
        }

        return AlchemyNFTResponse(
            ownedNfts: ownedNfts,
            totalCount: pageCount * itemsPerPage,
            pageKey: nextPageKey,
            validAt: .init(
                blockNumber: pageIndex + 1,
                blockHash: "0xabc\(pageIndex)",
                blockTimestamp: "2025-01-01T00:00:00Z"
            )
        )
    }

    func requestedPageKeys() async -> [String?] {
        await state.snapshot()
    }
}

private final class PartiallyFailingNFTInventoryProvider: NFTInventoryProviding {
    let successfulPageCount: Int
    let itemsPerPage: Int

    init(successfulPageCount: Int, itemsPerPage: Int) {
        self.successfulPageCount = successfulPageCount
        self.itemsPerPage = itemsPerPage
    }

    func nftsForOwner(
        owner: String,
        pageKey: String?
    ) async throws -> AlchemyNFTResponse {
        let pageIndex = pageKey.flatMap { Int($0, radix: 10) } ?? 0

        if pageIndex >= successfulPageCount {
            throw URLError(.badServerResponse)
        }

        let nextPageKey = pageIndex + 1 <= successfulPageCount ? String(pageIndex + 1) : nil
        let ownedNfts = (0..<itemsPerPage).map { itemOffset in
            let tokenNumber = pageIndex * itemsPerPage + itemOffset
            return NFT(
                id: "partial-\(tokenNumber)",
                contract: NFT.Contract(address: "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"),
                tokenId: String(tokenNumber),
                name: "Partial \(tokenNumber)",
                raw: nil,
                collection: NFT.Collection(
                    name: "Partial Collection",
                    chain: .ethMainnet,
                    contractAddress: "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
                ),
                tokenUri: "ipfs://partial-\(tokenNumber)",
                network: .ethMainnet,
                accountAddress: owner
            )
        }

        return AlchemyNFTResponse(
            ownedNfts: ownedNfts,
            totalCount: (successfulPageCount + 1) * itemsPerPage,
            pageKey: nextPageKey,
            validAt: .init(
                blockNumber: pageIndex + 1,
                blockHash: "0xdef\(pageIndex)",
                blockTimestamp: "2025-01-01T00:00:00Z"
            )
        )
    }
}

private extension ProviderAbstractionTests {
    @MainActor
    func makeMockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProviderMockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private extension URLRequest {
    var bodyData: Data? {
        if let httpBody {
            return httpBody
        }

        guard let stream = httpBodyStream else {
            return nil
        }

        stream.open()
        defer { stream.close() }

        let bufferSize = 1024
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let readCount = stream.read(buffer, maxLength: bufferSize)
            if readCount < 0 {
                return nil
            }
            if readCount == 0 {
                break
            }
            data.append(buffer, count: readCount)
        }

        return data.isEmpty ? nil : data
    }
}

private struct StubProviderConfigurationResolver: ProviderConfigurationResolving {
    let configuration: ProviderEndpointConfiguration

    func configuration(for chain: Chain) throws -> ProviderEndpointConfiguration {
        configuration
    }
}

private struct ThrowingProviderConfigurationResolver: ProviderConfigurationResolving {
    let error: ProviderAbstractionError

    func configuration(for chain: Chain) throws -> ProviderEndpointConfiguration {
        throw error
    }
}

// URLProtocol requires these overridden type methods even on a final class.
private final class ProviderMockURLProtocol: URLProtocol {
    typealias Handler = (URLRequest) throws -> (URLResponse, Data)

    // Safety invariant: tests install and clear the handler around a single request flow.
    nonisolated(unsafe) static var handler: Handler?

    override static func canInit(with request: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@MainActor
private final class SpyNFTRefreshEventRecorder: NFTRefreshEventRecording {
    private var succeededCount = 0
    private var failedCount = 0

    func recordRefreshStarted(accountAddress: String, chain: Chain, correlationID: String) async {}
    func recordFetchSucceeded(accountAddress: String, chain: Chain, correlationID: String, itemCount: Int, totalCount: Int?) async {
        succeededCount += 1
    }
    func recordFetchFailed(accountAddress: String, chain: Chain, correlationID: String, failure: NFTProviderFailure) async {
        failedCount += 1
    }
    func recordPersistenceCompleted(accountAddress: String, chain: Chain, correlationID: String, persistedCount: Int) async {}
    func recordPersistenceFailed(accountAddress: String, chain: Chain, correlationID: String, error: Error) async {}

    func fetchSucceededCount() -> Int {
        succeededCount
    }

    func fetchFailedCount() -> Int {
        failedCount
    }
}

private final class ArrayRecorder<Element: Sendable>: @unchecked Sendable {
    private var storage: [Element] = []
    private let lock = NSLock()

    func append(_ element: Element) {
        lock.lock()
        storage.append(element)
        lock.unlock()
    }

    func values() -> [Element] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
