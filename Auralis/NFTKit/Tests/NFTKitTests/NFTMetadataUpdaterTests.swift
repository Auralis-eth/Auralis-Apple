import AuralisTestSupport
import AuralisPrimaryModels
import AuralisPrimaryPersistence
import Testing
import NFTDomain
import NFTPersistence
import NFTPresentation
import NFTProviderAdapters

struct NFTMetadataUpdaterTests {
    @Test("metadata image updates create a missing image submodel")
    func metadataImageUpdatesCreateImageModel() throws {
        let nft = NFT(
            id: "0x1234567890abcdef1234567890abcdef12345678:eth-mainnet:0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa:1",
            contract: NFT.Contract(address: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", chain: .ethMainnet),
            tokenId: "1",
            name: "Fixture",
            image: nil,
            raw: nil,
            collection: NFT.Collection(
                name: "Collection",
                chain: .ethMainnet,
                contractAddress: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
            ),
            tokenUri: "ipfs://fixture-1",
            network: .ethMainnet,
            accountAddress: "0x1234567890abcdef1234567890abcdef12345678"
        )

        NFTMetadataUpdater.updateNFTFromMetadata(
            nft: nft,
            metadata: [
                "image": .string("https://example.com/image.png")
            ]
        )

        let image = try #require(nft.image)
        #expect(image.originalUrl == "https://example.com/image.png")
        #expect(image.secureUrl == "https://example.com/image.png")
    }

    @Test("nil metadata leaves cached NFT fields unchanged")
    func nilMetadataLeavesCachedFieldsUnchanged() throws {
        let nft = NFTFixture(
            name: "Cached Name",
            imageOriginalUrl: "https://example.com/cached.png",
            imageThumbnailUrl: "https://example.com/cached.png"
        ).build()

        NFTMetadataUpdater.updateNFTFromMetadata(nft: nft, metadata: nil)

        #expect(nft.name == "Cached Name")
        #expect(try #require(nft.image).originalUrl == "https://example.com/cached.png")
        #expect(try #require(nft.image).secureUrl == "https://example.com/cached.png")
    }

    @Test("partial metadata updates known fields and preserves cached image URLs")
    func partialMetadataUpdatesKnownFieldsAndPreservesImageURLs() throws {
        let nft = NFTFixture(
            name: "Old Name",
            imageOriginalUrl: "https://example.com/cached.png",
            imageThumbnailUrl: "https://example.com/cached.png"
        ).build()

        NFTMetadataUpdater.updateNFTFromMetadata(
            nft: nft,
            metadata: [
                "name": .string("New Name"),
                "collectionName": .string("New Collection"),
                "artist": .string("New Artist")
            ]
        )

        #expect(nft.name == "New Name")
        #expect(nft.collectionName == "New Collection")
        #expect(nft.artistName == "New Artist")
        #expect(try #require(nft.image).originalUrl == "https://example.com/cached.png")
    }

    @Test("empty metadata object preserves cached fields")
    func emptyMetadataObjectPreservesCachedFields() throws {
        let nft = NFTFixture(
            name: "Cached Name",
            imageOriginalUrl: "https://example.com/cached.png",
            imageThumbnailUrl: "https://example.com/cached.png"
        ).build()

        NFTMetadataUpdater.updateNFTFromMetadata(nft: nft, metadata: [:])

        #expect(nft.name == "Cached Name")
        #expect(try #require(nft.image).originalUrl == "https://example.com/cached.png")
        #expect(try #require(nft.image).secureUrl == "https://example.com/cached.png")
    }

    @Test("metadata image replacement updates both original and secure URLs")
    func metadataImageReplacementUpdatesImageURLs() throws {
        let nft = NFTFixture(
            name: "Cached Name",
            imageOriginalUrl: "https://example.com/old.png",
            imageThumbnailUrl: "https://example.com/old.png"
        ).build()

        NFTMetadataUpdater.updateNFTFromMetadata(
            nft: nft,
            metadata: [
                "image": .string("ipfs://new-image")
            ]
        )

        #expect(try #require(nft.image).originalUrl == "https://gateway.pinata.cloud/ipfs/new-image")
        #expect(try #require(nft.image).secureUrl == "https://gateway.pinata.cloud/ipfs/new-image")
    }

    @Test("Sound metadata prefers lossless audio and project collection fields")
    func soundMetadataPrefersLosslessAudio() {
        let nft = NFTFixture(name: "Cached Name").build()

        NFTMetadataUpdater.updateNFTFromMetadata(
            nft: nft,
            metadata: [
                "name": .string("Track One"),
                "artist": .string("Sound Artist"),
                "project": .string("Sound Project"),
                "losslessAudio": .string("https://example.com/lossless.flac"),
                "audio": .string("https://example.com/fallback.mp3"),
                "animation_url": .string("https://example.com/video.mp4")
            ]
        )

        #expect(nft.name == "Track One")
        #expect(nft.artistName == "Sound Artist")
        #expect(nft.collectionName == "Sound Project")
        #expect(nft.audioUrl == "https://example.com/lossless.flac")
        #expect(nft.animationUrl == "https://example.com/video.mp4")
        #expect(nft.contentType == "audio/flac")
    }

    @Test("Zora content metadata maps MIME typed content to video fields")
    func zoraContentMetadataMapsVideoFields() {
        let nft = NFTFixture().build()

        NFTMetadataUpdater.updateNFTFromMetadata(
            nft: nft,
            metadata: [
                "content": .object([
                    "uri": .string("ipfs://zora-video"),
                    "mime": .string("video/mp4")
                ])
            ]
        )

        #expect(nft.animationUrl == "https://gateway.pinata.cloud/ipfs/zora-video")
        #expect(nft.secureAnimationUrl == "https://gateway.pinata.cloud/ipfs/zora-video")
        #expect(nft.audioUrl == nil)
        #expect(nft.contentType == "video/mp4")
    }

    @Test("ERC-1155 file metadata maps first audio and video files")
    func erc1155FileMetadataMapsAudioAndVideoFiles() {
        let nft = NFTFixture().build()

        NFTMetadataUpdater.updateNFTFromMetadata(
            nft: nft,
            metadata: [
                "properties": .object([
                    "files": .array([
                        .object([
                            "uri": .string("ipfs://audio-track"),
                            "type": .string("audio/mpeg")
                        ]),
                        .object([
                            "uri": .string("ipfs://video-track"),
                            "type": .string("video/mp4")
                        ])
                    ])
                ])
            ]
        )

        #expect(nft.audioUrl == "https://gateway.pinata.cloud/ipfs/audio-track")
        #expect(nft.animationUrl == "https://gateway.pinata.cloud/ipfs/video-track")
        #expect(nft.secureAnimationUrl == "https://gateway.pinata.cloud/ipfs/video-track")
        #expect(nft.contentType == "audio/mpeg")
    }

    @Test("Helius DAS raw content files map audio and video URLs")
    func heliusDASRawContentFilesMapMediaURLs() {
        let nft = NFTFixture().build()

        NFTMetadataUpdater.updateNFTFromMetadata(
            nft: nft,
            metadata: [
                "content": .object([
                    "files": .array([
                        .object([
                            "uri": .string("https://example.com/mint.mp3"),
                            "cdn_uri": .string("https://cdn.example.com/mint.mp3"),
                            "mime": .string("audio/mpeg")
                        ]),
                        .object([
                            "uri": .string("https://example.com/mint.mp4"),
                            "cdn_uri": .string("https://cdn.example.com/mint.mp4"),
                            "mime": .string("video/mp4")
                        ])
                    ])
                ])
            ]
        )

        #expect(nft.audioUrl == "https://cdn.example.com/mint.mp3")
        #expect(nft.animationUrl == "https://cdn.example.com/mint.mp4")
        #expect(nft.secureAnimationUrl == "https://cdn.example.com/mint.mp4")
        #expect(nft.contentType == "audio/mpeg")
    }

    @Test("audio animation URLs are classified as audio instead of video")
    func audioAnimationURLsAreClassifiedAsAudio() {
        let nft = NFTFixture().build()

        NFTMetadataUpdater.updateNFTFromMetadata(
            nft: nft,
            metadata: [
                "animation_url": .string("https://catalog.works/token/track")
            ]
        )

        #expect(nft.audioUrl == "https://catalog.works/token/track")
        #expect(nft.animationUrl == nil)
        #expect(nft.secureAnimationUrl == nil)
        #expect(nft.contentType == nil)
    }

    @Test("Metaplex seller fee basis points updates royalty basis points")
    func metaplexSellerFeeBasisPointsUpdatesRoyalty() {
        let nft = NFTFixture().build()

        NFTMetadataUpdater.updateNFTFromMetadata(
            nft: nft,
            metadata: [
                "seller_fee_basis_points": .number(750)
            ]
        )

        #expect(nft.sellerFeeBasisPoints == 750)
    }
}
