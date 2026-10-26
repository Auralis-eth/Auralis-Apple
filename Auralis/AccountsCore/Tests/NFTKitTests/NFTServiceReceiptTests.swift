import AuralisPrimaryModels
import AuralisPrimaryPersistence
import AuralisTestSupport
import Foundation
import NFTDomain
import NFTPersistence
import NFTPresentation
import NFTProviderAdapters
import ProviderKit
import ReceiptsCore
import ReceiptStorage
import SwiftData
import Testing

struct NFTServiceReceiptTests {
    @Test("refresh flow carries one caller-provided correlation ID across service fetch and persistence receipts")
    @MainActor
    func refreshFlowUsesSharedCorrelationID() async throws {
        let container = try NFTKitTestModelContainers.refresh()
        let context = ModelContext(container)
        let receiptStore = SwiftDataReceiptStore(
            modelContext: context
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

        let receipts = try await receiptStore.receipts(forCorrelationID: correlationID, limit: 10)

        #expect(await fetcher.receivedCorrelationIDs == [correlationID])
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
        let container = try NFTKitTestModelContainers.refresh()
        let context = ModelContext(container)
        let receiptStore = SwiftDataReceiptStore(
            modelContext: context
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

        let firstSuccessTimestamp = try #require(
            service.lastSuccessfulRefreshAt(
                for: account.address,
                chain: .ethMainnet
            )
        )

        await service.refreshNFTs(
            for: account,
            chain: Chain.ethMainnet,
            modelContext: context,
            correlationID: "failure-pass"
        )

        #expect(
            service.lastSuccessfulRefreshAt(
                for: account.address,
                chain: .ethMainnet
            ) == firstSuccessTimestamp
        )
        guard case NFTFetcher.FetcherError.networkError(let error as URLError)? = service.error else {
            Issue.record("Expected offline network error, got \(String(describing: service.error)).")
            return
        }
        #expect(error.code == .notConnectedToInternet)
        #expect(try #require(service.providerFailure).kind == .offline)
        let failureReceipts = try await receiptStore.receipts(forCorrelationID: "failure-pass", limit: 10)
        #expect(failureReceipts.contains(where: { $0.kind == "nft.fetch.failed" }))
        let fetchFailure = try #require(failureReceipts.first(where: { $0.kind == "nft.fetch.failed" }))
        #expect(fetchFailure.details.values["errorKind"] == ReceiptJSONValue.string("<redacted-label>"))
        #expect(fetchFailure.details.values["isRetryable"] == ReceiptJSONValue.bool(true))
    }

    @Test(
        "duplicate in-flight refreshes coalesce into one fetch for the same account scope",
        .timeLimit(.minutes(1))
    )
    @MainActor
    func duplicateRefreshesCoalesce() async throws {
        let container = try NFTKitTestModelContainers.refresh()
        let context = ModelContext(container)
        let receiptStore = SwiftDataReceiptStore(
            modelContext: context
        )
        let recorder = ReceiptBackedNFTRefreshEventRecorder(receiptStore: receiptStore)
        let fetcher = SlowStubNFTFetcher()
        let service = NFTService(
            nftFetcher: fetcher,
            refreshTTL: 300,
            eventRecorderFactory: { _ in recorder }
        )
        let account = EOAccount(address: "0x1234567890abcdef1234567890abcdef12345678")

        let first = Task { @MainActor in
            await service.refreshNFTs(
                for: account,
                chain: Chain.ethMainnet,
                modelContext: context,
                correlationID: "coalesce-1"
            )
        }
        await fetcher.waitUntilFetchStarts()
        let second = Task { @MainActor in
            await service.refreshNFTs(
                for: account,
                chain: Chain.ethMainnet,
                modelContext: context,
                correlationID: "coalesce-2"
            )
        }
        await fetcher.resume()

        _ = await (first.value, second.value)

        #expect(await fetcher.fetchCallCount == 1)
    }

    @Test(
        "refresh exposes fetch phase while the provider call is still in flight and resets to idle after completion",
        .timeLimit(.minutes(1))
    )
    @MainActor
    func refreshPhaseTracksInFlightWork() async throws {
        let container = try NFTKitTestModelContainers.refresh()
        let context = ModelContext(container)
        let fetcher = GateControlledNFTFetcher()
        let service = NFTService(nftFetcher: fetcher)
        let account = EOAccount(address: "0x1234567890abcdef1234567890abcdef12345678")

        let refreshTask = Task { @MainActor in
            await service.refreshNFTs(
                for: account,
                chain: .ethMainnet,
                modelContext: context,
                correlationID: "phase-tracking"
            )
        }

        await fetcher.waitUntilFetchStarts()
        #expect(service.refreshPhase == .fetching)

        await fetcher.resume()
        await refreshTask.value

        #expect(service.refreshPhase == .idle)
    }

    @Test("refresh scopes contract and collection identities by the requested chain")
    @MainActor
    func refreshPersistsScopedContractIdentity() async throws {
        let container = try NFTKitTestModelContainers.refresh()
        let context = ModelContext(container)
        let fetcher = NFTFixtureFetcher(
            nftsByChain: [
                .baseMainnet: [makeRefreshFixtureSnapshot(network: .ethMainnet)]
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
        let collection = try #require(persistedNFT.collection)
        #expect(collection.id == "\(Chain.baseMainnet.rawValue):0x495f947276749ce646f68ac8c248420045cb7b5e")
    }

    @Test("same collection name on different contracts stays distinct in persistence")
    @MainActor
    func collectionsDoNotMergeByDisplayNameAlone() async throws {
        let container = try NFTKitTestModelContainers.refresh()
        let context = ModelContext(container)

        let firstNFT = NFTFixture(
            tokenId: "1",
            contractAddress: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            collectionName: "Shared Name",
            network: .ethMainnet
        ).build()
        let secondNFT = NFTFixture(
            tokenId: "2",
            contractAddress: "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
            collectionName: "Shared Name",
            network: .ethMainnet
        ).build()

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
        let container = try NFTKitTestModelContainers.refresh()
        let context = ModelContext(container)

        let firstNFT = NFTFixture(
            tokenId: "1",
            contractAddress: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            collectionName: "Shared Name",
            network: .ethMainnet
        ).build()
        let secondNFT = NFTFixture(
            tokenId: "1",
            contractAddress: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            collectionName: "Shared Name",
            network: .baseMainnet
        ).build()

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
        let container = try NFTKitTestModelContainers.refresh()
        let context = ModelContext(container)
        let activeAccount = EOAccount(address: "0x1234567890abcdef1234567890abcdef12345678")
        let otherAccountAddress = "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd"

        context.insert(
            NFTFixture(
                tokenId: "stale",
                accountAddress: activeAccount.address,
                contractAddress: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                network: .ethMainnet
            ).build()
        )
        context.insert(
            NFTFixture(
                tokenId: "other-account",
                accountAddress: otherAccountAddress,
                contractAddress: "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
                network: .ethMainnet
            ).build()
        )
        try context.save()

        let fetcher = NFTFixtureFetcher(
            nftsByChain: [
                .ethMainnet: [
                    makeRefreshFixtureSnapshot(
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
        #expect(persisted.contains(where: { $0.tokenId == "stale" && $0.accountAddressRawValue == activeAccount.address }) == false)
    }

    @Test("refresh cleanup only removes NFTs from the active chain scope")
    @MainActor
    func refreshCleanupPreservesOtherChains() async throws {
        let container = try NFTKitTestModelContainers.refresh()
        let context = ModelContext(container)
        let activeAccount = EOAccount(address: "0x1234567890abcdef1234567890abcdef12345678")

        context.insert(
            NFTFixture(
                tokenId: "stale-eth",
                accountAddress: activeAccount.address,
                contractAddress: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                network: .ethMainnet
            ).build()
        )
        context.insert(
            NFTFixture(
                tokenId: "base-keep",
                accountAddress: activeAccount.address,
                contractAddress: "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
                network: .baseMainnet
            ).build()
        )
        try context.save()

        let fetcher = NFTFixtureFetcher(
            nftsByChain: [
                .ethMainnet: [
                    makeRefreshFixtureSnapshot(
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
        #expect(persisted.contains(where: { $0.tokenId == "stale-eth" && $0.networkRawValue == Chain.ethMainnet.rawValue }) == false)
    }

    @Test("multiple NFTs from the same contract persist in one refresh without conflicting child identities")
    @MainActor
    func refreshPersistsMultipleTokensFromSameContract() async throws {
        let container = try NFTKitTestModelContainers.refresh()
        let context = ModelContext(container)
        let sharedContractAddress = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        let fetcher = NFTFixtureFetcher(
            nftsByChain: [
                .ethMainnet: [
                    makeRefreshFixtureSnapshot(
                        contractAddress: sharedContractAddress,
                        tokenId: "1",
                        collectionName: "Shared Contract",
                        network: .ethMainnet
                    ),
                    makeRefreshFixtureSnapshot(
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
    func providerFailuresExposeTypedPresentation() throws {
        let rateLimitedFailureResult = NFTProviderFailure(error: NFTFetcher.FetcherError.rateLimited)
        let degradedPresentationResult = rateLimitedFailureResult?.presentation(mode: .degraded)

        let rateLimitedFailure = try #require(rateLimitedFailureResult)
        let degradedPresentation = try #require(degradedPresentationResult)
        #expect(rateLimitedFailure.kind == .rateLimited)
        #expect(rateLimitedFailure.isRetryable)
        #expect(degradedPresentation.title == "Showing Last Sync")
        #expect(degradedPresentation.systemImage == "bolt.horizontal.circle")

        let offlineFailureResult = NFTProviderFailure(
            error: NFTFetcher.FetcherError.networkError(URLError(.notConnectedToInternet))
        )
        let blockingPresentationResult = offlineFailureResult?.presentation(mode: .blocking)

        let offlineFailure = try #require(offlineFailureResult)
        let blockingPresentation = try #require(blockingPresentationResult)
        #expect(offlineFailure.kind == .offline)
        #expect(blockingPresentation.title == "Collection Unavailable")
        #expect(blockingPresentation.systemImage == "wifi.slash")
        #expect(blockingPresentation.isRetryable)
    }

    @Test("provider failure presentation switches between blocking and degraded modes based on cached-content visibility")
    @MainActor
    func providerFailurePresentationRespectsCachedContentMode() async throws {
        let container = try NFTKitTestModelContainers.refresh()
        let context = ModelContext(container)
        let service = NFTService(
            nftFetcher: FailingStateNFTFetcher(
                error: NFTFetcher.FetcherError.networkError(URLError(.notConnectedToInternet))
            )
        )

        await service.fetchAllNFTs(
            for: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .ethMainnet,
            modelContext: context,
            correlationID: "provider-presentation-failure"
        )

        let blockingResult = service.providerFailurePresentation(isShowingCachedContent: false)
        let degradedResult = service.providerFailurePresentation(isShowingCachedContent: true)

        let blocking = try #require(blockingResult)
        let degraded = try #require(degradedResult)
        #expect(blocking.mode == .blocking)
        #expect(blocking.title == "Collection Unavailable")
        #expect(degraded.mode == .degraded)
        #expect(degraded.title == "Refresh Paused")
        #expect(degraded.isRetryable)
    }

    @Test("terminal fetch errors survive fetcher reset cleanup")
    @MainActor
    func terminalFetchErrorSurvivesResetCleanup() async throws {
        let container = try NFTKitTestModelContainers.refresh()
        let context = ModelContext(container)
        let expectedError = NFTFetcher.FetcherError.networkError(URLError(.notConnectedToInternet))
        let fetcher = FailingStateNFTFetcher(error: expectedError)
        let service = NFTService(nftFetcher: fetcher)

        await service.fetchAllNFTs(
            for: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .ethMainnet,
            modelContext: context,
            correlationID: "terminal-error-reset"
        )

        #expect(service.itemsLoaded == nil)
        guard case NFTFetcher.FetcherError.networkError(let error as URLError)? = service.error else {
            Issue.record("Expected offline network error, got \(String(describing: service.error)).")
            return
        }
        #expect(error.code == .notConnectedToInternet)
        #expect(try #require(service.providerFailure).kind == .offline)
    }

    @Test("one shell refresh flow can share a correlation ID across NFT refresh and context build receipts")
    @MainActor
    func shellRefreshFlowSharesCorrelationAcrossNFTAndContextReceipts() async throws {
        let container = try NFTKitTestModelContainers.refresh()
        let context = ModelContext(container)
        let receiptStore = SwiftDataReceiptStore(
            modelContext: context
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

        _ = try await logger.append(
            trigger: "context.built",
            scope: "context",
            summary: "Built shell context snapshot",
            provenance: "local_cache",
            timelineAccountAddress: account.address,
            timelineChainRawValue: Chain.ethMainnet.rawValue,
            rawPayload: RawReceiptPayload(fields: [
                .public("accountAddress", string: account.address, kind: .walletAddress),
                .public("chain", string: Chain.ethMainnet.rawValue, kind: .chain),
                .bool("loading", nftService.isLoading)
            ]),
            correlationID: correlationID,
            actorDetail: .workflow("nft.refresh"),
            authorityDetail: ReceiptAuthorityDetail(
                source: "policyDefault",
                reason: "Local context construction is allowed by standing policy."
            ),
            isSuccess: true
        )

        let receipts = try await receiptStore.receipts(forCorrelationID: correlationID, limit: 10)

        #expect(receipts.contains(where: { $0.kind == "nft.refresh.started" }))
        #expect(receipts.contains(where: { $0.kind == "nft.fetch.succeeded" }))
        #expect(receipts.contains(where: { $0.kind == "nft.persistence.completed" }))
        #expect(receipts.contains(where: { $0.kind == "context.built" }))
        #expect(receipts.allSatisfy { $0.correlationID == correlationID })
    }

    /// Receipts are telemetry *about* the refresh, not a precondition for it.
    ///
    /// This is the contract an NFT refresh crash depended on and nothing covered. The receipt ledger
    /// refuses a re-entrant append rather than trapping, which only helps if the refresh survives the
    /// refusal — so a store that throws from every `append` must still leave a fetched, persisted
    /// inventory and an unflagged service. The thrown error is a stand-in: the ledger's own
    /// re-entrancy error is internal to `ReceiptStorage`, and the recorder only reads
    /// `localizedDescription`, so the identity of the failure is not what is being proven here.
    @Test("a refresh completes when every receipt append fails")
    @MainActor
    func refreshSurvivesReceiptAppendFailure() async throws {
        let container = try NFTKitTestModelContainers.refresh()
        let context = ModelContext(container)
        let receiptStore = AppendFailingReceiptStore(
            wrapped: SwiftDataReceiptStore(modelContext: context)
        )
        let recorder = ReceiptBackedNFTRefreshEventRecorder(receiptStore: receiptStore)
        let fetcher = NFTFixtureFetcher(
            nftsByChain: [
                .ethMainnet: [makeRefreshFixtureSnapshot(network: .ethMainnet)]
            ]
        )
        let service = NFTService(
            nftFetcher: fetcher,
            eventRecorderFactory: { _ in recorder }
        )
        let account = EOAccount(address: "0x1234567890abcdef1234567890abcdef12345678")

        await service.refreshNFTs(
            for: account,
            chain: .ethMainnet,
            modelContext: context,
            correlationID: "receipts-unavailable"
        )

        // The refresh did its actual job.
        let persistedNFT = try #require(context.fetch(FetchDescriptor<NFT>()).first)
        #expect(persistedNFT.accountAddressRawValue == account.address)
        #expect(service.error == nil, "a rejected receipt was reported to the user as a refresh failure")

        // And swallowed the telemetry rather than half-writing it.
        let receipts = try await receiptStore.receipts(forCorrelationID: "receipts-unavailable", limit: 10)
        #expect(receipts.isEmpty)
    }
}

/// Forwards every read to a real store and fails every write, so a test can ask what a refresh does
/// when the ledger will not accept its telemetry.
private struct AppendFailingReceiptStore: ReceiptStore {
    struct AppendRefused: Error {}

    let wrapped: SwiftDataReceiptStore

    func append(_ receipt: ReceiptDraft) async throws -> ReceiptRecord {
        throw AppendRefused()
    }

    func latest(limit: Int) async throws -> [ReceiptRecord] {
        try await wrapped.latest(limit: limit)
    }

    func receipts(forCorrelationID correlationID: String, limit: Int) async throws -> [ReceiptRecord] {
        try await wrapped.receipts(forCorrelationID: correlationID, limit: limit)
    }

    func exportAll() async throws -> Data {
        try await wrapped.exportAll()
    }

    func resetAll() async throws {
        try await wrapped.resetAll()
    }
}

private actor StubNFTFetcher: NFTFetching {
    private(set) var receivedCorrelationIDs: [String?] = []

    func fetchAllNFTs(
        for account: String,
        chain: Chain,
        correlationID: String?,
        eventRecorder: any NFTRefreshEventRecording,
        progressHandler: NFTFetchProgressHandler?
    ) async throws -> NFTFetchInventoryResult {
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

        return NFTFetchInventoryResult(nfts: [], didCompleteFullRefresh: true, totalCount: 0)
    }
}

private actor FlakyNFTFetcher: NFTFetching {
    private(set) var fetchCallCount = 0

    func fetchAllNFTs(
        for account: String,
        chain: Chain,
        correlationID: String?,
        eventRecorder: any NFTRefreshEventRecording,
        progressHandler: NFTFetchProgressHandler?
    ) async throws -> NFTFetchInventoryResult {
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
            return NFTFetchInventoryResult(nfts: [], didCompleteFullRefresh: true, totalCount: 0)
        }

        let error = NFTFetcher.FetcherError.networkError(URLError(.notConnectedToInternet))
        if let correlationID {
            await eventRecorder.recordFetchFailed(
                accountAddress: account,
                chain: chain,
                correlationID: correlationID,
                failure: NFTProviderFailure(error: error)
                    ?? NFTProviderFailure.classifyNetworkOrFallback(error)
            )
        }
        throw error
    }
}

private actor NFTFixtureFetcher: NFTFetching {
    private let nftsByChain: [Chain: [NFTInventoryItemSnapshot]]

    init(nftsByChain: [Chain: [NFTInventoryItemSnapshot]]) {
        self.nftsByChain = nftsByChain
    }

    func fetchAllNFTs(
        for account: String,
        chain: Chain,
        correlationID: String?,
        eventRecorder: any NFTRefreshEventRecording,
        progressHandler: NFTFetchProgressHandler?
    ) async throws -> NFTFetchInventoryResult {
        let nfts = nftsByChain[chain] ?? []
        return NFTFetchInventoryResult(
            nfts: nfts,
            didCompleteFullRefresh: true,
            totalCount: nfts.count
        )
    }
}

private struct StubNativeBalanceProvider: NativeBalanceProviding {
    func nativeBalance(for address: String, chain: Chain) async throws -> NativeBalance {
        NativeBalance(weiHex: "0x0", weiDecimal: "0")
    }
}

private actor SlowStubNFTFetcher: NFTFetching {
    private(set) var fetchCallCount = 0
    private var fetchStartedContinuation: CheckedContinuation<Void, Never>?
    private var resumeContinuation: CheckedContinuation<Void, Never>?

    func fetchAllNFTs(
        for account: String,
        chain: Chain,
        correlationID: String?,
        eventRecorder: any NFTRefreshEventRecording,
        progressHandler: NFTFetchProgressHandler?
    ) async throws -> NFTFetchInventoryResult {
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

        fetchStartedContinuation?.resume()
        fetchStartedContinuation = nil
        await withCheckedContinuation { continuation in
            resumeContinuation = continuation
        }
        return NFTFetchInventoryResult(nfts: [], didCompleteFullRefresh: true, totalCount: 0)
    }

    func waitUntilFetchStarts() async {
        if fetchCallCount > 0 {
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
}

private actor GateControlledNFTFetcher: NFTFetching {
    private var fetchStartedContinuation: CheckedContinuation<Void, Never>?
    private var resumeContinuation: CheckedContinuation<Void, Never>?
    private var didStartFetch = false

    func fetchAllNFTs(
        for account: String,
        chain: Chain,
        correlationID: String?,
        eventRecorder: any NFTRefreshEventRecording,
        progressHandler: NFTFetchProgressHandler?
    ) async throws -> NFTFetchInventoryResult {
        didStartFetch = true
        fetchStartedContinuation?.resume()
        fetchStartedContinuation = nil

        await withCheckedContinuation { continuation in
            resumeContinuation = continuation
        }

        return NFTFetchInventoryResult(nfts: [], didCompleteFullRefresh: true, totalCount: 0)
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
}

private actor FailingStateNFTFetcher: NFTFetching {
    private let error: Error

    init(error: Error) {
        self.error = error
    }

    func fetchAllNFTs(
        for account: String,
        chain: Chain,
        correlationID: String?,
        eventRecorder: any NFTRefreshEventRecording,
        progressHandler: NFTFetchProgressHandler?
    ) async throws -> NFTFetchInventoryResult {
        throw error
    }
}
