@testable import Auralis
import Foundation
import SwiftData
import Testing

@Suite
struct NFTServiceReceiptTests {
    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([EOAccount.self, NFT.self, Tag.self, StoredReceipt.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @Test("refresh flow carries one caller-provided correlation ID across service fetch and persistence receipts")
    @MainActor
    func refreshFlowUsesSharedCorrelationID() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let receiptStore = SwiftDataReceiptStore(
            modelContext: context,
            sequenceAllocator: ReceiptSequenceAllocator()
        )
        let recorder = ReceiptBackedNFTRefreshEventRecorder(receiptStore: receiptStore)
        let fetcher = StubNFTFetcher()
        let service = NFTService(
            nftFetcher: fetcher,
            eventRecorderFactory: { _ in recorder }
        )
        let account = EOAccount(address: "0x1234567890abcdef1234567890abcdef12345678")
        let correlationID = "refresh-flow-123"

        await service.refreshNFTs(
            for: account,
            chain: Chain.ethMainnet,
            modelContext: context,
            correlationID: correlationID
        )

        let receipts = try receiptStore.receipts(forCorrelationID: correlationID, limit: 10)

        #expect(fetcher.receivedCorrelationIDs == [correlationID])
        #expect(receipts.map { $0.kind } == [
            "nft.persistence.completed",
            "nft.fetch.succeeded",
            "nft.refresh.started"
        ])
        #expect(receipts.allSatisfy { $0.correlationID == correlationID })
    }

    @Test("freshness keeps the last successful refresh timestamp when a later refresh fails")
    @MainActor
    func refreshFailureKeepsLastSuccessfulTimestamp() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let receiptStore = SwiftDataReceiptStore(
            modelContext: context,
            sequenceAllocator: ReceiptSequenceAllocator()
        )
        let recorder = ReceiptBackedNFTRefreshEventRecorder(receiptStore: receiptStore)
        let fetcher = FlakyNFTFetcher()
        let service = NFTService(
            nftFetcher: fetcher,
            refreshTTL: 300,
            eventRecorderFactory: { _ in recorder }
        )
        let account = EOAccount(address: "0x1234567890abcdef1234567890abcdef12345678")

        await service.refreshNFTs(
            for: account,
            chain: Chain.ethMainnet,
            modelContext: context,
            correlationID: "success-pass"
        )

        let firstSuccessTimestamp = try #require(service.lastSuccessfulRefreshAt)

        await service.refreshNFTs(
            for: account,
            chain: Chain.ethMainnet,
            modelContext: context,
            correlationID: "failure-pass"
        )

        #expect(service.lastSuccessfulRefreshAt == firstSuccessTimestamp)
        #expect(service.error != nil)
        #expect(service.providerFailure?.kind == .offline)
        let failureReceipts = try receiptStore.receipts(forCorrelationID: "failure-pass", limit: 10)
        #expect(failureReceipts.contains(where: { $0.kind == "nft.fetch.failed" }))
        let fetchFailure = try #require(failureReceipts.first(where: { $0.kind == "nft.fetch.failed" }))
        #expect(fetchFailure.details.values["errorKind"] == ReceiptJSONValue.string("<redacted-label>"))
        #expect(fetchFailure.details.values["isRetryable"] == ReceiptJSONValue.bool(true))
    }

    @Test("duplicate in-flight refreshes coalesce into one fetch for the same account scope")
    @MainActor
    func duplicateRefreshesCoalesce() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let receiptStore = SwiftDataReceiptStore(
            modelContext: context,
            sequenceAllocator: ReceiptSequenceAllocator()
        )
        let recorder = ReceiptBackedNFTRefreshEventRecorder(receiptStore: receiptStore)
        let fetcher = SlowStubNFTFetcher()
        let service = NFTService(
            nftFetcher: fetcher,
            refreshTTL: 300,
            eventRecorderFactory: { _ in recorder }
        )
        let account = EOAccount(address: "0x1234567890abcdef1234567890abcdef12345678")

        async let first: Void = service.refreshNFTs(
            for: account,
            chain: Chain.ethMainnet,
            modelContext: context,
            correlationID: "coalesce-1"
        )
        async let second: Void = service.refreshNFTs(
            for: account,
            chain: Chain.ethMainnet,
            modelContext: context,
            correlationID: "coalesce-2"
        )

        _ = await (first, second)

        #expect(fetcher.fetchCallCount == 1)
    }

    @Test("refresh exposes fetch phase while the provider call is still in flight and resets to idle after completion")
    @MainActor
    func refreshPhaseTracksInFlightWork() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let fetcher = GateControlledNFTFetcher()
        let service = NFTService(nftFetcher: fetcher)
        let account = EOAccount(address: "0x1234567890abcdef1234567890abcdef12345678")

        let refreshTask = Task {
            await service.refreshNFTs(
                for: account,
                chain: .ethMainnet,
                modelContext: context,
                correlationID: "phase-tracking"
            )
        }

        await fetcher.waitUntilFetchStarts()
        #expect(service.refreshPhase == .fetching)

        fetcher.resume()
        await refreshTask.value

        #expect(service.refreshPhase == .idle)
    }

    @Test("refresh scopes contract and collection identities by the requested chain")
    @MainActor
    func refreshPersistsScopedContractIdentity() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let fetcher = NFTFixtureFetcher(
            nftsByChain: [
                .baseMainnet: [makeFixtureNFT(network: .ethMainnet)]
            ]
        )
        let service = NFTService(nftFetcher: fetcher)
        let account = EOAccount(address: "0x1234567890abcdef1234567890abcdef12345678")

        await service.refreshNFTs(
            for: account,
            chain: .baseMainnet,
            modelContext: context,
            correlationID: "base-refresh"
        )

        let persistedNFT = try #require(context.fetch(FetchDescriptor<NFT>()).first)

        #expect(persistedNFT.networkRawValue == Chain.baseMainnet.rawValue)
        #expect(persistedNFT.accountAddressRawValue == account.address)
        #expect(persistedNFT.id == "\(account.address):\(Chain.baseMainnet.rawValue):0x495f947276749ce646f68ac8c248420045cb7b5e:42")
        #expect(persistedNFT.contract.id == "\(Chain.baseMainnet.rawValue):0x495f947276749ce646f68ac8c248420045cb7b5e")
        #expect(persistedNFT.collection?.id == "\(Chain.baseMainnet.rawValue):0x495f947276749ce646f68ac8c248420045cb7b5e")
    }

    @Test("same collection name on different contracts stays distinct in persistence")
    @MainActor
    func collectionsDoNotMergeByDisplayNameAlone() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let firstNFT = makeFixtureNFT(
            contractAddress: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            tokenId: "1",
            collectionName: "Shared Name",
            network: .ethMainnet
        )
        let secondNFT = makeFixtureNFT(
            contractAddress: "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
            tokenId: "2",
            collectionName: "Shared Name",
            network: .ethMainnet
        )

        context.insert(firstNFT)
        context.insert(secondNFT)
        try context.save()

        let fetchedNFTs = try context.fetch(FetchDescriptor<NFT>())

        #expect(fetchedNFTs.count == 2)
        #expect(Set(fetchedNFTs.compactMap { $0.collection?.id }).count == 2)
        #expect(Set(fetchedNFTs.map(\.contract.id)).count == 2)
        #expect(Set(fetchedNFTs.map(\.id)).count == 2)
    }

    @Test("same contract address stays distinct across chains in persistence")
    @MainActor
    func contractsDoNotMergeAcrossChains() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let firstNFT = makeFixtureNFT(
            contractAddress: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            tokenId: "1",
            collectionName: "Shared Name",
            network: .ethMainnet
        )
        let secondNFT = makeFixtureNFT(
            contractAddress: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            tokenId: "1",
            collectionName: "Shared Name",
            network: .baseMainnet
        )

        context.insert(firstNFT)
        context.insert(secondNFT)
        try context.save()

        let fetchedNFTs = try context.fetch(FetchDescriptor<NFT>())

        #expect(fetchedNFTs.count == 2)
        #expect(Set(fetchedNFTs.map(\.contract.id)).count == 2)
        #expect(Set(fetchedNFTs.compactMap { $0.collection?.id }).count == 2)
        #expect(Set(fetchedNFTs.map(\.id)).count == 2)
    }

    @Test("refresh cleanup only removes NFTs from the active account scope")
    @MainActor
    func refreshCleanupPreservesOtherAccounts() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let activeAccount = EOAccount(address: "0x1234567890abcdef1234567890abcdef12345678")
        let otherAccountAddress = "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd"

        context.insert(
            makeFixtureNFT(
                contractAddress: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                tokenId: "stale",
                network: .ethMainnet,
                accountAddress: activeAccount.address
            )
        )
        context.insert(
            makeFixtureNFT(
                contractAddress: "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
                tokenId: "other-account",
                network: .ethMainnet,
                accountAddress: otherAccountAddress
            )
        )
        try context.save()

        let fetcher = NFTFixtureFetcher(
            nftsByChain: [
                .ethMainnet: [
                    makeFixtureNFT(
                        contractAddress: "0xcccccccccccccccccccccccccccccccccccccccc",
                        tokenId: "fresh",
                        network: .ethMainnet,
                        accountAddress: activeAccount.address
                    )
                ]
            ]
        )
        let service = NFTService(nftFetcher: fetcher)

        await service.refreshNFTs(
            for: activeAccount,
            chain: .ethMainnet,
            modelContext: context,
            correlationID: "cleanup-account-scope"
        )

        let persisted = try context.fetch(FetchDescriptor<NFT>())
        #expect(persisted.contains(where: { $0.tokenId == "fresh" && $0.accountAddressRawValue == activeAccount.address }))
        #expect(persisted.contains(where: { $0.tokenId == "other-account" && $0.accountAddressRawValue == otherAccountAddress }))
        #expect(!persisted.contains(where: { $0.tokenId == "stale" && $0.accountAddressRawValue == activeAccount.address }))
    }

    @Test("refresh cleanup only removes NFTs from the active chain scope")
    @MainActor
    func refreshCleanupPreservesOtherChains() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let activeAccount = EOAccount(address: "0x1234567890abcdef1234567890abcdef12345678")

        context.insert(
            makeFixtureNFT(
                contractAddress: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                tokenId: "stale-eth",
                network: .ethMainnet,
                accountAddress: activeAccount.address
            )
        )
        context.insert(
            makeFixtureNFT(
                contractAddress: "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
                tokenId: "base-keep",
                network: .baseMainnet,
                accountAddress: activeAccount.address
            )
        )
        try context.save()

        let fetcher = NFTFixtureFetcher(
            nftsByChain: [
                .ethMainnet: [
                    makeFixtureNFT(
                        contractAddress: "0xcccccccccccccccccccccccccccccccccccccccc",
                        tokenId: "fresh-eth",
                        network: .ethMainnet,
                        accountAddress: activeAccount.address
                    )
                ]
            ]
        )
        let service = NFTService(nftFetcher: fetcher)

        await service.refreshNFTs(
            for: activeAccount,
            chain: .ethMainnet,
            modelContext: context,
            correlationID: "cleanup-chain-scope"
        )

        let persisted = try context.fetch(FetchDescriptor<NFT>())
        #expect(persisted.contains(where: { $0.tokenId == "fresh-eth" && $0.networkRawValue == Chain.ethMainnet.rawValue }))
        #expect(persisted.contains(where: { $0.tokenId == "base-keep" && $0.networkRawValue == Chain.baseMainnet.rawValue }))
        #expect(!persisted.contains(where: { $0.tokenId == "stale-eth" && $0.networkRawValue == Chain.ethMainnet.rawValue }))
    }

    @Test("multiple NFTs from the same contract persist in one refresh without conflicting child identities")
    @MainActor
    func refreshPersistsMultipleTokensFromSameContract() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let sharedContractAddress = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        let fetcher = NFTFixtureFetcher(
            nftsByChain: [
                .ethMainnet: [
                    makeFixtureNFT(
                        contractAddress: sharedContractAddress,
                        tokenId: "1",
                        collectionName: "Shared Contract",
                        network: .ethMainnet
                    ),
                    makeFixtureNFT(
                        contractAddress: sharedContractAddress,
                        tokenId: "2",
                        collectionName: "Shared Contract",
                        network: .ethMainnet
                    )
                ]
            ]
        )
        let service = NFTService(nftFetcher: fetcher)
        let account = EOAccount(address: "0x1234567890abcdef1234567890abcdef12345678")

        await service.refreshNFTs(
            for: account,
            chain: .ethMainnet,
            modelContext: context,
            correlationID: "shared-contract-refresh"
        )

        let fetchedNFTs = try context.fetch(FetchDescriptor<NFT>())
        let fetchedContracts = try context.fetch(FetchDescriptor<NFT.Contract>())
        let fetchedCollections = try context.fetch(FetchDescriptor<NFT.Collection>())

        #expect(fetchedNFTs.count == 2)
        #expect(fetchedContracts.count == 1)
        #expect(fetchedCollections.count == 1)
        #expect(Set(fetchedNFTs.map(\.tokenId)) == ["1", "2"])
        #expect(service.error == nil)
    }

    @Test("provider failures map rate-limited and degraded states without relying on raw localized errors")
    @MainActor
    func providerFailuresExposeTypedPresentation() {
        let rateLimitedFailure = NFTProviderFailure(error: NFTFetcher.FetcherError.rateLimited)
        let degradedPresentation = rateLimitedFailure?.presentation(mode: .degraded)

        #expect(rateLimitedFailure?.kind == .rateLimited)
        #expect(rateLimitedFailure?.isRetryable == true)
        #expect(degradedPresentation?.title == "Showing Last Sync")
        #expect(degradedPresentation?.systemImage == "bolt.horizontal.circle")

        let offlineFailure = NFTProviderFailure(
            error: NFTFetcher.FetcherError.networkError(URLError(.notConnectedToInternet))
        )
        let blockingPresentation = offlineFailure?.presentation(mode: .blocking)

        #expect(offlineFailure?.kind == .offline)
        #expect(blockingPresentation?.title == "Collection Unavailable")
        #expect(blockingPresentation?.systemImage == "wifi.slash")
        #expect(blockingPresentation?.isRetryable == true)
    }

    @Test("provider failure presentation switches between blocking and degraded modes based on cached-content visibility")
    @MainActor
    func providerFailurePresentationRespectsCachedContentMode() {
        let service = NFTService(
            nftFetcher: FailingStateNFTFetcher(
                error: NFTFetcher.FetcherError.networkError(URLError(.notConnectedToInternet))
            )
        )

        let blocking = service.providerFailurePresentation(isShowingCachedContent: false)
        let degraded = service.providerFailurePresentation(isShowingCachedContent: true)

        #expect(blocking?.mode == .blocking)
        #expect(blocking?.title == "Collection Unavailable")
        #expect(degraded?.mode == .degraded)
        #expect(degraded?.title == "Refresh Paused")
        #expect(degraded?.isRetryable == true)
    }

    @Test("one shell refresh flow can share a correlation ID across NFT refresh and context build receipts")
    @MainActor
    func shellRefreshFlowSharesCorrelationAcrossNFTAndContextReceipts() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let receiptStore = SwiftDataReceiptStore(
            modelContext: context,
            sequenceAllocator: ReceiptSequenceAllocator()
        )
        let recorder = ReceiptBackedNFTRefreshEventRecorder(receiptStore: receiptStore)
        let fetcher = StubNFTFetcher()
        let nftService = NFTService(
            nftFetcher: fetcher,
            eventRecorderFactory: { _ in recorder }
        )
        let logger = ReceiptEventLogger(receiptStore: receiptStore)
        let account = EOAccount(address: "0x1234567890abcdef1234567890abcdef12345678")
        let correlationID = "shell-flow-correlation-1"

        await nftService.refreshNFTs(
            for: account,
            chain: Chain.ethMainnet,
            modelContext: context,
            correlationID: correlationID
        )

        let contextService = ContextService(
            contextSourceBuilder: LiveShellContextSourceBuilder(),
            accountProvider: { account },
            addressProvider: { account.address },
            chainProvider: { .ethMainnet },
            modeProvider: { .observe },
            loadingProvider: { nftService.isLoading },
            refreshedAtProvider: { nftService.lastSuccessfulRefreshAt },
            nativeBalanceProvider: StubNativeBalanceProvider(),
            freshnessTTLProvider: { nftService.refreshTTL },
            trackedNFTCountProvider: { account.trackedNFTCount },
            musicCollectionCountProvider: { nil },
            receiptCountProvider: { nil },
            pinnedActionsProvider: { [] },
            prefersDemoDataProvider: { false },
            pinnedItemCountProvider: { nil }
        )

        _ = await contextService.refresh(
            correlationID: correlationID,
            receiptEventLogger: logger
        )

        let receipts = try receiptStore.receipts(forCorrelationID: correlationID, limit: 10)

        #expect(receipts.contains(where: { $0.kind == "nft.refresh.started" }))
        #expect(receipts.contains(where: { $0.kind == "nft.fetch.succeeded" }))
        #expect(receipts.contains(where: { $0.kind == "nft.persistence.completed" }))
        #expect(receipts.contains(where: { $0.kind == "context.built" }))
        #expect(receipts.allSatisfy { $0.correlationID == correlationID })
    }
}

private final class StubNFTFetcher: NFTFetching {
    var total: Int? = 0
    var itemsLoaded: Int? = 0
    var loading = false
    var error: Error?
    var currentCursor: String?
    private(set) var receivedCorrelationIDs: [String?] = []

    func fetchAllNFTs(
        for account: String,
        chain: Chain,
        correlationID: String?,
        eventRecorder: any NFTRefreshEventRecording
    ) async throws -> [NFT] {
        receivedCorrelationIDs.append(correlationID)

        if let correlationID {
            await eventRecorder.recordFetchSucceeded(
                accountAddress: account,
                chain: chain,
                correlationID: correlationID,
                itemCount: 0,
                totalCount: 0
            )
        }

        return []
    }

    func reset() {
        total = nil
        itemsLoaded = 0
        loading = false
        currentCursor = nil
        error = nil
    }
}

private final class FlakyNFTFetcher: NFTFetching {
    var total: Int? = 0
    var itemsLoaded: Int? = 0
    var loading = false
    var error: Error?
    var currentCursor: String?
    private(set) var fetchCallCount = 0

    func fetchAllNFTs(
        for account: String,
        chain: Chain,
        correlationID: String?,
        eventRecorder: any NFTRefreshEventRecording
    ) async throws -> [NFT] {
        fetchCallCount += 1

        if fetchCallCount == 1 {
            if let correlationID {
                await eventRecorder.recordFetchSucceeded(
                    accountAddress: account,
                    chain: chain,
                    correlationID: correlationID,
                    itemCount: 0,
                    totalCount: 0
                )
            }
            return []
        }

        let error = NFTFetcher.FetcherError.networkError(URLError(.notConnectedToInternet))
        if let correlationID {
            await eventRecorder.recordFetchFailed(
                accountAddress: account,
                chain: chain,
                correlationID: correlationID,
                error: error
            )
        }
        throw error
    }

    func reset() {
        total = nil
        itemsLoaded = 0
        loading = false
        currentCursor = nil
        error = nil
    }
}

private final class NFTFixtureFetcher: NFTFetching {
    var total: Int? = 0
    var itemsLoaded: Int? = 0
    var loading = false
    var error: Error?
    var currentCursor: String?
    private let nftsByChain: [Chain: [NFT]]

    init(nftsByChain: [Chain: [NFT]]) {
        self.nftsByChain = nftsByChain
    }

    func fetchAllNFTs(
        for account: String,
        chain: Chain,
        correlationID: String?,
        eventRecorder: any NFTRefreshEventRecording
    ) async throws -> [NFT] {
        let nfts = nftsByChain[chain] ?? []
        itemsLoaded = nfts.count
        total = nfts.count
        currentCursor = nil
        return nfts
    }

    func reset() {
        total = nil
        itemsLoaded = 0
        loading = false
        currentCursor = nil
        error = nil
    }
}

private struct StubNativeBalanceProvider: NativeBalanceProviding {
    func nativeBalance(for address: String, chain: Chain) async throws -> NativeBalance {
        NativeBalance(weiHex: "0x0", weiDecimal: "0")
    }
}

private final class SlowStubNFTFetcher: NFTFetching {
    var total: Int? = 0
    var itemsLoaded: Int? = 0
    var loading = false
    var error: Error?
    var currentCursor: String?
    private(set) var fetchCallCount = 0

    func fetchAllNFTs(
        for account: String,
        chain: Chain,
        correlationID: String?,
        eventRecorder: any NFTRefreshEventRecording
    ) async throws -> [NFT] {
        fetchCallCount += 1

        if let correlationID {
            await eventRecorder.recordFetchSucceeded(
                accountAddress: account,
                chain: chain,
                correlationID: correlationID,
                itemCount: 0,
                totalCount: 0
            )
        }

        try await Task.sleep(for: .milliseconds(50))
        return []
    }

    func reset() {
        total = nil
        itemsLoaded = 0
        loading = false
        currentCursor = nil
        error = nil
    }
}

private final class GateControlledNFTFetcher: NFTFetching {
    var total: Int? = 0
    var itemsLoaded: Int? = 0
    var loading = false
    var error: Error?
    var currentCursor: String?

    private var fetchStartedContinuation: CheckedContinuation<Void, Never>?
    private var resumeContinuation: CheckedContinuation<Void, Never>?
    private var didStartFetch = false

    func fetchAllNFTs(
        for account: String,
        chain: Chain,
        correlationID: String?,
        eventRecorder: any NFTRefreshEventRecording
    ) async throws -> [NFT] {
        itemsLoaded = 0
        total = 0
        didStartFetch = true
        fetchStartedContinuation?.resume()
        fetchStartedContinuation = nil

        await withCheckedContinuation { continuation in
            resumeContinuation = continuation
        }

        return []
    }

    func waitUntilFetchStarts() async {
        if didStartFetch {
            return
        }

        await withCheckedContinuation { continuation in
            fetchStartedContinuation = continuation
        }
    }

    func resume() {
        resumeContinuation?.resume()
        resumeContinuation = nil
    }

    func reset() {
        total = nil
        itemsLoaded = 0
        loading = false
        currentCursor = nil
        error = nil
    }
}

private final class FailingStateNFTFetcher: NFTFetching {
    var total: Int? = 0
    var itemsLoaded: Int? = 0
    var loading = false
    var error: Error?
    var currentCursor: String?

    init(error: Error) {
        self.error = error
    }

    func fetchAllNFTs(
        for account: String,
        chain: Chain,
        correlationID: String?,
        eventRecorder: any NFTRefreshEventRecording
    ) async throws -> [NFT] {
        throw error ?? NFTFetcher.FetcherError.networkError(URLError(.unknown))
    }

    func reset() {
        total = nil
        itemsLoaded = 0
        loading = false
        currentCursor = nil
        error = nil
    }
}

private func makeFixtureNFT(
    contractAddress: String = "0x495f947276749ce646f68ac8c248420045cb7b5e",
    tokenId: String = "42",
    collectionName: String = "Fixture Collection",
    network: Chain = .ethMainnet,
    accountAddress: String = "0x1234567890abcdef1234567890abcdef12345678"
) -> NFT {
    let normalizedAccountAddress = NFT.normalizedScopeComponent(accountAddress) ?? "unscoped"
    let normalizedContractAddress = NFT.normalizedScopeComponent(contractAddress) ?? "unknown"
    return NFT(
        id: "\(normalizedAccountAddress):\(network.rawValue):\(normalizedContractAddress):\(tokenId)",
        contract: NFT.Contract(address: contractAddress, chain: network),
        tokenId: tokenId,
        name: "Fixture NFT",
        image: nil,
        raw: nil,
        collection: NFT.Collection(
            name: collectionName,
            chain: network,
            contractAddress: contractAddress
        ),
        tokenUri: "ipfs://fixture-\(tokenId)",
        network: network,
        accountAddress: accountAddress,
        collectionName: collectionName
    )
}
