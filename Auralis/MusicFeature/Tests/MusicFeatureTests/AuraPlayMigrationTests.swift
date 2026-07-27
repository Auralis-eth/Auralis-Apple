@testable import MusicFeature
import AuralisPrimaryModels
import Foundation
import SwiftData
import Testing

@Suite(.serialized)
struct AuraPlayMigrationTests {
    @Test("AuraPlay V1 stores migrate to V2 with cache and loudness defaults")
    func v1StoreMigratesToV2() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appending(path: "AuraPlayMigrationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: baseDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        try seedV1Store(baseDirectory: baseDirectory)

        let migratedContainer = try AuraPlayModelContainer.make(
            inMemory: false,
            baseDirectory: baseDirectory
        )
        let context = ModelContext(migratedContainer)

        let mediaItem = try #require(try context.fetch(FetchDescriptor<AuraPlayMediaItem>()).first)
        #expect(mediaItem.sourceNFTID == "media-1")
        #expect(mediaItem.cachedFileStateRawValue == "notCached")
        #expect(mediaItem.approxLoudnessLUFS == nil)

        let playbackState = try #require(try context.fetch(FetchDescriptor<AuraPlayPlaybackPositionState>()).first)
        #expect(playbackState.mediaID == "media-1")
        #expect(playbackState.positionMilliseconds == 42_000)
        #expect(playbackState.playCount == 0)

        let playlist = try #require(try context.fetch(FetchDescriptor<AuraPlayPlaylist>()).first)
        #expect(playlist.name == "Migration Mix")
        #expect(playlist.isSmart == false)
        #expect(playlist.smartQueryData == nil)
        #expect(playlist.items.map(\.mediaItemID) == ["media-1"])
    }

    private func seedV1Store(baseDirectory: URL) throws {
        let schema = Schema(versionedSchema: AuraPlaySchemaV1.self)
        let configuration = ModelConfiguration(
            schema: schema,
            url: try AuraPlayModelContainer.storeURL(baseDirectory: baseDirectory)
        )
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        let context = ModelContext(container)
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        let mediaItem = AuraPlaySchemaV1.AuraPlayMediaItem(
            sourceNFTID: "media-1",
            accountAddressRawValue: "0x1111111111111111111111111111111111111111",
            chain: .ethMainnet,
            contractAddressRawValue: "0x2222222222222222222222222222222222222222",
            tokenID: "1",
            tokenType: "erc721",
            title: "Migration Song",
            artistName: "Auralis",
            collectionName: "Migration Collection",
            normalizedTitleKey: "migration song",
            normalizedArtistKey: "auralis",
            normalizedCollectionKey: "migration collection",
            artworkURLString: "https://example.com/art.png",
            playbackURLString: "https://example.com/audio.mp3",
            durationSeconds: 120,
            contentType: "audio/mpeg",
            sourceUpdatedAtRawValue: nil,
            hasArtwork: true,
            hasAudio: true,
            hasVideo: false,
            isPlayable: true,
            isSearchable: true,
            lastPlayedAt: date,
            createdAt: date,
            updatedAt: date
        )
        let playbackState = AuraPlaySchemaV1.AuraPlayPlaybackPositionState(
            mediaID: "media-1",
            positionMilliseconds: 42_000,
            durationMilliseconds: 120_000,
            lastPlayedAt: date,
            updatedAt: date
        )
        let playlist = AuraPlaySchemaV1.AuraPlayPlaylist(
            id: "playlist-1",
            name: "Migration Mix",
            createdAt: date,
            updatedAt: date
        )
        let playlistItem = AuraPlaySchemaV1.AuraPlayPlaylistItem(
            id: "playlist-item-1",
            playlistID: "playlist-1",
            mediaItemID: "media-1",
            position: 0,
            addedAt: date,
            playlist: playlist
        )
        playlist.items = [playlistItem]

        context.insert(mediaItem)
        context.insert(playbackState)
        context.insert(playlist)
        try context.save()
    }
}
