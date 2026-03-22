import Foundation
import Testing
@testable import Auralis

@Suite struct ProviderAbstractionTests {
    @Test("provider configuration resolves centralized Alchemy and Infura endpoints for an EVM chain")
    func resolverBuildsExpectedEndpoints() throws {
        let resolver = LiveProviderConfigurationResolver { provider in
            switch provider {
            case .alchemy:
                return "alchemy-key"
            case .infura:
                return "infura-key"
            default:
                return nil
            }
        }

        let configuration = try resolver.configuration(for: .baseMainnet)

        #expect(configuration.alchemyNFTBaseURL?.absoluteString == "https://base-mainnet.g.alchemy.com/nft/v3/alchemy-key")
        #expect(configuration.alchemyRPCURL?.absoluteString == "https://base-mainnet.g.alchemy.com/v2/alchemy-key")
        #expect(configuration.infuraGasURL?.absoluteString == "https://gas.api.infura.io/v3/infura-key/networks/8453/suggestedGasFees")
    }

    @Test("provider configuration leaves unsupported RPC-backed endpoints empty for Solana")
    func resolverDropsUnsupportedRPCEndpoints() throws {
        let resolver = LiveProviderConfigurationResolver { _ in "shared-key" }

        let configuration = try resolver.configuration(for: .solanaMainnet)

        #expect(configuration.alchemyNFTBaseURL?.absoluteString == "https://solana-mainnet.g.alchemy.com/nft/v3/shared-key")
        #expect(configuration.alchemyRPCURL == nil)
        #expect(configuration.infuraGasURL == nil)
    }

    @Test("NFT fetcher uses the injected inventory provider factory instead of constructing Alchemy inline")
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

        #expect(provider.receivedOwners == ["0x1234567890abcdef1234567890abcdef12345678"])
        #expect(response.isEmpty)
        #expect(fetcher.total == 0)
        #expect(fetcher.itemsLoaded == 0)
    }
}

private final class StubNFTInventoryProvider: NFTInventoryProviding {
    private(set) var receivedOwners: [String] = []

    func nftsForOwner(
        owner: String,
        pageKey: String?
    ) async throws -> AlchemyNFTResponse {
        receivedOwners.append(owner)
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
}
