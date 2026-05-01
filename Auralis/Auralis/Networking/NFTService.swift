//
//  NFTService.swift
//  Auralis
//
//  Created by Daniel Bell on 6/29/25.
//

import Foundation
import OSLog
import SwiftData

// SwiftLint currently misclassifies these file-scope snapshot helpers as overly nested.
private struct NFTRefreshContractSnapshot: Sendable {
    let address: String?
    let chain: Chain
}

private struct NFTRefreshCollectionSnapshot: Sendable {
    let name: String?
    let chain: Chain
    let contractAddress: String?
}

private struct NFTRefreshImageSnapshot: Sendable {
    let originalURL: String?
    let thumbnailURL: String?
    let secureURL: String?
}

private struct NFTRefreshRawSnapshot: Sendable {
    let tokenURI: String?
    let metadata: [String: JSONValue]?
    let error: String?
}

private struct NFTRefreshAcquiredAtSnapshot: Sendable {
    let blockTimestamp: String?
}

private struct NFTRefreshAttributeSnapshot: Sendable {
    let value: String
    let traitType: String?
}

private struct NFTRefreshPersistenceSnapshot: Sendable {
    let id: String
    let contract: NFTRefreshContractSnapshot
    let tokenId: String
    let tokenType: String?
    let name: String?
    let nftDescription: String?
    let image: NFTRefreshImageSnapshot?
    let raw: NFTRefreshRawSnapshot?
    let collection: NFTRefreshCollectionSnapshot?
    let tokenURI: String?
    let timeLastUpdated: String?
    let acquiredAt: NFTRefreshAcquiredAtSnapshot?
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
    let attributes: [NFTRefreshAttributeSnapshot]
}

private struct NFTRefreshPersistenceScopeSnapshot {
    var persistedNFTsByID: [String: NFT]
    var persistedContractsByID: [String: NFT.Contract]
    var persistedCollectionsByID: [String: NFT.Collection]
    let owningAccount: EOAccount?
}

enum NFTServiceRefreshPhase: Equatable {
    case idle
    case fetching
    case processingMetadata(itemCount: Int)
    case persisting(itemCount: Int)
    case cleaningUp(itemCount: Int)
}

private struct NFTServiceRefreshScope: Hashable {
    let accountAddress: String
    let chain: Chain
}

private struct NFTMetadataPreparationInput: Sendable {
    let tokenURI: String?
    let rawTokenURI: String?
    let rawMetadata: [String: JSONValue]?
}

@ModelActor
private actor NFTRefreshPersistenceStore {
    func persist(
        _ snapshots: [NFTRefreshPersistenceSnapshot],
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
        synchronizeTrackedNFTCount(for: accountAddress)
        try modelContext.save()
        try pruneOrphanedSharedModels()
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
            stalePersistedNFTs: Array(snapshot.persistedNFTsByID.values),
            accountAddress: accountAddress
        )
    }

    private func deleteStaleNFTs(
        currentNFTIDs: [String],
        stalePersistedNFTs: [NFT],
        accountAddress: String
    ) throws {
        let currentNFTIDSet = Set(currentNFTIDs)
        for nft in stalePersistedNFTs where !currentNFTIDSet.contains(nft.id) {
            if nft.playlists.isEmpty {
                modelContext.delete(nft)
            } else {
                nft.archiveForPlaylistRetention()
            }
        }
        synchronizeTrackedNFTCount(for: accountAddress)
        try modelContext.save()
        try pruneOrphanedSharedModels()
    }

    private func makePersistenceScopeSnapshot(
        accountAddress: String,
        chain: Chain
    ) throws -> NFTRefreshPersistenceScopeSnapshot {
        let normalizedAccountAddress = NFT.normalizedScopeComponent(accountAddress) ?? ""
        let scopedNFTDescriptor = FetchDescriptor<NFT>(
            predicate: #Predicate<NFT> {
                $0.accountAddressRawValue == normalizedAccountAddress &&
                $0.networkRawValue == chain.rawValue
            }
        )
        let scopedContractDescriptor = FetchDescriptor<NFT.Contract>(
            predicate: #Predicate<NFT.Contract> { contract in
                contract.chainRawValue == chain.rawValue
            }
        )
        let scopedCollectionDescriptor = FetchDescriptor<NFT.Collection>(
            predicate: #Predicate<NFT.Collection> { collection in
                collection.chainRawValue == chain.rawValue
            }
        )

        let persistedNFTs = try modelContext.fetch(scopedNFTDescriptor)
        let persistedContracts = try modelContext.fetch(scopedContractDescriptor)
        let persistedCollections = try modelContext.fetch(scopedCollectionDescriptor)

        return NFTRefreshPersistenceScopeSnapshot(
            persistedNFTsByID: Dictionary(uniqueKeysWithValues: persistedNFTs.map { ($0.id, $0) }),
            persistedContractsByID: Dictionary(uniqueKeysWithValues: persistedContracts.map { ($0.id, $0) }),
            persistedCollectionsByID: Dictionary(uniqueKeysWithValues: persistedCollections.map { ($0.id, $0) }),
            owningAccount: try modelContext.fetch(
                FetchDescriptor<EOAccount>(
                    predicate: #Predicate<EOAccount> { account in
                        account.address == normalizedAccountAddress
                    }
                )
            ).first
        )
    }

    private func synchronizeTrackedNFTCount(for accountAddress: String) {
        guard let normalizedAccountAddress = NFT.normalizedScopeComponent(accountAddress) else {
            return
        }

        let accountDescriptor = FetchDescriptor<EOAccount>(
            predicate: #Predicate<EOAccount> { account in
                account.address == normalizedAccountAddress
            }
        )
        let nftDescriptor = FetchDescriptor<NFT>(
            predicate: #Predicate<NFT> { nft in
                nft.accountAddressRawValue == normalizedAccountAddress
            }
        )

        guard let account = try? modelContext.fetch(accountDescriptor).first,
              let trackedNFTCount = try? modelContext.fetchCount(nftDescriptor) else {
            return
        }

        if account.trackedNFTCount != trackedNFTCount {
            account.trackedNFTCount = trackedNFTCount
        }
    }

    private func canonicalizePersistenceScope(
        for nfts: [NFT],
        snapshot: inout NFTRefreshPersistenceScopeSnapshot
    ) {
        for nft in nfts {
            nft.assignOwnership(to: snapshot.owningAccount)
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
        snapshot: inout NFTRefreshPersistenceScopeSnapshot
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
        persistedNFT.account = incomingNFT.account
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
        snapshot: inout NFTRefreshPersistenceScopeSnapshot
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
        snapshot: inout NFTRefreshPersistenceScopeSnapshot
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

    private func pruneOrphanedSharedModels() throws {
        let allNFTs = try modelContext.fetch(FetchDescriptor<NFT>())
        let referencedContractIDs = Set(allNFTs.map(\.contract.id))
        let referencedCollectionIDs = Set(allNFTs.compactMap(\.collection?.id))

        // Contracts and collections remain shared models. NFT-owned children
        // such as image/raw/acquiredAt now clean themselves up through cascade.
        let persistedContracts = try modelContext.fetch(FetchDescriptor<NFT.Contract>())
        for contract in persistedContracts where !referencedContractIDs.contains(contract.id) {
            modelContext.delete(contract)
        }

        let persistedCollections = try modelContext.fetch(FetchDescriptor<NFT.Collection>())
        for collection in persistedCollections where !referencedCollectionIDs.contains(collection.id) {
            modelContext.delete(collection)
        }

        try modelContext.save()
    }

    private func makeNFT(from snapshot: NFTRefreshPersistenceSnapshot) -> NFT {
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
/// Coordinates NFT refresh work across fetching, metadata preparation, and SwiftData persistence.
class NFTService {
    private let logger = Logger(subsystem: "Auralis", category: "NFTService")
    typealias RefreshPhase = NFTServiceRefreshPhase
    private let nftFetcher: any NFTFetching
    private let eventRecorderFactory: @MainActor (ModelContext) -> any NFTRefreshEventRecording
    let refreshTTL: TimeInterval
    var isLoading: Bool { nftFetcher.loading }
    var itemsLoaded: Int? { nftFetcher.itemsLoaded }
    var total: Int? { nftFetcher.total }
    var error: Error? { nftFetcher.error }
    var providerFailure: NFTProviderFailure? { NFTProviderFailure(error: error) }
    private(set) var refreshPhase: NFTServiceRefreshPhase = .idle
    private var successfulRefreshTimestamps: [NFTServiceRefreshScope: Date] = [:]
    private var inFlightRefreshScope: NFTServiceRefreshScope?
    private var inFlightRefreshTask: Task<Void, Never>?
    private var inFlightRefreshToken: UUID?

    /// Creates the shared NFT orchestration service used by the shell.
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
                let persistenceSnapshots = nfts.map {
                    makePersistenceSnapshot(from: $0, scopeChain: chain)
                }

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
                    NFTServiceRefreshScope(accountAddress: accountAddress, chain: chain)
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
    ) -> NFTServiceRefreshScope? {
        guard let normalizedAccountAddress = NFT.normalizedScopeComponent(accountAddress) else {
            return nil
        }

        return NFTServiceRefreshScope(accountAddress: normalizedAccountAddress, chain: chain)
    }

    private func prepareMetadataPatches(
        for fetchedNFTs: [NFT]
    ) async -> [NFTMetadataUpdater.MetadataPatch?] {
        let inputs = fetchedNFTs.map {
            NFTMetadataPreparationInput(
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

    private func makePersistenceSnapshot(
        from nft: NFT,
        scopeChain: Chain
    ) -> NFTRefreshPersistenceSnapshot {
        NFTRefreshPersistenceSnapshot(
            id: nft.id,
            contract: .init(
                address: nft.contract.address,
                chain: scopeChain
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
                    chain: scopeChain,
                    contractAddress: $0.contractAddress
                )
            },
            tokenURI: nft.tokenUri,
            timeLastUpdated: nft.timeLastUpdated,
            acquiredAt: nft.acquiredAt.map { .init(blockTimestamp: $0.blockTimestamp) },
            network: scopeChain,
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
