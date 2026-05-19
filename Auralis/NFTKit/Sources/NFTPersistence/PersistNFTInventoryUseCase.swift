//
//  PersistNFTInventoryUseCase.swift
//  Auralis
//
//  Created by Codex on 8/26/25.
//

import AuralisPrimaryModels
import AuralisPrimaryPersistence
import Foundation
import NFTDomain
import SwiftData

public struct PreparedNFTInventory {
    public let nfts: [NFTInventoryItemSnapshot]

    public init(nfts: [NFTInventoryItemSnapshot]) {
        self.nfts = nfts
    }
}

@MainActor
public protocol PersistNFTInventoryUsing {
    func persist(
        _ inventory: PreparedNFTInventory,
        accountAddress: String,
        chain: Chain,
        modelContext: ModelContext
    ) async throws

    func cleanupStaleInventory(
        currentNFTIDs: [String],
        accountAddress: String,
        chain: Chain,
        modelContext: ModelContext
    ) async throws
}

@MainActor
public struct LivePersistNFTInventoryUseCase: PersistNFTInventoryUsing {
    public init() { }

    public func persist(
        _ inventory: PreparedNFTInventory,
        accountAddress: String,
        chain: Chain,
        modelContext: ModelContext
    ) async throws {
        let persistenceStore = NFTRefreshPersistenceStore(modelContainer: modelContext.container)
        let persistenceSnapshots = inventory.nfts.map {
            makePersistenceSnapshot(from: $0, scopeChain: chain)
        }

        try await persistenceStore.persist(
            persistenceSnapshots,
            accountAddress: accountAddress,
            chain: chain
        )
    }

    public func cleanupStaleInventory(
        currentNFTIDs: [String],
        accountAddress: String,
        chain: Chain,
        modelContext: ModelContext
    ) async throws {
        let persistenceStore = NFTRefreshPersistenceStore(modelContainer: modelContext.container)
        try await persistenceStore.cleanupOldNFTs(
            currentNFTIDs: currentNFTIDs,
            accountAddress: accountAddress,
            chain: chain
        )
    }

    private func makePersistenceSnapshot(
        from nft: NFTInventoryItemSnapshot,
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
                    originalURL: $0.originalURL,
                    thumbnailURL: $0.thumbnailURL,
                    secureURL: $0.secureURL
                )
            },
            raw: nft.raw.map {
                .init(
                    tokenURI: $0.tokenURI,
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
            tokenURI: nft.tokenURI,
            timeLastUpdated: nft.timeLastUpdated,
            acquiredAt: nft.acquiredAt.map { .init(blockTimestamp: $0.blockTimestamp) },
            network: scopeChain,
            accountAddress: nft.accountAddress,
            contentType: nft.contentType,
            collectionName: nft.collectionName,
            artistName: nft.artistName,
            animationURL: nft.animationURL,
            secureAnimationURL: nft.secureAnimationURL,
            audioURL: nft.audioURL,
            externalURL: nft.externalURL,
            modelURL: nft.modelURL,
            backgroundColor: nft.backgroundColor,
            collectionID: nft.collectionID,
            projectID: nft.projectID,
            series: nft.series,
            seriesID: nft.seriesID,
            primaryAssetURL: nft.primaryAssetURL,
            securePrimaryAssetURL: nft.securePrimaryAssetURL,
            previewAssetURL: nft.previewAssetURL,
            securePreviewAssetURL: nft.securePreviewAssetURL,
            artistWebsite: nft.artistWebsite,
            uniqueID: nft.uniqueID,
            timestamp: nft.timestamp,
            tokenHash: nft.tokenHash,
            medium: nft.medium,
            metadataVersion: nft.metadataVersion,
            imageDataURL: nft.imageDataURL,
            secureImageDataURL: nft.secureImageDataURL,
            imageHrURL: nft.imageHrURL,
            secureImageHrURL: nft.secureImageHrURL,
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
}

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

@ModelActor
private actor NFTRefreshPersistenceStore {
    func persist(
        _ snapshots: [NFTRefreshPersistenceSnapshot],
        accountAddress: String,
        chain: Chain
    ) throws {
        var persistenceScope = try makePersistenceScopeSnapshot(
            accountAddress: accountAddress,
            chain: chain
        )

        for snapshot in snapshots {
            let nft = makeNFT(
                from: snapshot,
                owningAccount: persistenceScope.owningAccount,
                snapshot: &persistenceScope
            )
            upsert(nft: nft, snapshot: &persistenceScope)
        }
        synchronizeTrackedNFTCount(for: accountAddress)
        try modelContext.save()
        try pruneOrphanedSharedModels(
            chain: chain,
            candidateContracts: Array(persistenceScope.persistedContractsByID.values),
            candidateCollections: Array(persistenceScope.persistedCollectionsByID.values)
        )
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
            accountAddress: accountAddress,
            chain: chain,
            candidateContracts: Array(snapshot.persistedContractsByID.values),
            candidateCollections: Array(snapshot.persistedCollectionsByID.values)
        )
    }

    private func deleteStaleNFTs(
        currentNFTIDs: [String],
        stalePersistedNFTs: [NFT],
        accountAddress: String,
        chain: Chain,
        candidateContracts: [NFT.Contract],
        candidateCollections: [NFT.Collection]
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
        try pruneOrphanedSharedModels(
            chain: chain,
            candidateContracts: candidateContracts,
            candidateCollections: candidateCollections
        )
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
        from contractSnapshot: NFTRefreshContractSnapshot,
        snapshot: inout NFTRefreshPersistenceScopeSnapshot
    ) -> NFT.Contract {
        let contractID = makeScopedContractID(
            chain: contractSnapshot.chain,
            address: contractSnapshot.address
        )

        if let cachedContract = snapshot.persistedContractsByID[contractID] {
            cachedContract.address = contractSnapshot.address
            cachedContract.chainRawValue = contractSnapshot.chain.rawValue
            return cachedContract
        }

        let contract = NFT.Contract(
            address: contractSnapshot.address,
            chain: contractSnapshot.chain
        )
        modelContext.insert(contract)
        snapshot.persistedContractsByID[contract.id] = contract
        return contract
    }

    private func resolveCollection(
        from collectionSnapshot: NFTRefreshCollectionSnapshot,
        snapshot: inout NFTRefreshPersistenceScopeSnapshot
    ) -> NFT.Collection {
        let collectionID = makeScopedCollectionID(
            chain: collectionSnapshot.chain,
            name: collectionSnapshot.name,
            contractAddress: collectionSnapshot.contractAddress
        )

        if let cachedCollection = snapshot.persistedCollectionsByID[collectionID] {
            cachedCollection.name = collectionSnapshot.name
            cachedCollection.chainRawValue = collectionSnapshot.chain.rawValue
            cachedCollection.contractAddress = collectionSnapshot.contractAddress
            return cachedCollection
        }

        let collection = NFT.Collection(
            name: collectionSnapshot.name,
            chain: collectionSnapshot.chain,
            contractAddress: collectionSnapshot.contractAddress
        )
        modelContext.insert(collection)
        snapshot.persistedCollectionsByID[collection.id] = collection
        return collection
    }

    private func pruneOrphanedSharedModels(
        chain: Chain,
        candidateContracts: [NFT.Contract],
        candidateCollections: [NFT.Collection]
    ) throws {
        let chainRawValue = chain.rawValue
        let descriptor = FetchDescriptor<NFT>(
            predicate: #Predicate<NFT> { nft in
                nft.networkRawValue == chainRawValue
            }
        )
        let chainScopedNFTs = try modelContext.fetch(descriptor)
        let referencedContractIDs = Set(chainScopedNFTs.map(\.contract.id))
        let referencedCollectionIDs = Set(chainScopedNFTs.compactMap(\.collection?.id))

        var deletedSharedModel = false

        for contract in candidateContracts where !referencedContractIDs.contains(contract.id) {
            modelContext.delete(contract)
            deletedSharedModel = true
        }

        for collection in candidateCollections where !referencedCollectionIDs.contains(collection.id) {
            modelContext.delete(collection)
            deletedSharedModel = true
        }

        if deletedSharedModel {
            try modelContext.save()
        }
    }

    private func makeNFT(
        from snapshot: NFTRefreshPersistenceSnapshot,
        owningAccount: EOAccount?,
        snapshot persistenceScope: inout NFTRefreshPersistenceScopeSnapshot
    ) -> NFT {
        let contract = resolveContract(
            from: snapshot.contract,
            snapshot: &persistenceScope
        )
        let collection = snapshot.collection.map {
            resolveCollection(
                from: $0,
                snapshot: &persistenceScope
            )
        }

        let nft = NFT(
            id: snapshot.id,
            contract: contract,
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
            collection: collection,
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
        nft.assignOwnership(to: owningAccount)
        return nft
    }

    private func makeScopedContractID(
        chain: Chain,
        address: String?
    ) -> String {
        let resolvedAddress = NFT.normalizedScopeComponent(address) ?? "unknown"
        return "\(chain.rawValue):\(resolvedAddress)"
    }

    private func makeScopedCollectionID(
        chain: Chain,
        name: String?,
        contractAddress: String?
    ) -> String {
        if let resolvedContractAddress = NFT.normalizedScopeComponent(contractAddress) {
            return "\(chain.rawValue):\(resolvedContractAddress)"
        }

        let resolvedName = NFT.normalizedScopeComponent(name) ?? "unknown"
        return "\(chain.rawValue):name:\(resolvedName)"
    }
}
