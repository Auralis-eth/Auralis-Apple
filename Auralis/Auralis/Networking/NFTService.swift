//
//  NFTService.swift
//  Auralis
//
//  Created by Daniel Bell on 6/29/25.
//

import Foundation
import SwiftData

enum NFTServiceRefreshPhase: Equatable {
    case idle
    case fetching
    case processingMetadata(itemCount: Int)
    case persisting(itemCount: Int)
    case cleaningUp(itemCount: Int)
}

@MainActor
@Observable
/// Coordinates NFT refresh work across fetching, metadata preparation, and SwiftData persistence.
class NFTService {
    typealias RefreshPhase = NFTServiceRefreshPhase

    private let nftFetcher: any NFTFetching
    private let fetchInventoryUseCase: any FetchNFTInventoryUsing
    private let prepareMetadataUseCase: any PrepareNFTMetadataUsing
    private let persistInventoryUseCase: any PersistNFTInventoryUsing
    private let refreshStateComputer: NFTRefreshStateComputer
    private let eventRecorderFactory: @MainActor (ModelContext) -> any NFTRefreshEventRecording

    let refreshTTL: TimeInterval

    var isLoading: Bool { nftFetcher.loading }
    var itemsLoaded: Int? { nftFetcher.itemsLoaded }
    var total: Int? { nftFetcher.total }
    var error: Error? { nftFetcher.error }
    var providerFailure: NFTProviderFailure? { NFTProviderFailure(error: error) }

    private(set) var refreshPhase: NFTServiceRefreshPhase = .idle
    private var inFlightRefreshScope: NFTRefreshScope?
    private var inFlightRefreshTask: Task<Void, Never>?
    private var inFlightRefreshToken: UUID?

    /// Creates the shared NFT orchestration service used by the shell.
    init(
        nftFetcher: (any NFTFetching)? = nil,
        refreshTTL: TimeInterval = 300,
        fetchInventoryUseCase: (any FetchNFTInventoryUsing)? = nil,
        prepareMetadataUseCase: (any PrepareNFTMetadataUsing)? = nil,
        persistInventoryUseCase: (any PersistNFTInventoryUsing)? = nil,
        refreshStateComputer: NFTRefreshStateComputer? = nil,
        eventRecorderFactory: @escaping @MainActor (ModelContext) -> any NFTRefreshEventRecording = {
            NFTRefreshEventRecorders.live(modelContext: $0)
        }
    ) {
        let resolvedFetcher = nftFetcher ?? NFTFetcher()
        self.nftFetcher = resolvedFetcher
        self.refreshTTL = refreshTTL
        self.fetchInventoryUseCase = fetchInventoryUseCase ?? LiveFetchNFTInventoryUseCase(nftFetcher: resolvedFetcher)
        self.prepareMetadataUseCase = prepareMetadataUseCase ?? LivePrepareNFTMetadataUseCase()
        self.persistInventoryUseCase = persistInventoryUseCase ?? LivePersistNFTInventoryUseCase()
        self.refreshStateComputer = refreshStateComputer ?? NFTRefreshStateComputer(refreshTTL: refreshTTL)
        self.eventRecorderFactory = eventRecorderFactory
    }

    func lastSuccessfulRefreshAt(
        for accountAddress: String?,
        chain: Chain
    ) -> Date? {
        refreshStateComputer.lastSuccessfulRefreshAt(
            for: accountAddress,
            chain: chain
        )
    }

    func fetchAllNFTs(
        for accountAddress: String,
        chain: Chain,
        modelContext: ModelContext,
        correlationID: String
    ) async {
        refreshPhase = .fetching
        await Task.yield()
        let eventRecorder = eventRecorderFactory(modelContext)

        await eventRecorder.recordRefreshStarted(
            accountAddress: accountAddress,
            chain: chain,
            correlationID: correlationID
        )

        do {
            let fetchedInventory = try await fetchInventoryUseCase.fetchInventory(
                for: accountAddress,
                chain: chain,
                correlationID: correlationID,
                eventRecorder: eventRecorder
            )

            refreshPhase = .processingMetadata(itemCount: fetchedInventory.nfts.count)
            let preparedInventory = await prepareMetadataUseCase.prepareInventory(
                fetchedInventory.nfts,
                accountAddress: accountAddress,
                chain: chain
            )

            do {
                refreshPhase = .persisting(itemCount: preparedInventory.nfts.count)
                await Task.yield()

                if fetchedInventory.didCompleteFullRefresh {
                    refreshPhase = .cleaningUp(itemCount: preparedInventory.nfts.count)
                    await Task.yield()
                }

                try await persistInventoryUseCase.persist(
                    preparedInventory,
                    accountAddress: accountAddress,
                    chain: chain,
                    modelContext: modelContext
                )

                if fetchedInventory.didCompleteFullRefresh {
                    refreshPhase = .cleaningUp(itemCount: preparedInventory.nfts.count)
                    await Task.yield()
                    try await persistInventoryUseCase.cleanupStaleInventory(
                        currentNFTIDs: preparedInventory.nfts.map(\.id),
                        accountAddress: accountAddress,
                        chain: chain,
                        modelContext: modelContext
                    )
                }

                refreshStateComputer.markRefreshSucceeded(
                    for: accountAddress,
                    chain: chain
                )
                await eventRecorder.recordPersistenceCompleted(
                    accountAddress: accountAddress,
                    chain: chain,
                    correlationID: correlationID,
                    persistedCount: preparedInventory.nfts.count
                )
            } catch {
                nftFetcher.error = error
                await eventRecorder.recordPersistenceFailed(
                    accountAddress: accountAddress,
                    chain: chain,
                    correlationID: correlationID,
                    error: error
                )
                throw error
            }
        } catch is CancellationError {
            nftFetcher.error = nil
        } catch {
            nftFetcher.error = error
        }

        let terminalError = nftFetcher.error
        nftFetcher.reset()
        refreshPhase = .idle
        if let terminalError {
            nftFetcher.error = terminalError
        }
    }

    func refreshNFTs(
        for currentAccount: EOAccount?,
        chain: Chain,
        modelContext: ModelContext,
        correlationID: String
    ) async {
        guard let accountAddress = currentAccount?.address else {
            return
        }

        guard let requestedScope = NFTRefreshScope(
            accountAddress: accountAddress,
            chain: chain
        ) else {
            return
        }

        if let inFlightRefreshTask {
            if inFlightRefreshScope == requestedScope {
                await inFlightRefreshTask.value
                return
            }

            inFlightRefreshTask.cancel()
            await inFlightRefreshTask.value
        }

        let refreshToken = UUID()
        let task = Task { [self] in
            await fetchAllNFTs(
                for: accountAddress,
                chain: chain,
                modelContext: modelContext,
                correlationID: correlationID
            )
        }

        inFlightRefreshScope = requestedScope
        inFlightRefreshTask = task
        inFlightRefreshToken = refreshToken

        await task.value

        if inFlightRefreshToken == refreshToken {
            inFlightRefreshScope = nil
            inFlightRefreshTask = nil
            inFlightRefreshToken = nil
        }
    }

    func reset() {
        inFlightRefreshTask?.cancel()
        inFlightRefreshTask = nil
        inFlightRefreshScope = nil
        inFlightRefreshToken = nil
        refreshStateComputer.reset()
        nftFetcher.reset()
    }

    func providerFailurePresentation(
        isShowingCachedContent: Bool
    ) -> NFTProviderFailurePresentation? {
        guard let providerFailure else {
            return nil
        }

        return providerFailure.presentation(
            mode: isShowingCachedContent ? .degraded : .blocking
        )
    }
}
