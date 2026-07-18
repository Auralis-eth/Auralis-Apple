import AuralisPrimaryModels
@testable import MusicFeature
import Foundation
import Testing

struct AuraPlayDiscoveryContractTests {
    @Test("NFT token DTO normalizes EVM composite IDs")
    func nftTokenDTOCompositeIDEVM() {
        let token = NFTTokenDTO(
            chain: .ethMainnet,
            walletAddress: "  0xABCDEFabcdefABCDEFabcdefABCDEFabcdefABCD  ",
            contractAddress: "0xC0FFEE0000000000000000000000000000000000",
            tokenId: "42",
            tokenStandard: "ERC721"
        )

        #expect(token.walletAddress == "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd")
        #expect(token.contractAddress == "0xc0ffee0000000000000000000000000000000000")
        #expect(token.compositeID == "eth-mainnet:0xc0ffee0000000000000000000000000000000000:42:0xabcdefabcdefabcdefabcdefabcdefabcdefabcd")
    }

    @Test("NFT token DTO uses missing-contract fallback for Solana IDs")
    func nftTokenDTOCompositeIDSolana() {
        let token = NFTTokenDTO(
            chain: .solanaMainnet,
            walletAddress: "SolanaOwnerAddress",
            contractAddress: nil,
            tokenId: "MintAddress",
            tokenStandard: "ProgrammableNFT",
            name: "Sol Track",
            metadataURL: "https://example.com/metadata.json"
        )

        #expect(token.compositeID == "solana-mainnet::MintAddress:solanaowneraddress")
    }

    @Test("Metadata parser detects Sound.xyz before OpenSea")
    func metadataParserPrioritizesSoundXyz() {
        let json = """
        {
          "name": "Lossless Track",
          "image": "ipfs://cover",
          "animation_url": "https://example.com/video.mp4",
          "artist": "Catalog Artist",
          "project": "Catalog Project",
          "losslessAudio": "ipfs://track.flac",
          "duration": 183,
          "attributes": [{"trait_type": "Mood", "value": "Night"}]
        }
        """

        let parsed = MetadataParser().parse(json: json)

        #expect(parsed.schemaVersion == .soundXyz)
        #expect(parsed.audioURL == "ipfs://track.flac")
        #expect(parsed.videoURL == "https://example.com/video.mp4")
        #expect(parsed.creatorName == "Catalog Artist")
        #expect(parsed.collectionName == "Catalog Project")
        #expect(parsed.duration == 183)
        #expect(parsed.attributes["Mood"] == "Night")
    }

    @Test("Metadata parser extracts Zora video content")
    func metadataParserExtractsZoraVideo() {
        let json = """
        {
          "name": "Zora Video",
          "description": "Moving edition",
          "image": "https://example.com/poster.png",
          "content": {
            "uri": "ipfs://video.mp4",
            "mime": "video/mp4"
          }
        }
        """

        let parsed = MetadataParser().parse(json: json)

        #expect(parsed.schemaVersion == .zora)
        #expect(parsed.videoURL == "ipfs://video.mp4")
        #expect(parsed.audioURL == nil)
        #expect(parsed.format == "mp4")
    }

    @Test("Metadata parser extracts Metaplex creator and file audio")
    func metadataParserExtractsMetaplexAudio() {
        let json = """
        {
          "name": "Solana Song",
          "symbol": "AURA",
          "image": "https://example.com/sol.png",
          "properties": {
            "creators": [{"address": "CreatorAddress"}],
            "files": [{"uri": "ipfs://sol-track.mp3", "type": "audio/mpeg"}]
          },
          "collection": {"name": "Solana Collection"}
        }
        """

        let parsed = MetadataParser().parse(json: json)

        #expect(parsed.schemaVersion == .metaplex)
        #expect(parsed.creatorName == "CreatorAddress")
        #expect(parsed.collectionName == "Solana Collection")
        #expect(parsed.audioURL == "ipfs://sol-track.mp3")
        #expect(parsed.format == "mp3")
    }

    @Test("Metadata parser returns unknown for invalid JSON")
    func metadataParserInvalidJSON() {
        let parsed = MetadataParser().parse(json: "{")

        #expect(parsed.schemaVersion == .unknown)
        #expect(parsed.name == nil)
        #expect(parsed.attributes.isEmpty)
    }

    @Test("Media classifier treats direct audio URLs as playable audio")
    func mediaClassifierAudioURL() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let classifier = MediaClassifier(
            urlResolver: URLResolver(configuration: Self.resolutionConfiguration),
            clock: { date }
        )
        let item = classifier.classify(
            parsed: MetadataParsed(
                name: "Track",
                artworkURL: "ipfs://cover.png",
                audioURL: "ipfs://track.mp3",
                schemaVersion: .openSea,
                rawJSON: "{}"
            ),
            token: Self.token(tokenId: "1")
        )

        #expect(item.title == "Track")
        #expect(item.artworkURL == "https://media.example/ipfs/cover.png")
        #expect(item.audioURL == "https://media.example/ipfs/track.mp3")
        #expect(item.videoURL == nil)
        #expect(item.format == "mp3")
        #expect(item.hasAudio)
        #expect(!item.hasVideo)
        #expect(item.isPlayable)
        #expect(item.classifiedAt == date)
        #expect(item.createdAt == date)
    }

    @Test("Media classifier disambiguates animation URLs by extension")
    func mediaClassifierDisambiguatesAnimationURL() {
        let classifier = MediaClassifier(
            urlResolver: URLResolver(configuration: Self.resolutionConfiguration),
            clock: { Date(timeIntervalSince1970: 1) }
        )

        let mp3 = classifier.classify(
            parsed: MetadataParsed(videoURL: "https://example.com/animation.mp3", schemaVersion: .openSea, rawJSON: "{}"),
            token: Self.token(tokenId: "2")
        )
        let mp4 = classifier.classify(
            parsed: MetadataParsed(videoURL: "https://example.com/animation.mp4", schemaVersion: .openSea, rawJSON: "{}"),
            token: Self.token(tokenId: "3")
        )

        #expect(mp3.audioURL == "https://example.com/animation.mp3")
        #expect(mp3.videoURL == nil)
        #expect(mp3.hasAudio)
        #expect(!mp3.hasVideo)
        #expect(mp4.audioURL == nil)
        #expect(mp4.videoURL == "https://example.com/animation.mp4")
        #expect(!mp4.hasAudio)
        #expect(mp4.hasVideo)
    }

    @Test("Media classifier treats Sound.xyz animation host as audio")
    func mediaClassifierTreatsSoundHostAsAudio() {
        let classifier = MediaClassifier(
            urlResolver: URLResolver(configuration: Self.resolutionConfiguration),
            clock: { Date(timeIntervalSince1970: 1) }
        )

        let item = classifier.classify(
            parsed: MetadataParsed(videoURL: "https://sound.xyz/artist/track", schemaVersion: .soundXyz, rawJSON: "{}"),
            token: Self.token(tokenId: "4")
        )

        #expect(item.audioURL == "https://sound.xyz/artist/track")
        #expect(item.videoURL == nil)
        #expect(item.hasAudio)
    }

    @Test("Media classifier returns non-playable items and title fallback")
    func mediaClassifierNonPlayableFallback() {
        let classifier = MediaClassifier(
            urlResolver: URLResolver(configuration: Self.resolutionConfiguration),
            clock: { Date(timeIntervalSince1970: 1) }
        )

        let item = classifier.classify(
            parsed: MetadataParsed(schemaVersion: .openSea, rawJSON: "{}"),
            token: Self.token(tokenId: "42", name: nil)
        )

        #expect(item.title == "Untitled #42")
        #expect(!item.hasAudio)
        #expect(!item.hasVideo)
        #expect(!item.isPlayable)
    }

    @Test("Media item DTO maps to AuraPlay media upsert request")
    func mediaItemDTOMakesUpsertRequest() {
        let dto = MediaItemDTO(
            id: "media-1",
            nftTokenId: "nft-1",
            title: "Aural Echo",
            creatorName: "Artist",
            collectionName: "Collection",
            artworkURL: "https://example.com/art.png",
            audioURL: "https://example.com/audio.mp3",
            videoURL: nil,
            durationSeconds: 120,
            format: "mp3",
            hasAudio: true,
            hasVideo: false,
            isPlayable: true,
            chain: .baseMainnet,
            contractAddress: "0xcontract",
            tokenId: "7",
            tokenStandard: "ERC721",
            walletAddress: "0xwallet",
            classifiedAt: Date(timeIntervalSince1970: 1),
            createdAt: Date(timeIntervalSince1970: 1)
        )

        let request = dto.makeAuraPlayMediaItemUpsertRequest()

        #expect(request.sourceNFTID == "nft-1")
        #expect(request.tokenType == "ERC721")
        #expect(request.playbackURLString == "https://example.com/audio.mp3")
        #expect(request.normalizedTitleKey == "aural echo")
        #expect(request.hasArtwork)
        #expect(request.hasAudio)
        #expect(!request.hasVideo)
        #expect(request.isPlayable)
    }

    private static func token(tokenId: String, name: String? = "Token") -> NFTTokenDTO {
        NFTTokenDTO(
            chain: .ethMainnet,
            walletAddress: "0x1234567890abcdef1234567890abcdef12345678",
            contractAddress: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
            tokenId: tokenId,
            tokenStandard: "ERC721",
            collectionName: "Token Collection",
            name: name
        )
    }

    private static let resolutionConfiguration = AuraPlayStorageResolutionConfiguration(
        ipfsGatewayURL: URL(string: "https://media.example")!,
        arweaveGatewayURL: URL(string: "https://ar.example")!,
        fallbackIPFSGatewayURLs: [],
        fallbackArweaveGatewayURLs: []
    )
}
