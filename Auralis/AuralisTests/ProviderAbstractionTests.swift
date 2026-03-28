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

    @Test("retry exhaustion throws and records failure instead of success")
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

        #expect(recorder.fetchFailedCount == 1)
        #expect(recorder.fetchSucceededCount == 0)
    }

    @Test("large successful paginated collections do not exhaust retry budget just because they span many pages")
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
        #expect(provider.requestedPageKeys.count == 40)
        #expect(fetcher.error == nil)
    }

    @Test("partial paginated success is returned when a later page fails after items were already fetched")
    func partialPaginationReturnsFetchedItemsBeforeFailure() async throws {
        let provider = PartiallyFailingNFTInventoryProvider(successfulPageCount: 3, itemsPerPage: 2)
        let recorder = SpyNFTRefreshEventRecorder()
        let fetcher = NFTFetcher(
            maxRetryCount: 1,
            baseDelayNanoseconds: 0,
            maxDelayNanoseconds: 0,
            nftProviderFactory: { _ in provider }
        )

        let response = try await fetcher.fetchAllNFTs(
            for: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .ethMainnet,
            correlationID: "partial-pages",
            eventRecorder: recorder
        )

        #expect(response.count == 6)
        #expect(fetcher.error != nil)
        #expect(recorder.fetchFailedCount == 1)
        #expect(recorder.fetchSucceededCount == 0)
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

private final class ManyPageNFTInventoryProvider: NFTInventoryProviding {
    let pageCount: Int
    let itemsPerPage: Int
    private(set) var requestedPageKeys: [String?] = []

    init(pageCount: Int, itemsPerPage: Int) {
        self.pageCount = pageCount
        self.itemsPerPage = itemsPerPage
    }

    func nftsForOwner(
        owner: String,
        pageKey: String?
    ) async throws -> AlchemyNFTResponse {
        requestedPageKeys.append(pageKey)

        let pageIndex = pageKey.flatMap(Int.init) ?? 0
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
        let pageIndex = pageKey.flatMap(Int.init) ?? 0

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

private final class SpyNFTRefreshEventRecorder: NFTRefreshEventRecording {
    private(set) var fetchSucceededCount = 0
    private(set) var fetchFailedCount = 0

    func recordRefreshStarted(accountAddress: String, chain: Chain, correlationID: String) async {}
    func recordFetchSucceeded(accountAddress: String, chain: Chain, correlationID: String, itemCount: Int, totalCount: Int?) async {
        fetchSucceededCount += 1
    }
    func recordFetchFailed(accountAddress: String, chain: Chain, correlationID: String, error: Error) async {
        fetchFailedCount += 1
    }
    func recordPersistenceCompleted(accountAddress: String, chain: Chain, correlationID: String, persistedCount: Int) async {}
    func recordPersistenceFailed(accountAddress: String, chain: Chain, correlationID: String, error: Error) async {}
}
