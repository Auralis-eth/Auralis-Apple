import Foundation
import SwiftData
import AuralisFoundation

public struct MusicLibraryItemSnapshot: Sendable {
    private let id: String
    private let sourceNFTID: String
    private let accountAddressRawValue: String
    private let networkRawValue: String
    private let title: String
    private let artistName: String?
    private let collectionName: String?
    private let normalizedTitleKey: String
    private let normalizedArtistKey: String
    private let normalizedCollectionKey: String
    private let artworkURLString: String?
    private let contentType: String?
    private let playbackURLString: String?
    private let availability: MusicLibraryAvailability
    private let availabilityReason: String?
    private let sourceUpdatedAtRawValue: String?
    private let indexedAt: Date

    init(_ item: MusicLibraryItem) {
        self.id = item.id
        self.sourceNFTID = item.sourceNFTID
        self.accountAddressRawValue = item.accountAddressRawValue
        self.networkRawValue = item.networkRawValue
        self.title = item.title
        self.artistName = item.artistName
        self.collectionName = item.collectionName
        self.normalizedTitleKey = item.normalizedTitleKey
        self.normalizedArtistKey = item.normalizedArtistKey
        self.normalizedCollectionKey = item.normalizedCollectionKey
        self.artworkURLString = item.artworkURLString
        self.contentType = item.contentType
        self.playbackURLString = item.playbackURLString
        self.availability = item.availability
        self.availabilityReason = item.availabilityReason
        self.sourceUpdatedAtRawValue = item.sourceUpdatedAtRawValue
        self.indexedAt = item.indexedAt
    }

    func model() -> MusicLibraryItem {
        MusicLibraryItem(
            id: id,
            sourceNFTID: sourceNFTID,
            accountAddressRawValue: accountAddressRawValue,
            networkRawValue: networkRawValue,
            title: title,
            artistName: artistName,
            collectionName: collectionName,
            normalizedTitleKey: normalizedTitleKey,
            normalizedArtistKey: normalizedArtistKey,
            normalizedCollectionKey: normalizedCollectionKey,
            artworkURLString: artworkURLString,
            contentType: contentType,
            playbackURLString: playbackURLString,
            availability: availability,
            availabilityReason: availabilityReason,
            sourceUpdatedAtRawValue: sourceUpdatedAtRawValue,
            indexedAt: indexedAt
        )
    }
}

public enum MusicLibraryAccountPersistenceParticipant: ScopedPersistenceParticipant {
    public static func capture(
        scope accountAddress: String,
        in context: ModelContext
    ) throws -> [MusicLibraryItemSnapshot] {
        try context.fetchMusicLibraryItems(accountAddress: accountAddress).map(MusicLibraryItemSnapshot.init)
    }

    public static func delete(scope accountAddress: String, in context: ModelContext) throws {
        for item in try context.fetchMusicLibraryItems(accountAddress: accountAddress) {
            context.delete(item)
        }
    }

    public static func restore(
        _ snapshot: [MusicLibraryItemSnapshot],
        in context: ModelContext
    ) throws {
        guard context.container.schema.entity(for: MusicLibraryItem.self) != nil else {
            return
        }
        snapshot.forEach { context.insert($0.model()) }
    }
}

private extension ModelContext {
    func fetchMusicLibraryItems(accountAddress: String) throws -> [MusicLibraryItem] {
        guard container.schema.entity(for: MusicLibraryItem.self) != nil else {
            return []
        }

        let descriptor = FetchDescriptor<MusicLibraryItem>(
            predicate: #Predicate<MusicLibraryItem> { item in
                item.accountAddressRawValue == accountAddress
            }
        )
        return try fetch(descriptor)
    }
}
