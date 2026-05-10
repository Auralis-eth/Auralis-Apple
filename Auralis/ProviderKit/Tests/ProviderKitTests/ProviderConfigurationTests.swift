import AuralisPrimaryModels
import Foundation
import ProviderKit
import Testing

@Suite
struct ProviderConfigurationTests {
    @Test("Live resolver builds Alchemy endpoints for supported EVM chains")
    func resolverBuildsEndpoints() throws {
        let resolver = LiveProviderConfigurationResolver { provider in
            provider == .alchemy ? "test-key" : nil
        }

        let configuration = try resolver.configuration(for: .baseMainnet)

        #expect(configuration.alchemyNFTBaseURL?.absoluteString == "https://base-mainnet.g.alchemy.com/nft/v3/test-key")
        #expect(configuration.alchemyDataAPIBaseURL?.absoluteString == "https://api.g.alchemy.com/data/v1/test-key")
        #expect(configuration.alchemyRPCURL?.absoluteString == "https://base-mainnet.g.alchemy.com/v2/test-key")
    }

    @Test("Live resolver omits RPC endpoints for Solana chains")
    func resolverOmitsSolanaRPC() throws {
        let resolver = LiveProviderConfigurationResolver { _ in "test-key" }

        let configuration = try resolver.configuration(for: .solanaMainnet)

        #expect(configuration.alchemyRPCURL == nil)
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
}
