import AuralisPrimaryModels
import Foundation
import SwiftData

public enum AuraPlaySchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            AuraPlayNFTToken.self,
            AuraPlayMediaItem.self,
            AuraPlayPlaybackPositionState.self,
            AuraPlayPlaylist.self,
            AuraPlayPlaylistItem.self,
        ]
    }

    @Model
    public final class AuraPlayNFTToken {
        @Attribute(.unique) public var compositeID: String
        public var chainRawValue: String
        public var walletAddress: String
        public var contractAddress: String?
        public var tokenId: String
        public var tokenStandard: String?
        public var collectionName: String?
        public var name: String?
        public var tokenDescription: String?
        public var imageURL: String?
        public var metadataURL: String?
        public var metadataRaw: String?
        public var providerUpdatedAt: String?
        public var isActive: Bool
        public var providerRawValue: String
        public var updatedAt: Date
        public var createdAt: Date

        public init(
            compositeID: String,
            chainRawValue: String,
            walletAddress: String,
            contractAddress: String?,
            tokenId: String,
            tokenStandard: String?,
            collectionName: String?,
            name: String?,
            tokenDescription: String?,
            imageURL: String?,
            metadataURL: String?,
            metadataRaw: String?,
            providerUpdatedAt: String?,
            isActive: Bool,
            providerRawValue: String,
            updatedAt: Date = .now,
            createdAt: Date = .now
        ) {
            self.compositeID = compositeID
            self.chainRawValue = chainRawValue
            self.walletAddress = walletAddress
            self.contractAddress = contractAddress
            self.tokenId = tokenId
            self.tokenStandard = tokenStandard
            self.collectionName = collectionName
            self.name = name
            self.tokenDescription = tokenDescription
            self.imageURL = imageURL
            self.metadataURL = metadataURL
            self.metadataRaw = metadataRaw
            self.providerUpdatedAt = providerUpdatedAt
            self.isActive = isActive
            self.providerRawValue = providerRawValue
            self.updatedAt = updatedAt
            self.createdAt = createdAt
        }
    }

    @Model
    public final class AuraPlayMediaItem {
        @Attribute(.unique) public var id: String
        public var sourceNFTID: String
        public var accountAddressRawValue: String
        public var chainRawValue: String
        public var contractAddressRawValue: String?
        public var tokenID: String
        public var tokenType: String?
        public var title: String
        public var artistName: String?
        public var creatorIdentifierRawValue: String?
        public var collectionName: String?
        public var normalizedTitleKey: String
        public var normalizedArtistKey: String
        public var normalizedCollectionKey: String
        public var artworkURLString: String?
        public var playbackURLString: String?
        public var durationSeconds: Double?
        public var contentType: String?
        public var sourceUpdatedAtRawValue: String?
        public var hasArtwork: Bool
        public var hasAudio: Bool
        public var hasVideo: Bool
        public var isPlayable: Bool
        public var isSearchable: Bool
        public var lastPlayedAt: Date?
        public var createdAt: Date
        public var updatedAt: Date

        public init(
            sourceNFTID: String,
            accountAddressRawValue: String,
            chain: Chain,
            contractAddressRawValue: String?,
            tokenID: String,
            tokenType: String?,
            title: String,
            artistName: String?,
            creatorIdentifierRawValue: String? = nil,
            collectionName: String?,
            normalizedTitleKey: String,
            normalizedArtistKey: String,
            normalizedCollectionKey: String,
            artworkURLString: String?,
            playbackURLString: String?,
            durationSeconds: Double? = nil,
            contentType: String?,
            sourceUpdatedAtRawValue: String?,
            hasArtwork: Bool,
            hasAudio: Bool,
            hasVideo: Bool,
            isPlayable: Bool,
            isSearchable: Bool,
            lastPlayedAt: Date? = nil,
            createdAt: Date = .now,
            updatedAt: Date = .now
        ) {
            self.id = sourceNFTID
            self.sourceNFTID = sourceNFTID
            self.accountAddressRawValue = accountAddressRawValue
            self.chainRawValue = chain.rawValue
            self.contractAddressRawValue = contractAddressRawValue
            self.tokenID = tokenID
            self.tokenType = tokenType
            self.title = title
            self.artistName = artistName
            self.creatorIdentifierRawValue = creatorIdentifierRawValue
            self.collectionName = collectionName
            self.normalizedTitleKey = normalizedTitleKey
            self.normalizedArtistKey = normalizedArtistKey
            self.normalizedCollectionKey = normalizedCollectionKey
            self.artworkURLString = artworkURLString
            self.playbackURLString = playbackURLString
            self.durationSeconds = durationSeconds.map { max(0, $0) }
            self.contentType = contentType
            self.sourceUpdatedAtRawValue = sourceUpdatedAtRawValue
            self.hasArtwork = hasArtwork
            self.hasAudio = hasAudio
            self.hasVideo = hasVideo
            self.isPlayable = isPlayable
            self.isSearchable = isSearchable
            self.lastPlayedAt = lastPlayedAt
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }

    @Model
    public final class AuraPlayPlaybackPositionState {
        @Attribute(.unique) public var mediaID: String
        public var positionMilliseconds: Int
        public var durationMilliseconds: Int?
        public var lastPlayedAt: Date
        public var completedAt: Date?
        public var updatedAt: Date

        public init(
            mediaID: String,
            positionMilliseconds: Int,
            durationMilliseconds: Int?,
            lastPlayedAt: Date = .now,
            completedAt: Date? = nil,
            updatedAt: Date = .now
        ) {
            self.mediaID = mediaID
            self.positionMilliseconds = max(0, positionMilliseconds)
            self.durationMilliseconds = durationMilliseconds.map { max(0, $0) }
            self.lastPlayedAt = lastPlayedAt
            self.completedAt = completedAt
            self.updatedAt = updatedAt
        }
    }

    @Model
    public final class AuraPlayPlaylist {
        @Attribute(.unique) public var id: String
        public var name: String
        public var coverImageURLString: String?
        public var createdAt: Date
        public var updatedAt: Date

        @Relationship(deleteRule: .cascade, inverse: \AuraPlayPlaylistItem.playlist)
        public var items: [AuraPlayPlaylistItem]

        public init(
            id: String = UUID().uuidString,
            name: String,
            coverImageURLString: String? = nil,
            createdAt: Date = .now,
            updatedAt: Date = .now,
            items: [AuraPlayPlaylistItem] = []
        ) {
            self.id = id
            self.name = name
            self.coverImageURLString = coverImageURLString
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.items = items
        }
    }

    @Model
    public final class AuraPlayPlaylistItem {
        @Attribute(.unique) public var id: String
        public var playlistID: String
        public var mediaItemID: String
        public var position: Int
        public var addedAt: Date
        public var playlist: AuraPlayPlaylist?

        public init(
            id: String = UUID().uuidString,
            playlistID: String,
            mediaItemID: String,
            position: Int,
            addedAt: Date = .now,
            playlist: AuraPlayPlaylist? = nil
        ) {
            self.id = id
            self.playlistID = playlistID
            self.mediaItemID = mediaItemID
            self.position = max(0, position)
            self.addedAt = addedAt
            self.playlist = playlist
        }
    }
}

public enum AuraPlaySchemaV2: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        AuraPlaySchema.models
    }
}

public enum AuraPlayMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [AuraPlaySchemaV1.self, AuraPlaySchemaV2.self]
    }

    public static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: AuraPlaySchemaV1.self, toVersion: AuraPlaySchemaV2.self),
        ]
    }
}
