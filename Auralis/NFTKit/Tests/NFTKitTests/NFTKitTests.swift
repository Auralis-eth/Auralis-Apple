import AuralisTestSupport
import AuralisPrimaryModels
import AuralisPrimaryPersistence
import Foundation
import NFTDomain
import NFTKit
import Testing

struct NFTKitTests {
    @Test("refresh scope normalizes account input and rejects empty scopes")
    func refreshScopeNormalizesAccountInput() throws {
        let scope = try #require(
            NFTRefreshScope(
                accountAddress: " 0xABCDEFabcdefABCDEFabcdefABCDEFabcdefABCD ",
                chain: .baseMainnet
            )
        )

        #expect(scope.accountAddress == "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd")
        #expect(scope.chain == .baseMainnet)
        #expect(NFTRefreshScope(accountAddress: "   ", chain: .ethMainnet) == nil)
    }

    @Test("refresh state computes fresh and stale TTL boundaries deterministically")
    func refreshStateComputesFreshnessBoundaries() {
        let computer = NFTRefreshStateComputer(refreshTTL: 60)
        let account = "0x1234567890abcdef1234567890abcdef12345678"
        let refreshedAt = Date(timeIntervalSince1970: 1_704_067_200)

        computer.markRefreshSucceeded(for: account, chain: .ethMainnet, at: refreshedAt)

        #expect(computer.isFresh(for: account, chain: .ethMainnet, referenceDate: refreshedAt.addingTimeInterval(60)))
        #expect(computer.isStale(for: account, chain: .ethMainnet, referenceDate: refreshedAt.addingTimeInterval(61)))
        #expect(computer.lastSuccessfulRefreshAt(for: account, chain: .ethMainnet) == refreshedAt)
    }

    @Test("metadata updater applies canonical media URLs and preserves secure image URL")
    func metadataUpdaterAppliesMediaPatch() throws {
        let nft = NFTFixture(
            tokenId: "1",
            accountAddress: Fixture.Accounts.primary,
            contractAddress: Fixture.contract("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
            collectionName: "Original Collection",
            network: .baseMainnet,
            name: "Original",
            nftDescription: "Original description",
            imageOriginalUrl: "https://example.com/original.png"
        ).build()

        NFTMetadataUpdater.updateNFTFromMetadata(
            nft: nft,
            metadata: [
                "name": .string("Updated Token"),
                "description": .string("Updated description"),
                "collection": .object(["name": .string("Updated Collection")]),
                "image": .string("ipfs://new-image"),
                "animation_url": .string("https://example.com/animation.mp4"),
                "audio_url": .string("https://example.com/audio.mp3"),
            ]
        )

        let image = try #require(nft.image)
        #expect(nft.name == "Updated Token")
        #expect(nft.nftDescription == "Updated description")
        #expect(nft.collectionName == "Updated Collection")
        #expect(image.originalUrl == "https://gateway.pinata.cloud/ipfs/new-image")
        #expect(image.secureUrl == "https://gateway.pinata.cloud/ipfs/new-image")
        #expect(nft.animationUrl == "https://example.com/animation.mp4")
        #expect(nft.audioUrl == "https://example.com/audio.mp3")
    }

    @Test("live fetch inventory use case forwards scope, correlation, recorder, and progress")
    func liveFetchInventoryUseCaseForwardsFetcherResult() async throws {
        let snapshot = NFTInventoryItemSnapshot(
            id: "snapshot-1",
            contract: .init(address: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", chain: .baseMainnet),
            tokenId: "1",
            tokenType: "ERC721",
            name: "Snapshot",
            nftDescription: nil,
            image: nil,
            raw: nil,
            collection: nil,
            tokenURI: nil,
            timeLastUpdated: nil,
            acquiredAt: nil,
            network: .baseMainnet
        )
        let fetcher = RecordingNFTFetcher(result: .init(
            nfts: [snapshot],
            didCompleteFullRefresh: true,
            totalCount: 1
        ))
        let recorder = NoOpNFTRefreshEventRecorder()
        let useCase = LiveFetchNFTInventoryUseCase(nftFetcher: fetcher)

        let inventory = try await useCase.fetchInventory(
            for: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .baseMainnet,
            correlationID: "fetch-1",
            eventRecorder: recorder,
            progressHandler: { _ in }
        )

        #expect(inventory.nfts.map(\.id) == ["snapshot-1"])
        #expect(inventory.didCompleteFullRefresh)
        #expect(await fetcher.calls == [
            RecordingNFTFetcher.Call(
                account: "0x1234567890abcdef1234567890abcdef12345678",
                chain: .baseMainnet,
                correlationID: "fetch-1"
            )
        ])
    }

}

private actor RecordingNFTFetcher: NFTFetching {
    struct Call: Equatable {
        let account: String
        let chain: Chain
        let correlationID: String?
    }

    private(set) var calls: [Call] = []
    private let result: NFTFetchInventoryResult

    init(result: NFTFetchInventoryResult) {
        self.result = result
    }

    func fetchAllNFTs(
        for account: String,
        chain: Chain,
        correlationID: String?,
        eventRecorder: any NFTRefreshEventRecording,
        progressHandler: NFTFetchProgressHandler?
    ) async throws -> NFTFetchInventoryResult {
        calls.append(Call(account: account, chain: chain, correlationID: correlationID))
        await progressHandler?(NFTFetchProgress(itemsLoaded: result.nfts.count, total: result.totalCount, currentCursor: nil))
        return result
    }
}

private struct NoOpNFTRefreshEventRecorder: NFTRefreshEventRecording {
    func recordRefreshStarted(accountAddress: String, chain: Chain, correlationID: String) async {}
    func recordFetchSucceeded(accountAddress: String, chain: Chain, correlationID: String, itemCount: Int, totalCount: Int?) async {}
    func recordFetchFailed(accountAddress: String, chain: Chain, correlationID: String, failure: NFTProviderFailure) async {}
    func recordPersistenceCompleted(accountAddress: String, chain: Chain, correlationID: String, persistedCount: Int) async {}
    func recordPersistenceFailed(accountAddress: String, chain: Chain, correlationID: String, error: Error) async {}
}
