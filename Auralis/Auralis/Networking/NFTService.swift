//
//  NFTService.swift
//  Auralis
//
//  Created by Daniel Bell on 6/29/25.
//

import Foundation
import OSLog
import SwiftData

@ModelActor
private actor NFTRefreshPersistenceStore {
    struct NFTSnapshot: Sendable {
        struct ContractSnapshot: Sendable {
            let address: String?
            let chain: Chain
        }

        struct CollectionSnapshot: Sendable {
            let name: String?
            let chain: Chain
            let contractAddress: String?
        }

        struct ImageSnapshot: Sendable {
            let originalURL: String?
            let thumbnailURL: String?
            let secureURL: String?
        }

        struct RawSnapshot: Sendable {
            let tokenURI: String?
            let metadata: [String: JSONValue]?
            let error: String?
        }

        struct AcquiredAtSnapshot: Sendable {
            let blockTimestamp: String?
        }

        struct AttributeSnapshot: Sendable {
            let value: String
            let traitType: String?
        }

        let id: String
        let contract: ContractSnapshot
        let tokenId: String
        let tokenType: String?
        let name: String?
        let nftDescription: String?
        let image: ImageSnapshot?
        let raw: RawSnapshot?
        let collection: CollectionSnapshot?
        let tokenURI: String?
        let timeLastUpdated: String?
        let acquiredAt: AcquiredAtSnapshot?
        let network: Chain
        let accountAddress: String?
        let contentType: String?
        let collectionName: String?
        let artistName: String?
        let animationURL: String?
        let secureAnimationURL: String?
        let audioURL: String?
        let externalURL: String?
        let modelURL: String?
        let backgroundColor: String?
        let collectionID: String?
        let projectID: String?
        let series: String?
        let seriesID: String?
        let primaryAssetURL: String?
        let securePrimaryAssetURL: String?
        let previewAssetURL: String?
        let securePreviewAssetURL: String?
        let artistWebsite: String?
        let uniqueID: String?
        let timestamp: String?
        let tokenHash: String?
        let medium: String?
        let metadataVersion: String?
        let imageDataURL: String?
        let secureImageDataURL: String?
        let imageHrURL: String?
        let secureImageHrURL: String?
        let imageHash: String?
        let symbols: String?
        let seed: String?
        let original: String?
        let agreement: String?
        let website: String?
        let payoutAddress: String?
        let scriptType: String?
        let engineType: String?
        let accessArtworkFiles: String?
        let sellerFeeBasisPoints: Int?
        let minted: Int?
        let isStatic: Int?
        let aspectRatio: Double?
        let attributes: [AttributeSnapshot]
    }

    private struct PersistenceScopeSnapshot {
        var persistedNFTsByID: [String: NFT]
        var persistedContractsByID: [String: NFT.Contract]
        var persistedCollectionsByID: [String: NFT.Collection]
    }

    func persist(
        _ snapshots: [NFTSnapshot],
        accountAddress: String,
        chain: Chain
    ) throws {
        var snapshot = try makePersistenceScopeSnapshot(
            accountAddress: accountAddress,
            chain: chain
        )

        let nfts = snapshots.map(makeNFT(from:))
        canonicalizePersistenceScope(for: nfts, snapshot: &snapshot)
        for nft in nfts {
            upsert(nft: nft, snapshot: &snapshot)
        }
        try modelContext.save()
    }

    func cleanupOldNFTs(
        currentNFTIDs: [String],
        accountAddress: String,
        chain: Chain
    ) throws {
        let snapshot = try makePersistenceScopeSnapshot(
            accountAddress: accountAddress,
            chain: chain
        )
        try deleteStaleNFTs(
            currentNFTIDs: currentNFTIDs,
            stalePersistedNFTs: Array(snapshot.persistedNFTsByID.values)
        )
    }

    private func deleteStaleNFTs(
        currentNFTIDs: [String],
        stalePersistedNFTs: [NFT]
    ) throws {
        let currentNFTIDSet = Set(currentNFTIDs)
        for nft in stalePersistedNFTs where !currentNFTIDSet.contains(nft.id) {
            modelContext.delete(nft)
        }
        try modelContext.save()
    }

    private func makePersistenceScopeSnapshot(
        accountAddress: String,
        chain: Chain
    ) throws -> PersistenceScopeSnapshot {
        let normalizedAccountAddress = NFT.normalizedScopeComponent(accountAddress) ?? ""
        let scopedNFTDescriptor = FetchDescriptor<NFT>(
            predicate: #Predicate<NFT> {
                $0.accountAddressRawValue == normalizedAccountAddress &&
                $0.networkRawValue == chain.rawValue
            }
        )

        let persistedNFTs = try modelContext.fetch(scopedNFTDescriptor)
        let persistedContracts = try modelContext.fetch(FetchDescriptor<NFT.Contract>())
        let persistedCollections = try modelContext.fetch(FetchDescriptor<NFT.Collection>())

        return PersistenceScopeSnapshot(
            persistedNFTsByID: Dictionary(uniqueKeysWithValues: persistedNFTs.map { ($0.id, $0) }),
            persistedContractsByID: Dictionary(uniqueKeysWithValues: persistedContracts.map { ($0.id, $0) }),
            persistedCollectionsByID: Dictionary(uniqueKeysWithValues: persistedCollections.map { ($0.id, $0) })
        )
    }

    private func canonicalizePersistenceScope(
        for nfts: [NFT],
        snapshot: inout PersistenceScopeSnapshot
    ) {
        for nft in nfts {
            let resolvedContract = resolveContract(
                for: nft.contract,
                snapshot: &snapshot
            )
            nft.contract = resolvedContract

            if let collection = nft.collection {
                let resolvedCollection = resolveCollection(
                    for: collection,
                    snapshot: &snapshot
                )
                nft.collection = resolvedCollection
            }
        }
    }

    private func upsert(
        nft incomingNFT: NFT,
        snapshot: inout PersistenceScopeSnapshot
    ) {
        if let persistedNFT = snapshot.persistedNFTsByID[incomingNFT.id] {
            merge(into: persistedNFT, from: incomingNFT)
            return
        }

        modelContext.insert(incomingNFT)
        snapshot.persistedNFTsByID[incomingNFT.id] = incomingNFT
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
        // Tags are local user state, not provider-owned refresh data.
    }

    private func resolveContract(
        for contract: NFT.Contract,
        snapshot: inout PersistenceScopeSnapshot
    ) -> NFT.Contract {
        if let cachedContract = snapshot.persistedContractsByID[contract.id] {
            cachedContract.address = contract.address
            cachedContract.chainRawValue = contract.chainRawValue
            return cachedContract
        }

        snapshot.persistedContractsByID[contract.id] = contract
        return contract
    }

    private func resolveCollection(
        for collection: NFT.Collection,
        snapshot: inout PersistenceScopeSnapshot
    ) -> NFT.Collection {
        if let cachedCollection = snapshot.persistedCollectionsByID[collection.id] {
            cachedCollection.name = collection.name
            cachedCollection.chainRawValue = collection.chainRawValue
            cachedCollection.contractAddress = collection.contractAddress
            return cachedCollection
        }

        snapshot.persistedCollectionsByID[collection.id] = collection
        return collection
    }

    private func makeNFT(from snapshot: NFTSnapshot) -> NFT {
        let nft = NFT(
            id: snapshot.id,
            contract: NFT.Contract(address: snapshot.contract.address, chain: snapshot.contract.chain),
            tokenId: snapshot.tokenId,
            tokenType: snapshot.tokenType,
            name: snapshot.name,
            nftDescription: snapshot.nftDescription,
            image: snapshot.image.map {
                let image = NFT.Image(originalUrl: $0.originalURL, thumbnailUrl: $0.thumbnailURL)
                image.secureUrl = $0.secureURL
                return image
            },
            raw: snapshot.raw.map {
                let raw = NFT.Raw(tokenUri: $0.tokenURI, metadata: $0.metadata)
                raw.error = $0.error
                return raw
            },
            collection: snapshot.collection.map {
                NFT.Collection(
                    name: $0.name,
                    chain: $0.chain,
                    contractAddress: $0.contractAddress
                )
            },
            tokenUri: snapshot.tokenURI,
            timeLastUpdated: snapshot.timeLastUpdated,
            acquiredAt: snapshot.acquiredAt.map { NFT.AcquiredAt(blockTimestamp: $0.blockTimestamp) },
            network: snapshot.network,
            accountAddress: snapshot.accountAddress,
            contentType: snapshot.contentType,
            collectionName: snapshot.collectionName,
            artistName: snapshot.artistName,
            animationUrl: snapshot.animationURL,
            secureAnimationUrl: snapshot.secureAnimationURL,
            audioUrl: snapshot.audioURL
        )
        nft.externalUrl = snapshot.externalURL
        nft.modelUrl = snapshot.modelURL
        nft.backgroundColor = snapshot.backgroundColor
        nft.collectionID = snapshot.collectionID
        nft.projectID = snapshot.projectID
        nft.series = snapshot.series
        nft.seriesID = snapshot.seriesID
        nft.primaryAssetUrl = snapshot.primaryAssetURL
        nft.securePrimaryAssetUrl = snapshot.securePrimaryAssetURL
        nft.previewAssetUrl = snapshot.previewAssetURL
        nft.securePreviewAssetUrl = snapshot.securePreviewAssetURL
        nft.artistWebsite = snapshot.artistWebsite
        nft.uniqueID = snapshot.uniqueID
        nft.timestamp = snapshot.timestamp
        nft.tokenHash = snapshot.tokenHash
        nft.medium = snapshot.medium
        nft.metadataVersion = snapshot.metadataVersion
        nft.imageDataUrl = snapshot.imageDataURL
        nft.secureImageDataUrl = snapshot.secureImageDataURL
        nft.imageHrUrl = snapshot.imageHrURL
        nft.secureImageHrUrl = snapshot.secureImageHrURL
        nft.imageHash = snapshot.imageHash
        nft.symbols = snapshot.symbols
        nft.seed = snapshot.seed
        nft.original = snapshot.original
        nft.agreement = snapshot.agreement
        nft.website = snapshot.website
        nft.payoutAddress = snapshot.payoutAddress
        nft.scriptType = snapshot.scriptType
        nft.engineType = snapshot.engineType
        nft.accessArtworkFiles = snapshot.accessArtworkFiles
        nft.sellerFeeBasisPoints = snapshot.sellerFeeBasisPoints
        nft.minted = snapshot.minted
        nft.isStatic = snapshot.isStatic
        nft.aspectRatio = snapshot.aspectRatio
        nft.attributes = snapshot.attributes.map {
            NFT.Attribute(value: $0.value, traitType: $0.traitType)
        }
        return nft
    }
}

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

    private struct RefreshScope: Hashable {
        let accountAddress: String
        let chain: Chain
    }

    private struct MetadataPreparationInput: Sendable {
        let tokenURI: String?
        let rawTokenURI: String?
        let rawMetadata: [String: JSONValue]?
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
    private var successfulRefreshTimestamps: [RefreshScope: Date] = [:]
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

    func lastSuccessfulRefreshAt(
        for accountAddress: String?,
        chain: Chain
    ) -> Date? {
        guard let refreshScope = refreshScope(
            accountAddress: accountAddress,
            chain: chain
        ) else {
            return nil
        }

        return successfulRefreshTimestamps[refreshScope]
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
            let nfts = await prepareFetchedNFTs(
                fetchedNFTs,
                accountAddress: accountAddress,
                chain: chain
            )

            do {
                refreshPhase = .persisting(itemCount: nfts.count)
                await Task.yield()
                let didCompleteFullRefresh = nftFetcher.currentCursor == nil &&
                    (nftFetcher.total == nil || (nftFetcher.itemsLoaded ?? 0) >= (nftFetcher.total ?? 0))
                let persistenceStore = NFTRefreshPersistenceStore(modelContainer: modelContext.container)
                let persistenceSnapshots = nfts.map(makePersistenceSnapshot(from:))

                try await persistenceStore.persist(
                    persistenceSnapshots,
                    accountAddress: accountAddress,
                    chain: chain
                )

                if didCompleteFullRefresh {
                    refreshPhase = .cleaningUp(itemCount: nfts.count)
                    await Task.yield()
                    try await persistenceStore.cleanupOldNFTs(
                        currentNFTIDs: nfts.map(\.id),
                        accountAddress: accountAddress,
                        chain: chain
                    )
                }

                successfulRefreshTimestamps[
                    RefreshScope(accountAddress: accountAddress, chain: chain)
                ] = .now
                await eventRecorder.recordPersistenceCompleted(
                    accountAddress: accountAddress,
                    chain: chain,
                    correlationID: correlationID,
                    persistedCount: nfts.count
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

        guard let requestedScope = refreshScope(
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

    private func deduplicateFetchedNFTs(_ nfts: [NFT]) -> [NFT] {
        var seenIDs = Set<String>()
        var deduplicatedNFTs: [NFT] = []
        deduplicatedNFTs.reserveCapacity(nfts.count)

        for nft in nfts where seenIDs.insert(nft.id).inserted {
            deduplicatedNFTs.append(nft)
        }

        return deduplicatedNFTs
    }

    private func prepareFetchedNFTs(
        _ fetchedNFTs: [NFT],
        accountAddress: String,
        chain: Chain
    ) async -> [NFT] {
        let metadataPatches = await prepareMetadataPatches(for: fetchedNFTs)

        for (index, nft) in fetchedNFTs.enumerated() {
            nft.applyRefreshScope(accountAddress: accountAddress, chain: chain)
            if let metadataPatch = metadataPatches[index] {
                NFTMetadataUpdater.applyMetadataPatch(metadataPatch, to: nft)
                nft.applyRefreshScope(accountAddress: accountAddress, chain: chain)
            }

            if index.isMultiple(of: 25) {
                await Task.yield()
            }
        }

        return deduplicateFetchedNFTs(fetchedNFTs)
    }

    private func refreshScope(
        accountAddress: String?,
        chain: Chain
    ) -> RefreshScope? {
        guard let normalizedAccountAddress = NFT.normalizedScopeComponent(accountAddress) else {
            return nil
        }

        return RefreshScope(accountAddress: normalizedAccountAddress, chain: chain)
    }

    private func prepareMetadataPatches(
        for fetchedNFTs: [NFT]
    ) async -> [NFTMetadataUpdater.MetadataPatch?] {
        let inputs = fetchedNFTs.map {
            MetadataPreparationInput(
                tokenURI: $0.tokenUri,
                rawTokenURI: $0.raw?.tokenUri,
                rawMetadata: $0.raw?.metadata
            )
        }

        return await Task.detached(priority: .userInitiated) {
            inputs.map { input in
                let tokenURIs = Set([input.tokenURI, input.rawTokenURI].compactMap(\.self))
                let siftedTokenURIs = tokenURIs.siftTokenURIs()

                guard !siftedTokenURIs.isEmpty else {
                    return nil
                }

                if let decodedTokenURI = siftedTokenURIs.lazy.compactMap(\.base64JSON).first {
                    return NFTMetadataUpdater.metadataPatch(from: decodedTokenURI)
                }

                return NFTMetadataUpdater.metadataPatch(from: input.rawMetadata)
            }
        }.value
    }

    private func makePersistenceSnapshot(from nft: NFT) -> NFTRefreshPersistenceStore.NFTSnapshot {
        NFTRefreshPersistenceStore.NFTSnapshot(
            id: nft.id,
            contract: .init(
                address: nft.contract.address,
                chain: Chain(rawValue: nft.contract.chainRawValue) ?? .ethMainnet
            ),
            tokenId: nft.tokenId,
            tokenType: nft.tokenType,
            name: nft.name,
            nftDescription: nft.nftDescription,
            image: nft.image.map {
                .init(
                    originalURL: $0.originalUrl,
                    thumbnailURL: $0.thumbnailUrl,
                    secureURL: $0.secureUrl
                )
            },
            raw: nft.raw.map {
                .init(
                    tokenURI: $0.tokenUri,
                    metadata: $0.metadata,
                    error: $0.error
                )
            },
            collection: nft.collection.map {
                .init(
                    name: $0.name,
                    chain: Chain(rawValue: $0.chainRawValue) ?? .ethMainnet,
                    contractAddress: $0.contractAddress
                )
            },
            tokenURI: nft.tokenUri,
            timeLastUpdated: nft.timeLastUpdated,
            acquiredAt: nft.acquiredAt.map { .init(blockTimestamp: $0.blockTimestamp) },
            network: Chain(rawValue: nft.networkRawValue) ?? .ethMainnet,
            accountAddress: nft.accountAddress,
            contentType: nft.contentType,
            collectionName: nft.collectionName,
            artistName: nft.artistName,
            animationURL: nft.animationUrl,
            secureAnimationURL: nft.secureAnimationUrl,
            audioURL: nft.audioUrl,
            externalURL: nft.externalUrl,
            modelURL: nft.modelUrl,
            backgroundColor: nft.backgroundColor,
            collectionID: nft.collectionID,
            projectID: nft.projectID,
            series: nft.series,
            seriesID: nft.seriesID,
            primaryAssetURL: nft.primaryAssetUrl,
            securePrimaryAssetURL: nft.securePrimaryAssetUrl,
            previewAssetURL: nft.previewAssetUrl,
            securePreviewAssetURL: nft.securePreviewAssetUrl,
            artistWebsite: nft.artistWebsite,
            uniqueID: nft.uniqueID,
            timestamp: nft.timestamp,
            tokenHash: nft.tokenHash,
            medium: nft.medium,
            metadataVersion: nft.metadataVersion,
            imageDataURL: nft.imageDataUrl,
            secureImageDataURL: nft.secureImageDataUrl,
            imageHrURL: nft.imageHrUrl,
            secureImageHrURL: nft.secureImageHrUrl,
            imageHash: nft.imageHash,
            symbols: nft.symbols,
            seed: nft.seed,
            original: nft.original,
            agreement: nft.agreement,
            website: nft.website,
            payoutAddress: nft.payoutAddress,
            scriptType: nft.scriptType,
            engineType: nft.engineType,
            accessArtworkFiles: nft.accessArtworkFiles,
            sellerFeeBasisPoints: nft.sellerFeeBasisPoints,
            minted: nft.minted,
            isStatic: nft.isStatic,
            aspectRatio: nft.aspectRatio,
            attributes: (nft.attributes ?? []).map {
                .init(value: $0.value, traitType: $0.traitType)
            }
        )
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
