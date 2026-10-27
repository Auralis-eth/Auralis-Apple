import AuralisFoundation
import Foundation
import SwiftData

public struct NFTAccountSnapshot {
    let id: String
    let contractAddress: String?
    let tokenID: String
    let tokenType: String?
    let name: String?
    let nftDescription: String?
    let collectionNameValue: String?
    let collectionContractAddress: String?
    let tokenURI: String?
    let timeLastUpdated: String?
    let acquiredAtBlockTimestamp: String?
    let network: Chain
    let accountAddress: String
    let contentType: String?
    let displayCollectionName: String?
    let artistName: String?
    let animationURL: String?
    let secureAnimationURL: String?
    let audioURL: String?
    let attributes: [NFTAttributeSnapshot]
    let externalURL: String?
    let backgroundColor: String?
    let modelURL: String?
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
    let imageHighResolutionURL: String?
    let secureImageHighResolutionURL: String?
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
    let image: NFTImageSnapshot?
    let raw: NFTRawSnapshot?
    let tagNames: [String]
    let playlistIDs: [UUID]

    init(_ nft: NFT) {
        self.id = nft.id
        self.contractAddress = nft.contract.address
        self.tokenID = nft.tokenId
        self.tokenType = nft.tokenType
        self.name = nft.name
        self.nftDescription = nft.nftDescription
        self.collectionNameValue = nft.collection?.name
        self.collectionContractAddress = nft.collection?.contractAddress
        self.tokenURI = nft.tokenUri
        self.timeLastUpdated = nft.timeLastUpdated
        self.acquiredAtBlockTimestamp = nft.acquiredAt?.blockTimestamp
        self.network = nft.network ?? .ethMainnet
        self.accountAddress = nft.accountAddressRawValue
        self.contentType = nft.contentType
        self.displayCollectionName = nft.collectionName
        self.artistName = nft.artistName
        self.animationURL = nft.animationUrl
        self.secureAnimationURL = nft.secureAnimationUrl
        self.audioURL = nft.audioUrl
        self.attributes = (nft.attributes ?? []).map(NFTAttributeSnapshot.init)
        self.externalURL = nft.externalUrl
        self.backgroundColor = nft.backgroundColor
        self.modelURL = nft.modelUrl
        self.collectionID = nft.collectionID
        self.projectID = nft.projectID
        self.series = nft.series
        self.seriesID = nft.seriesID
        self.primaryAssetURL = nft.primaryAssetUrl
        self.securePrimaryAssetURL = nft.securePrimaryAssetUrl
        self.previewAssetURL = nft.previewAssetUrl
        self.securePreviewAssetURL = nft.securePreviewAssetUrl
        self.artistWebsite = nft.artistWebsite
        self.uniqueID = nft.uniqueID
        self.timestamp = nft.timestamp
        self.tokenHash = nft.tokenHash
        self.medium = nft.medium
        self.metadataVersion = nft.metadataVersion
        self.imageDataURL = nft.imageDataUrl
        self.secureImageDataURL = nft.secureImageDataUrl
        self.imageHighResolutionURL = nft.imageHrUrl
        self.secureImageHighResolutionURL = nft.secureImageHrUrl
        self.imageHash = nft.imageHash
        self.symbols = nft.symbols
        self.seed = nft.seed
        self.original = nft.original
        self.agreement = nft.agreement
        self.website = nft.website
        self.payoutAddress = nft.payoutAddress
        self.scriptType = nft.scriptType
        self.engineType = nft.engineType
        self.accessArtworkFiles = nft.accessArtworkFiles
        self.sellerFeeBasisPoints = nft.sellerFeeBasisPoints
        self.minted = nft.minted
        self.isStatic = nft.isStatic
        self.aspectRatio = nft.aspectRatio
        self.image = nft.image.map(NFTImageSnapshot.init)
        self.raw = nft.raw.map(NFTRawSnapshot.init)
        self.tagNames = (nft.tags ?? []).map(\.name)
        self.playlistIDs = nft.playlists.map(\.id)
    }

    func model() -> NFT {
        let nft = NFT(
            id: id,
            contract: NFT.Contract(address: contractAddress, chain: network),
            tokenId: tokenID,
            tokenType: tokenType,
            name: name,
            nftDescription: nftDescription,
            collection: NFT.Collection(
                name: collectionNameValue,
                chain: network,
                contractAddress: collectionContractAddress
            ),
            tokenUri: tokenURI,
            timeLastUpdated: timeLastUpdated,
            acquiredAt: NFT.AcquiredAt(blockTimestamp: acquiredAtBlockTimestamp),
            network: network,
            accountAddress: accountAddress,
            contentType: contentType,
            collectionName: displayCollectionName,
            artistName: artistName,
            animationUrl: animationURL,
            secureAnimationUrl: secureAnimationURL,
            audioUrl: audioURL
        )
        nft.attributes = attributes.map { NFT.Attribute(value: $0.value, traitType: $0.traitType) }
        nft.externalUrl = externalURL
        nft.backgroundColor = backgroundColor
        nft.modelUrl = modelURL
        nft.collectionID = collectionID
        nft.projectID = projectID
        nft.series = series
        nft.seriesID = seriesID
        nft.primaryAssetUrl = primaryAssetURL
        nft.securePrimaryAssetUrl = securePrimaryAssetURL
        nft.previewAssetUrl = previewAssetURL
        nft.securePreviewAssetUrl = securePreviewAssetURL
        nft.artistWebsite = artistWebsite
        nft.uniqueID = uniqueID
        nft.timestamp = timestamp
        nft.tokenHash = tokenHash
        nft.medium = medium
        nft.metadataVersion = metadataVersion
        nft.imageDataUrl = imageDataURL
        nft.secureImageDataUrl = secureImageDataURL
        nft.imageHrUrl = imageHighResolutionURL
        nft.secureImageHrUrl = secureImageHighResolutionURL
        nft.imageHash = imageHash
        nft.symbols = symbols
        nft.seed = seed
        nft.original = original
        nft.agreement = agreement
        nft.website = website
        nft.payoutAddress = payoutAddress
        nft.scriptType = scriptType
        nft.engineType = engineType
        nft.accessArtworkFiles = accessArtworkFiles
        nft.sellerFeeBasisPoints = sellerFeeBasisPoints
        nft.minted = minted
        nft.isStatic = isStatic
        nft.aspectRatio = aspectRatio
        nft.image = image?.model()
        nft.raw = raw?.model()
        return nft
    }
}

struct NFTImageSnapshot {
    let originalURL: String?
    let thumbnailURL: String?
    let secureURL: String?

    init(_ image: NFT.Image) {
        self.originalURL = image.originalUrl
        self.thumbnailURL = image.thumbnailUrl
        self.secureURL = image.secureUrl
    }

    func model() -> NFT.Image {
        let image = NFT.Image(originalUrl: originalURL, thumbnailUrl: thumbnailURL)
        image.secureUrl = secureURL
        return image
    }
}

struct NFTRawSnapshot {
    let tokenURI: String?
    let metadata: [String: JSONValue]?
    let error: String?

    init(_ raw: NFT.Raw) {
        self.tokenURI = raw.tokenUri
        self.metadata = raw.metadata
        self.error = raw.error
    }

    func model() -> NFT.Raw {
        let raw = NFT.Raw(tokenUri: tokenURI, metadata: metadata)
        raw.error = error
        return raw
    }
}

struct NFTAttributeSnapshot {
    let value: String
    let traitType: String?

    init(_ attribute: NFT.Attribute) {
        self.value = attribute.value
        self.traitType = attribute.traitType
    }
}

public enum NFTAccountPersistenceParticipant: ScopedPersistenceParticipant {
    public static func capture(scope accountAddress: String, in context: ModelContext) throws -> [NFTAccountSnapshot] {
        guard context.container.schema.entity(for: NFT.self) != nil else {
            return []
        }
        let descriptor = FetchDescriptor<NFT>(
            predicate: #Predicate<NFT> { nft in
                nft.accountAddressRawValue == accountAddress
            }
        )
        return try context.fetch(descriptor).map(NFTAccountSnapshot.init)
    }

    public static func delete(scope accountAddress: String, in context: ModelContext) throws {
        guard context.container.schema.entity(for: NFT.self) != nil else {
            return
        }
        try context.deleteNFTsScopedToAccount(accountAddress)
    }

    public static func restore(_ snapshot: [NFTAccountSnapshot], in context: ModelContext) throws {
        guard context.container.schema.entity(for: NFT.self) != nil else {
            return
        }
        let existingTags = try context.fetch(FetchDescriptor<Tag>())
        var tagsByName = Dictionary(uniqueKeysWithValues: existingTags.map { ($0.name, $0) })
        let playlistsByID = Dictionary(
            uniqueKeysWithValues: try context.fetch(FetchDescriptor<Playlist>()).map { ($0.id, $0) }
        )

        for item in snapshot {
            let nft = item.model()
            nft.tags = try item.tagNames.map { name in
                if let tag = tagsByName[name] {
                    return tag
                }
                let tag = try Tag(name: name)
                context.insert(tag)
                tagsByName[name] = tag
                return tag
            }
            nft.playlists = item.playlistIDs.compactMap { playlistsByID[$0] }
            context.insert(nft)
        }
    }
}
