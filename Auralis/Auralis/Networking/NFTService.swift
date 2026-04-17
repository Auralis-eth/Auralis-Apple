//
//  NFTService.swift
//  Auralis
//
//  Created by Daniel Bell on 6/29/25.
//

import Foundation
import OSLog
import SwiftData

@MainActor
@Observable
class NFTService {
    private let logger = Logger(subsystem: "Auralis", category: "NFTService")
    enum RefreshPhase: Equatable {
        case idle
        case fetching
        case processingMetadata(itemCount: Int)
        case persisting(itemCount: Int)
        case cleaningUp(itemCount: Int)
    }

    private struct RefreshScope: Equatable {
        let accountAddress: String
        let chain: Chain
    }

    private let nftFetcher: any NFTFetching
    private let eventRecorderFactory: @MainActor (ModelContext) -> any NFTRefreshEventRecording
    let refreshTTL: TimeInterval
    var isLoading: Bool { nftFetcher.loading }
    var itemsLoaded: Int? { nftFetcher.itemsLoaded }
    var total: Int? { nftFetcher.total }
    var error: Error? { nftFetcher.error }
    var providerFailure: NFTProviderFailure? { NFTProviderFailure(error: error) }
    private(set) var refreshPhase: RefreshPhase = .idle
    var lastSuccessfulRefreshAt: Date?
    private var inFlightRefreshScope: RefreshScope?
    private var inFlightRefreshTask: Task<Void, Never>?
    private var inFlightRefreshToken: UUID?

    init(
        nftFetcher: (any NFTFetching)? = nil,
        refreshTTL: TimeInterval = 300,
        eventRecorderFactory: @escaping @MainActor (ModelContext) -> any NFTRefreshEventRecording = {
            NFTRefreshEventRecorders.live(modelContext: $0)
        }
    ) {
        self.nftFetcher = nftFetcher ?? NFTFetcher()
        self.refreshTTL = refreshTTL
        self.eventRecorderFactory = eventRecorderFactory
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
            let fetchedNFTs = try await nftFetcher.fetchAllNFTs(
                for: accountAddress,
                chain: chain,
                correlationID: correlationID,
                eventRecorder: eventRecorder
            )

            refreshPhase = .processingMetadata(itemCount: fetchedNFTs.count)
            await Task.yield()
            fetchedNFTs.forEach {
                $0.applyRefreshScope(accountAddress: accountAddress, chain: chain)
                $0.parseMetadata()
            }
            let nfts = deduplicateFetchedNFTs(fetchedNFTs)

            do {
                refreshPhase = .persisting(itemCount: nfts.count)
                await Task.yield()
                try canonicalizePersistenceScope(for: nfts, modelContext: modelContext)
                for nft in nfts {
                    try reusePersistedRelationships(for: nft, modelContext: modelContext)
                    try upsert(nft: nft, modelContext: modelContext)
                }
                try modelContext.save()

                let didCompleteFullRefresh = nftFetcher.currentCursor == nil &&
                    (nftFetcher.total == nil || (nftFetcher.itemsLoaded ?? 0) >= (nftFetcher.total ?? 0))

                if didCompleteFullRefresh {
                    refreshPhase = .cleaningUp(itemCount: nfts.count)
                    await Task.yield()
                    try await cleanupOldNFTs(
                        currentNFTIDs: nfts.map(\.id),
                        modelContext: modelContext,
                        accountAddress: accountAddress,
                        chain: chain,
                        correlationID: correlationID,
                        eventRecorder: eventRecorder
                    )
                } else if let currentCursor = nftFetcher.currentCursor {
                    UserDefaults.standard.set(currentCursor, forKey: "currentCursor")
                }

                lastSuccessfulRefreshAt = .now
                await eventRecorder.recordPersistenceCompleted(
                    accountAddress: accountAddress,
                    chain: chain,
                    correlationID: correlationID,
                    persistedCount: nfts.count
                )
            } catch {
                modelContext.rollback()
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

        let requestedScope = RefreshScope(accountAddress: accountAddress, chain: chain)

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

    private func cleanupOldNFTs(
        currentNFTIDs: [String],
        modelContext: ModelContext,
        accountAddress: String,
        chain: Chain,
        correlationID: String,
        eventRecorder: any NFTRefreshEventRecording
    ) async throws {
        let currentNFTIDSet = Set(currentNFTIDs)
        do {
            let persistedNFTs = try modelContext.fetch(FetchDescriptor<NFT>())
            for nft in persistedNFTs
            where nft.matchesScope(accountAddress: accountAddress, chain: chain) &&
                !currentNFTIDSet.contains(nft.id) {
                modelContext.delete(nft)
            }
            try modelContext.save()
        } catch {
            logger.error("Failed to cleanup old NFTs from SwiftData: \(error.localizedDescription, privacy: .public)")
            nftFetcher.error = error
            await eventRecorder.recordPersistenceFailed(
                accountAddress: accountAddress,
                chain: chain,
                correlationID: correlationID,
                error: error
            )
            throw error
        }
    }

    private func reusePersistedRelationships(
        for nft: NFT,
        modelContext: ModelContext
    ) throws {
        let contractID = nft.contract.id
        let contractDescriptor = FetchDescriptor<NFT.Contract>(
            predicate: #Predicate<NFT.Contract> { $0.id == contractID }
        )
        if let persistedContract = try modelContext.fetch(contractDescriptor).first {
            nft.contract = persistedContract
        }

        if let collection = nft.collection {
            let collectionID = collection.id
            let collectionDescriptor = FetchDescriptor<NFT.Collection>(
                predicate: #Predicate<NFT.Collection> { $0.id == collectionID }
            )
            if let persistedCollection = try modelContext.fetch(collectionDescriptor).first {
                nft.collection = persistedCollection
            }
        }
    }

    private func canonicalizePersistenceScope(
        for nfts: [NFT],
        modelContext: ModelContext
    ) throws {
        var contractsByID: [String: NFT.Contract] = [:]
        var collectionsByID: [String: NFT.Collection] = [:]

        for nft in nfts {
            let resolvedContract = try resolveContract(
                for: nft.contract,
                modelContext: modelContext,
                cache: &contractsByID
            )
            nft.contract = resolvedContract

            if let collection = nft.collection {
                let resolvedCollection = try resolveCollection(
                    for: collection,
                    modelContext: modelContext,
                    cache: &collectionsByID
                )
                nft.collection = resolvedCollection
            }
        }
    }

    private func deduplicateFetchedNFTs(_ nfts: [NFT]) -> [NFT] {
        var seenIDs = Set<String>()
        var deduplicatedNFTs: [NFT] = []
        deduplicatedNFTs.reserveCapacity(nfts.count)

        for nft in nfts where seenIDs.insert(nft.id).inserted {
            deduplicatedNFTs.append(nft)
        }

        return deduplicatedNFTs
    }

    private func upsert(
        nft incomingNFT: NFT,
        modelContext: ModelContext
    ) throws {
        let descriptor = FetchDescriptor<NFT>(
            predicate: #Predicate<NFT> { $0.id == incomingNFT.id }
        )

        if let persistedNFT = try modelContext.fetch(descriptor).first {
            merge(into: persistedNFT, from: incomingNFT)
            return
        }

        modelContext.insert(incomingNFT)
    }

    private func merge(
        into persistedNFT: NFT,
        from incomingNFT: NFT
    ) {
        persistedNFT.id = incomingNFT.id
        persistedNFT.contract = incomingNFT.contract
        persistedNFT.tokenId = incomingNFT.tokenId
        persistedNFT.tokenType = incomingNFT.tokenType
        persistedNFT.name = incomingNFT.name
        persistedNFT.nftDescription = incomingNFT.nftDescription
        persistedNFT.image = incomingNFT.image
        persistedNFT.raw = incomingNFT.raw
        persistedNFT.collection = incomingNFT.collection
        persistedNFT.tokenUri = incomingNFT.tokenUri
        persistedNFT.timeLastUpdated = incomingNFT.timeLastUpdated
        persistedNFT.acquiredAt = incomingNFT.acquiredAt
        persistedNFT.networkRawValue = incomingNFT.networkRawValue
        persistedNFT.accountAddressRawValue = incomingNFT.accountAddressRawValue
        persistedNFT.contentType = incomingNFT.contentType
        persistedNFT.collectionName = incomingNFT.collectionName
        persistedNFT.artistName = incomingNFT.artistName
        persistedNFT.animationUrl = incomingNFT.animationUrl
        persistedNFT.secureAnimationUrl = incomingNFT.secureAnimationUrl
        persistedNFT.audioUrl = incomingNFT.audioUrl
        persistedNFT.externalUrl = incomingNFT.externalUrl
        persistedNFT.modelUrl = incomingNFT.modelUrl
        persistedNFT.backgroundColor = incomingNFT.backgroundColor
        persistedNFT.collectionID = incomingNFT.collectionID
        persistedNFT.projectID = incomingNFT.projectID
        persistedNFT.series = incomingNFT.series
        persistedNFT.seriesID = incomingNFT.seriesID
        persistedNFT.primaryAssetUrl = incomingNFT.primaryAssetUrl
        persistedNFT.securePrimaryAssetUrl = incomingNFT.securePrimaryAssetUrl
        persistedNFT.previewAssetUrl = incomingNFT.previewAssetUrl
        persistedNFT.securePreviewAssetUrl = incomingNFT.securePreviewAssetUrl
        persistedNFT.artistWebsite = incomingNFT.artistWebsite
        persistedNFT.uniqueID = incomingNFT.uniqueID
        persistedNFT.timestamp = incomingNFT.timestamp
        persistedNFT.tokenHash = incomingNFT.tokenHash
        persistedNFT.medium = incomingNFT.medium
        persistedNFT.metadataVersion = incomingNFT.metadataVersion
        persistedNFT.imageDataUrl = incomingNFT.imageDataUrl
        persistedNFT.secureImageDataUrl = incomingNFT.secureImageDataUrl
        persistedNFT.imageHrUrl = incomingNFT.imageHrUrl
        persistedNFT.secureImageHrUrl = incomingNFT.secureImageHrUrl
        persistedNFT.imageHash = incomingNFT.imageHash
        persistedNFT.symbols = incomingNFT.symbols
        persistedNFT.seed = incomingNFT.seed
        persistedNFT.original = incomingNFT.original
        persistedNFT.agreement = incomingNFT.agreement
        persistedNFT.website = incomingNFT.website
        persistedNFT.payoutAddress = incomingNFT.payoutAddress
        persistedNFT.scriptType = incomingNFT.scriptType
        persistedNFT.engineType = incomingNFT.engineType
        persistedNFT.accessArtworkFiles = incomingNFT.accessArtworkFiles
        persistedNFT.sellerFeeBasisPoints = incomingNFT.sellerFeeBasisPoints
        persistedNFT.minted = incomingNFT.minted
        persistedNFT.isStatic = incomingNFT.isStatic
        persistedNFT.aspectRatio = incomingNFT.aspectRatio
        persistedNFT.attributes = incomingNFT.attributes
        persistedNFT.tags = incomingNFT.tags
    }

    private func resolveContract(
        for contract: NFT.Contract,
        modelContext: ModelContext,
        cache: inout [String: NFT.Contract]
    ) throws -> NFT.Contract {
        if let cachedContract = cache[contract.id] {
            cachedContract.address = contract.address
            cachedContract.chainRawValue = contract.chainRawValue
            return cachedContract
        }

        let descriptor = FetchDescriptor<NFT.Contract>(
            predicate: #Predicate<NFT.Contract> { $0.id == contract.id }
        )

        if let persistedContract = try modelContext.fetch(descriptor).first {
            persistedContract.address = contract.address
            persistedContract.chainRawValue = contract.chainRawValue
            cache[contract.id] = persistedContract
            return persistedContract
        }

        cache[contract.id] = contract
        return contract
    }

    private func resolveCollection(
        for collection: NFT.Collection,
        modelContext: ModelContext,
        cache: inout [String: NFT.Collection]
    ) throws -> NFT.Collection {
        if let cachedCollection = cache[collection.id] {
            cachedCollection.name = collection.name
            cachedCollection.chainRawValue = collection.chainRawValue
            cachedCollection.contractAddress = collection.contractAddress
            return cachedCollection
        }

        let descriptor = FetchDescriptor<NFT.Collection>(
            predicate: #Predicate<NFT.Collection> { $0.id == collection.id }
        )

        if let persistedCollection = try modelContext.fetch(descriptor).first {
            persistedCollection.name = collection.name
            persistedCollection.chainRawValue = collection.chainRawValue
            persistedCollection.contractAddress = collection.contractAddress
            cache[collection.id] = persistedCollection
            return persistedCollection
        }

        cache[collection.id] = collection
        return collection
    }
    func reset() {
        inFlightRefreshTask?.cancel()
        inFlightRefreshTask = nil
        inFlightRefreshScope = nil
        inFlightRefreshToken = nil
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
