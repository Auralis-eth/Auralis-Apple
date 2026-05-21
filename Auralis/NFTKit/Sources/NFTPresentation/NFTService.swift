//
//  NFTService.swift
//  Auralis
//
//  Created by Daniel Bell on 6/29/25.
//

import AuralisPrimaryModels
import AuralisPrimaryPersistence
import Foundation
import NFTDomain
import NFTPersistence
import NFTProviderAdapters
import SwiftData

public enum NFTServiceRefreshPhase: Equatable {
    case idle
    case fetching
    case processingMetadata(itemCount: Int)
    case persisting(itemCount: Int)
    case cleaningUp(itemCount: Int)
}

@MainActor
@Observable
/// Coordinates NFT refresh work across fetching, metadata preparation, and SwiftData persistence.
public class NFTService {
    public typealias RefreshPhase = NFTServiceRefreshPhase

    private let nftFetcher: any NFTFetching
    private let fetchInventoryUseCase: any FetchNFTInventoryUsing
    private let prepareMetadataUseCase: any PrepareNFTMetadataUsing
    private let persistInventoryUseCase: any PersistNFTInventoryUsing
    private let refreshStateComputer: NFTRefreshStateComputer
    private let eventRecorderFactory: @MainActor (ModelContext) -> any NFTRefreshEventRecording

    public let refreshTTL: TimeInterval

    public private(set) var isLoading = false
    public private(set) var itemsLoaded: Int?
    public private(set) var total: Int?
    public private(set) var error: Error?
    public var providerFailure: NFTProviderFailure? { NFTProviderFailure(error: error) }

    public private(set) var refreshPhase: NFTServiceRefreshPhase = .idle
    private var inFlightRefreshScope: NFTRefreshScope?
    private var inFlightRefreshTask: Task<Void, Never>?
    private var inFlightRefreshToken: UUID?

    /// Creates the shared NFT orchestration service used by the shell.
    public init(
        nftFetcher: (any NFTFetching)? = nil,
        refreshTTL: TimeInterval = 300,
        fetchInventoryUseCase: (any FetchNFTInventoryUsing)? = nil,
        prepareMetadataUseCase: (any PrepareNFTMetadataUsing)? = nil,
        persistInventoryUseCase: (any PersistNFTInventoryUsing)? = nil,
        refreshStateComputer: NFTRefreshStateComputer? = nil,
        eventRecorderFactory: @escaping @MainActor (ModelContext) -> any NFTRefreshEventRecording = { _ in
            NoOpNFTRefreshEventRecorder()
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

    public func lastSuccessfulRefreshAt(
        for accountAddress: String?,
        chain: Chain
    ) -> Date? {
        refreshStateComputer.lastSuccessfulRefreshAt(
            for: accountAddress,
            chain: chain
        )
    }

    public func fetchAllNFTs(
        for accountAddress: String,
        chain: Chain,
        modelContext: ModelContext,
        correlationID: String
    ) async {
        refreshPhase = .fetching
        isLoading = true
        itemsLoaded = 0
        total = nil
        error = nil
        await Task.yield()
        let eventRecorder = eventRecorderFactory(modelContext)
        let modelContainer = modelContext.container

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
                eventRecorder: eventRecorder,
                progressHandler: { [weak self] progress in
                    await MainActor.run {
                        self?.itemsLoaded = progress.itemsLoaded
                        self?.total = progress.total
                    }
                }
            )
            try Task.checkCancellation()

            refreshPhase = .processingMetadata(itemCount: fetchedInventory.nfts.count)
            let preparedInventory = await prepareMetadataUseCase.prepareInventory(
                fetchedInventory.nfts,
                accountAddress: accountAddress,
                chain: chain
            )
            try Task.checkCancellation()

            do {
                refreshPhase = .persisting(itemCount: preparedInventory.nfts.count)
                await Task.yield()
                try Task.checkCancellation()

                try await persistInventoryUseCase.persist(
                    preparedInventory,
                    accountAddress: accountAddress,
                    chain: chain,
                    modelContainer: modelContainer
                )
                try Task.checkCancellation()

                if fetchedInventory.didCompleteFullRefresh {
                    refreshPhase = .cleaningUp(itemCount: preparedInventory.nfts.count)
                    await Task.yield()
                    try Task.checkCancellation()
                    try await persistInventoryUseCase.cleanupStaleInventory(
                        currentNFTIDs: preparedInventory.nfts.map(\.id),
                        accountAddress: accountAddress,
                        chain: chain,
                        modelContainer: modelContainer
                    )
                    try Task.checkCancellation()
                }

                if fetchedInventory.didCompleteFullRefresh {
                    refreshStateComputer.markRefreshSucceeded(
                        for: accountAddress,
                        chain: chain
                    )
                }
                await eventRecorder.recordPersistenceCompleted(
                    accountAddress: accountAddress,
                    chain: chain,
                    correlationID: correlationID,
                    persistedCount: preparedInventory.nfts.count
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                self.error = error
                await eventRecorder.recordPersistenceFailed(
                    accountAddress: accountAddress,
                    chain: chain,
                    correlationID: correlationID,
                    error: error
                )
                throw error
            }
        } catch is CancellationError {
            error = nil
        } catch {
            self.error = error
        }

        let terminalError = error
        isLoading = false
        itemsLoaded = nil
        total = nil
        refreshPhase = .idle
        if let terminalError {
            error = terminalError
        }
    }

    public func refreshNFTs(
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

    public func reset() {
        inFlightRefreshTask?.cancel()
        inFlightRefreshTask = nil
        inFlightRefreshScope = nil
        inFlightRefreshToken = nil
        isLoading = false
        itemsLoaded = nil
        total = nil
        error = nil
        refreshStateComputer.reset()
    }

    public func providerFailurePresentation(
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
