import AuralisPrimaryModels
import AuralisTestSupport
import Foundation
import Testing
@testable import ProviderKit

struct ProviderConfigurationTests {
    @Test(
        "Live resolver keeps public Alchemy client keys in expected URL paths",
        arguments: [
            "development-public-client-key",
            "production-public-client-key",
        ]
    )
    func resolverKeepsPublicAlchemyClientKeysInURLPaths(alchemyKey: String) throws {
        let resolver = LiveProviderConfigurationResolver { provider in
            provider == .alchemy ? alchemyKey : nil
        }

        let configuration = try resolver.configuration(for: .baseMainnet)

        #expect(try #require(configuration.alchemyNFTBaseURL).absoluteString == "https://base-mainnet.g.alchemy.com/nft/v3/\(alchemyKey)")
        #expect(try #require(configuration.alchemyDataAPIBaseURL).absoluteString == "https://api.g.alchemy.com/data/v1/\(alchemyKey)")
        #expect(try #require(configuration.alchemyRPCURL).absoluteString == "https://base-mainnet.g.alchemy.com/v2/\(alchemyKey)")
    }

    @Test("Live resolver omits Alchemy endpoints when the public client key is unavailable")
    func resolverOmitsAlchemyEndpointsWithoutClientKey() throws {
        let resolver = LiveProviderConfigurationResolver { _ in nil }

        let configuration = try resolver.configuration(for: .baseMainnet)

        #expect(configuration.alchemyNFTBaseURL == nil)
        #expect(configuration.alchemyDataAPIBaseURL == nil)
        #expect(configuration.alchemyRPCURL == nil)
    }

    @Test("Live resolver omits RPC endpoints for Solana chains and exposes Helius DAS")
    func resolverOmitsSolanaRPCAndExposesHeliusDAS() throws {
        let resolver = LiveProviderConfigurationResolver { provider in
            switch provider {
            case .alchemy:
                return "alchemy-test-key"
            case .helius:
                return "helius-test-key"
            }
        }

        let configuration = try resolver.configuration(for: .solanaMainnet)

        #expect(configuration.alchemyRPCURL == nil)
        #expect(configuration.heliusDASBaseURL?.absoluteString == "https://mainnet.helius-rpc.com/")
    }

    @Test("Live resolver omits Helius DAS when the Helius key is unavailable")
    func resolverOmitsHeliusDASWithoutKey() throws {
        let resolver = LiveProviderConfigurationResolver { provider in
            provider == .alchemy ? "alchemy-test-key" : nil
        }

        let configuration = try resolver.configuration(for: .solanaMainnet)

        #expect(configuration.heliusDASBaseURL == nil)
    }

    @Test("Native balance provider maps missing RPC endpoint to missing API key")
    func nativeBalanceProviderMapsMissingRPCURL() async throws {
        let resolver = StubProviderConfigurationResolver(
            configuration: ProviderEndpointConfiguration(
                chain: .baseMainnet,
                alchemyNFTBaseURL: nil,
                alchemyDataAPIBaseURL: nil,
                alchemyRPCURL: nil
            )
        )
        let provider = AlchemyRPCProvider(configurationResolver: resolver)

        await #expect(throws: ProviderAbstractionError.missingAPIKey(.alchemy)) {
            try await provider.nativeBalance(
                for: "0x0000000000000000000000000000000000000001",
                chain: .baseMainnet
            )
        }
    }

    @Test("Native balance provider forwards invalid endpoint configuration")
    func nativeBalanceProviderForwardsInvalidEndpointConfiguration() async throws {
        let provider = AlchemyRPCProvider(
            configurationResolver: ThrowingProviderConfigurationResolver(error: .invalidURL)
        )

        await #expect(throws: ProviderAbstractionError.invalidURL) {
            try await provider.nativeBalance(
                for: "0x0000000000000000000000000000000000000001",
                chain: .baseMainnet
            )
        }
    }

    @Test("Retry-After parser accepts numeric seconds")
    func retryAfterNumericSeconds() {
        #expect(RetryAfterSupport.parse("2.5") == 2.5)
    }

    @Test("Retry-After parser accepts HTTP dates")
    func retryAfterHTTPDate() throws {
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

    @Test("RPC envelope decodes success payloads")
    func rpcEnvelopeDecodesSuccessPayload() throws {
        let data = try #require(#"{"jsonrpc":"2.0","id":1,"result":"0xde0b6b3a7640000"}"#.data(using: .utf8))

        let envelope = try JSONDecoder().decode(AlchemyRPCProvider.RPCEnvelope<String>.self, from: data)

        #expect(envelope.result == "0xde0b6b3a7640000")
        #expect(envelope.error == nil)
    }

    @Test(
        "RPC envelope decodes error payloads",
        arguments: [
            RPCErrorMappingCase(
                payload: #"{"jsonrpc":"2.0","id":1,"error":{"code":429,"message":"rate limit exceeded"}}"#,
                expectedCode: 429,
                expectedMessage: "rate limit exceeded",
                expectedError: .rateLimited
            ),
            RPCErrorMappingCase(
                payload: #"{"jsonrpc":"2.0","id":1,"error":{"code":-32000,"message":"API key unauthorized"}}"#,
                expectedCode: -32000,
                expectedMessage: "API key unauthorized",
                expectedError: .unauthorized
            ),
            RPCErrorMappingCase(
                payload: #"{"jsonrpc":"2.0","id":1,"error":{"code":-32601,"message":"method not found"}}"#,
                expectedCode: -32601,
                expectedMessage: "method not found",
                expectedError: .unsupportedMethod
            ),
            RPCErrorMappingCase(
                payload: #"{"jsonrpc":"2.0","id":1,"error":{"code":-32003,"message":"upstream failed"}}"#,
                expectedCode: -32003,
                expectedMessage: "upstream failed",
                expectedError: .providerError("provider_error_payload_redacted reason=unclassified_message sha256=fbf483cb811705e59268dac16b4706991c0c5625a8c0d8531da68931331f2289")
            ),
        ]
    )
    func rpcErrorPayloadsDecodeForProviderMapping(mappingCase: RPCErrorMappingCase) throws {
        let data = try #require(mappingCase.payload.data(using: .utf8))

        let envelope = try JSONDecoder().decode(AlchemyRPCProvider.RPCEnvelope<String>.self, from: data)
        let error = try #require(envelope.error)

        #expect(error.code == mappingCase.expectedCode)
        #expect(error.message == mappingCase.expectedMessage)
    }

    @Test("Native balance maps RPC error responses to provider errors")
    func nativeBalanceMapsRPCErrorResponses() async throws {
        let mappingCases = [
            RPCErrorMappingCase(
                payload: #"{"jsonrpc":"2.0","id":1,"error":{"code":429,"message":"rate limit exceeded"}}"#,
                expectedCode: 429,
                expectedMessage: "rate limit exceeded",
                expectedError: .rateLimited
            ),
            RPCErrorMappingCase(
                payload: #"{"jsonrpc":"2.0","id":1,"error":{"code":-32000,"message":"API key unauthorized"}}"#,
                expectedCode: -32000,
                expectedMessage: "API key unauthorized",
                expectedError: .unauthorized
            ),
            RPCErrorMappingCase(
                payload: #"{"jsonrpc":"2.0","id":1,"error":{"code":-32601,"message":"method not found"}}"#,
                expectedCode: -32601,
                expectedMessage: "method not found",
                expectedError: .unsupportedMethod
            ),
            RPCErrorMappingCase(
                payload: #"{"jsonrpc":"2.0","id":1,"error":{"code":-32003,"message":"upstream failed"}}"#,
                expectedCode: -32003,
                expectedMessage: "upstream failed",
                expectedError: .providerError("provider_error_payload_redacted reason=unclassified_message sha256=fbf483cb811705e59268dac16b4706991c0c5625a8c0d8531da68931331f2289")
            ),
        ]

        for mappingCase in mappingCases {
            let data = try #require(mappingCase.payload.data(using: .utf8))
            let session = URLSession.mocked { request in
                let response = HTTPURLResponse(
                    url: try #require(request.url),
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: nil
                )!
                return (response, data)
            }
            let provider = AlchemyRPCProvider(
                configurationResolver: StubProviderConfigurationResolver(
                    configuration: ProviderEndpointConfiguration(
                        chain: .baseMainnet,
                        alchemyNFTBaseURL: nil,
                        alchemyDataAPIBaseURL: nil,
                        alchemyRPCURL: try #require(URL(string: "https://example.com/rpc"))
                    )
                ),
                session: session,
                maxRetryCount: 1
            )

            await #expect(throws: mappingCase.expectedError) {
                try await provider.nativeBalance(
                    for: "0x0000000000000000000000000000000000000001",
                    chain: .baseMainnet
                )
            }
        }
    }

    @Test(
        "Native balance converts hex quantity to decimal string",
        arguments: [
            ("0x0", "0"),
            ("0xde0b6b3a7640000", "1000000000000000000"),
            ("0xffffffffffffffff", "18446744073709551615"),
        ]
    )
    func nativeBalanceHexQuantityConversion(hexQuantity: String, expectedDecimal: String) {
        #expect(AlchemyRPCProvider.decimalString(fromHexQuantity: hexQuantity) == expectedDecimal)
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

struct RPCErrorMappingCase: Sendable {
    let payload: String
    let expectedCode: Int
    let expectedMessage: String
    let expectedError: ProviderAbstractionError
}
