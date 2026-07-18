import AuralisPrimaryModels
import Foundation
import MusicFeature
import SwiftData

/// Deterministic AuraPlay library seeds (P9-009). Stable IDs and dates so
/// assertions and future snapshots do not drift between runs.
@MainActor
enum AuraPlayLibrarySeed {
    static let accountAddress = "0x1234567890abcdef1234567890abcdef12345678"
    static let chain = Chain.ethMainnet
    static let baseDate = Date(timeIntervalSince1970: 1_750_000_000)

    static var scope: AuraPlayLibraryScope {
        AuraPlayLibraryScope(accountAddress: accountAddress, chain: chain)
    }

    enum Tier {
        case minimal
        case standard
        case large(Int)
    }

    static func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(AuraPlaySchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    @discardableResult
    static func seed(_ container: ModelContainer, tier: Tier) throws -> Int {
        let context = ModelContext(container)
        let items: [AuraPlayMediaItem]
        switch tier {
        case .minimal:
            items = [
                makeItem(index: 0, title: "Only Track", artist: "Solo", collection: "Single", contract: "0xc0")
            ]
        case .standard:
            items = standardItems()
        case .large(let count):
            items = (0..<count).map { index in
                makeItem(
                    index: index,
                    title: "Bulk Track \(String(format: "%05d", index))",
                    artist: "Bulk Artist \(index % 7)",
                    collection: "Bulk Collection \(index % 5)",
                    contract: "0xbulk\(index % 5)",
                    hasVideo: index % 9 == 0,
                    isPlayable: index % 11 != 10,
                    duration: Double(90 + index % 240)
                )
            }
        }
        for item in items {
            context.insert(item)
        }
        try context.save()
        return items.count
    }

    /// Standard tier: audio + video, one non-playable, one without artwork,
    /// two collections sharing a name on different contracts, and two
    /// creators sharing a display name with distinct identifiers.
    static func standardItems() -> [AuraPlayMediaItem] {
        [
            makeItem(index: 0, title: "Aurora Drift", artist: "Nova", collection: "Waves", contract: "0xaaa", duration: 201, lastPlayedAt: baseDate.addingTimeInterval(-3_600)),
            makeItem(index: 1, title: "Basalt", artist: "Nova", collection: "Waves", contract: "0xaaa", duration: 154),
            makeItem(index: 2, title: "Cinder Loop", artist: "Kestrel", collection: "Waves", contract: "0xbbb", duration: 320),
            makeItem(index: 3, title: "Delta Bloom", artist: "Kestrel", collection: "Meadow", contract: "0xccc", hasVideo: true, duration: 645),
            makeItem(index: 4, title: "Ember Signal", artist: "Same Name", collection: "Meadow", contract: "0xccc", creatorID: "eth:artist:one", duration: 99),
            makeItem(index: 5, title: "Fen Static", artist: "Same Name", collection: "Meadow", contract: "0xccc", creatorID: "eth:artist:two", duration: 187),
            makeItem(index: 6, title: "Ghost Format", artist: "Nova", collection: "Waves", contract: "0xaaa", isPlayable: false),
            makeItem(index: 7, title: "Halcyon", artist: "Nova", collection: "Waves", contract: "0xaaa", artwork: nil, duration: 260)
        ]
    }

    static func makeItem(
        index: Int,
        title: String,
        artist: String,
        collection: String,
        contract: String?,
        creatorID: String? = nil,
        artwork: String? = "https://artwork.example/item.png",
        hasVideo: Bool = false,
        isPlayable: Bool = true,
        duration: Double? = nil,
        lastPlayedAt: Date? = nil
    ) -> AuraPlayMediaItem {
        AuraPlayMediaItem(
            sourceNFTID: "nft-\(String(format: "%05d", index))",
            accountAddressRawValue: accountAddress,
            chain: chain,
            contractAddressRawValue: contract,
            tokenID: "\(index)",
            tokenType: "ERC721",
            title: title,
            artistName: artist,
            creatorIdentifierRawValue: creatorID,
            collectionName: collection,
            normalizedTitleKey: title.lowercased(),
            normalizedArtistKey: artist.lowercased(),
            normalizedCollectionKey: collection.lowercased(),
            artworkURLString: artwork,
            playbackURLString: isPlayable ? "https://media.example/\(index).\(hasVideo ? "mp4" : "mp3")" : nil,
            durationSeconds: duration,
            contentType: hasVideo ? "video/mp4" : "audio/mpeg",
            sourceUpdatedAtRawValue: nil,
            hasArtwork: artwork != nil,
            hasAudio: !hasVideo,
            hasVideo: hasVideo,
            isPlayable: isPlayable,
            isSearchable: true,
            lastPlayedAt: lastPlayedAt,
            createdAt: baseDate.addingTimeInterval(Double(index) * 60),
            updatedAt: baseDate.addingTimeInterval(Double(index) * 60)
        )
    }
}
