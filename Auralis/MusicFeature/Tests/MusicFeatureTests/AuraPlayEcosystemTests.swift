import AuralisPrimaryModels
import Foundation
import MusicFeature
import SwiftData
import Testing

@MainActor
struct AuraPlayEcosystemTests {
    @Test("deep link builder emits custom scheme links without tracking parameters")
    func deepLinkBuilderUsesCustomScheme() throws {
        let builder = AuraPlayDeepLinkBuilder()

        let playlistURL = try #require(builder.url(for: .playlist(id: "playlist-1")))
        let collectionURL = try #require(builder.url(for: .collection(identifier: "0xabc", chain: .baseMainnet)))
        let creatorURL = try #require(builder.url(for: .creator(identifier: "eth:artist:one")))

        #expect(playlistURL.absoluteString == "auraplay://playlist/playlist-1")
        #expect(collectionURL.absoluteString == "auraplay://collection/0xabc?chain=base-mainnet")
        #expect(creatorURL.absoluteString == "auraplay://creator/eth:artist:one")
        #expect(!collectionURL.absoluteString.contains("utm_"))
    }

    @Test("share policy prefers explorer URLs for media and local links for playlists")
    func sharePolicyBuildsExpectedRequests() throws {
        let item = LibraryItemCellViewModel(queryItem: MediaItemQueryItem(item: AuraPlayLibrarySeed.standardItems()[0]))
        let explorerURL = try #require(URL(string: "https://etherscan.io/nft/0xaaa/0"))
        let policy = AuraPlaySharePolicy()

        let mediaRequest = policy.mediaShareRequest(item: item, explorerURL: explorerURL)
        #expect(mediaRequest.url == explorerURL)
        #expect(mediaRequest.text.contains("Aurora Drift"))
        #expect(mediaRequest.text.contains("Ethereum"))

        let playlistRequest = policy.playlistShareRequest(id: "playlist-1", name: "Night Set")
        #expect(playlistRequest.url?.absoluteString == "auraplay://playlist/playlist-1")
        #expect(playlistRequest.text == "Night Set - AuraPlay playlist")

        let creatorRequest = policy.creatorShareRequest(
            group: LibraryCreatorGroup(
                id: "creator:cross",
                displayName: "Cross Creator",
                itemCount: 2,
                artworkURLStrings: ["https://artwork.example/creator.png"]
            )
        )
        #expect(creatorRequest.url?.absoluteString == "auraplay://creator/creator:cross")
        #expect(creatorRequest.text == "Cross Creator - 2 AuraPlay media items")
        #expect(creatorRequest.artworkURLString == "https://artwork.example/creator.png")
    }

    @Test("collection share emits a bare identifier so the handler does not double-prefix the chain")
    func collectionShareAvoidsChainDoublePrefix() throws {
        let policy = AuraPlaySharePolicy()

        // Group with no contract address: `id` is the composite "chain|key".
        let noContract = LibraryCollectionGroup(
            id: "base-mainnet|midnight-loops",
            collectionName: "Midnight Loops",
            contractAddress: nil,
            chain: .baseMainnet,
            itemCount: 3,
            artworkURLStrings: []
        )
        let noContractURL = try #require(policy.collectionShareRequest(group: noContract).url)
        // Identifier must be bare; re-qualifying with the chain reproduces `id` exactly once.
        #expect(noContractURL.absoluteString == "auraplay://collection/midnight-loops?chain=base-mainnet")
        #expect(!noContractURL.absoluteString.contains("base-mainnet|base-mainnet"))

        // Group with a contract address: the contract is shared directly.
        let withContract = LibraryCollectionGroup(
            id: "base-mainnet|0xabc",
            collectionName: "Contract Set",
            contractAddress: "0xabc",
            chain: .baseMainnet,
            itemCount: 2,
            artworkURLStrings: []
        )
        let withContractURL = try #require(policy.collectionShareRequest(group: withContract).url)
        #expect(withContractURL.absoluteString == "auraplay://collection/0xabc?chain=base-mainnet")
    }

    @Test("creator profile aggregates matching creator across connected accounts")
    func creatorProfileAggregatesAcrossConnectedAccounts() async throws {
        let container = try AuraPlayLibrarySeed.makeContainer()
        let context = ModelContext(container)
        let firstAccount = AuraPlayLibrarySeed.accountAddress
        let secondAccount = "0x2222222222222222222222222222222222222222"

        let first = AuraPlayLibrarySeed.makeItem(
            index: 20,
            title: "First Wallet Track",
            artist: "Cross Creator",
            collection: "Cross",
            contract: "0xcross",
            creatorID: "creator:cross",
            lastPlayedAt: AuraPlayLibrarySeed.baseDate
        )
        let second = AuraPlayMediaItem(
            sourceNFTID: "nft-second-wallet",
            accountAddressRawValue: secondAccount,
            chain: .baseMainnet,
            contractAddressRawValue: "0xcross",
            tokenID: "21",
            tokenType: "ERC721",
            title: "Second Wallet Track",
            artistName: "Cross Creator",
            creatorIdentifierRawValue: "creator:cross",
            collectionName: "Cross",
            normalizedTitleKey: "second wallet track",
            normalizedArtistKey: "cross creator",
            normalizedCollectionKey: "cross",
            artworkURLString: nil,
            playbackURLString: "https://media.example/21.mp3",
            durationSeconds: 180,
            contentType: "audio/mpeg",
            sourceUpdatedAtRawValue: nil,
            hasArtwork: false,
            hasAudio: true,
            hasVideo: false,
            isPlayable: true,
            isSearchable: true,
            createdAt: AuraPlayLibrarySeed.baseDate,
            updatedAt: AuraPlayLibrarySeed.baseDate
        )
        context.insert(first)
        context.insert(second)
        try context.save()

        let service = AuraPlayMediaItemService(modelContainer: container)
        let profile = try await service.fetchCreatorProfile(
            creatorIdentifier: "creator:cross",
            accountAddresses: [firstAccount, secondAccount],
            chains: nil,
            sort: .titleAZ
        )

        let unwrapped = try #require(profile)
        #expect(unwrapped.itemCount == 2)
        #expect(unwrapped.playedItemCount == 1)
        #expect(Set(unwrapped.chains) == Set([.ethMainnet, .baseMainnet]))
    }
}
