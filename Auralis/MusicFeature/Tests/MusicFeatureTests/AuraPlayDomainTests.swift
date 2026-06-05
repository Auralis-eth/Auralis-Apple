import AuralisPrimaryModels
import Foundation
import MusicFeature
import Testing

@Suite
struct AuraPlayDomainTests {
    @Test("library scope keeps account and chain together")
    func libraryScopeStoresAccountAndChain() {
        let scope = AuraPlayLibraryScope(
            accountAddress: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .ethMainnet
        )

        #expect(scope.accountAddress == "0x1234567890abcdef1234567890abcdef12345678")
        #expect(scope.chain == .ethMainnet)
    }

    @Test("configuration reports missing bundle requirements")
    func configurationReportsMissingRequirements() {
        let configuration = AuraPlayModuleConfiguration(
            backgroundAudioEnabled: false,
            declaredURLSchemes: ["auralis"],
            walletQuerySchemes: ["metamask"]
        )

        #expect(configuration.missingRequirements.contains("Background audio mode is missing."))
        #expect(configuration.missingRequirements.contains("The auraplay URL scheme is missing."))
        #expect(configuration.missingRequirements.contains("Wallet query schemes missing: cbwallet, ledgerlive, rainbow."))
    }

    @Test("artwork loader returns valid track artwork URL")
    @MainActor
    func artworkLoaderReturnsTrackURL() throws {
        let loader = AuraPlayTrackArtworkLoader()
        let track = AuraPlayTrack(
            id: "track-1",
            title: "Foundation",
            artist: "AuraPlay",
            duration: 120,
            imageURLString: "https://example.com/cover.png"
        )

        #expect(try #require(loader.artworkURL(for: track)).absoluteString == "https://example.com/cover.png")
    }

    @Test("media item stores scope, search flags, and chain identity")
    func mediaItemStoresScopeAndPlaybackFlags() {
        let createdAt = Date(timeIntervalSince1970: 1_704_067_200)
        let item = AuraPlayMediaItem(
            sourceNFTID: "nft-1",
            accountAddressRawValue: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .baseMainnet,
            contractAddressRawValue: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            tokenID: "42",
            tokenType: "ERC721",
            title: "Aurora Echo",
            artistName: "Indexed Nimbus",
            collectionName: "Sky Archive",
            normalizedTitleKey: "aurora echo",
            normalizedArtistKey: "indexed nimbus",
            normalizedCollectionKey: "sky archive",
            artworkURLString: "https://example.com/cover.png",
            playbackURLString: "https://example.com/audio.mp3",
            contentType: "audio/mpeg",
            sourceUpdatedAtRawValue: "2026-06-01T00:00:00Z",
            hasArtwork: true,
            hasAudio: true,
            isPlayable: true,
            isSearchable: true,
            createdAt: createdAt,
            updatedAt: createdAt
        )

        #expect(item.id == "nft-1")
        #expect(item.chain == .baseMainnet)
        #expect(item.hasArtwork)
        #expect(item.hasAudio)
        #expect(item.isPlayable)
        #expect(item.isSearchable)
        #expect(item.updatedAt == createdAt)
    }
}
