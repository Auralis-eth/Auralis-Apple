@testable import Auralis
import AuralisPrimaryModels
import AuralisPrimaryPersistence
import Foundation
import Testing
import NFTKit

@Suite
struct PrepareNFTMetadataUseCaseTests {
    @Test("applies refresh scope to prepared NFTs")
    @MainActor
    func appliesAccountAndChainScope() async throws {
        let nft = makeRefreshFixtureNFT(
            network: .ethMainnet,
            accountAddress: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        )
        let useCase = LivePrepareNFTMetadataUseCase()

        let inventory = await useCase.prepareInventory(
            [nft],
            accountAddress: "0xBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB",
            chain: .baseMainnet
        )
        let prepared = try #require(inventory.nfts.first)

        #expect(prepared.networkRawValue == Chain.baseMainnet.rawValue)
        #expect(prepared.accountAddressRawValue == "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
        #expect(prepared.contract.id == "\(Chain.baseMainnet.rawValue):0x495f947276749ce646f68ac8c248420045cb7b5e")
        #expect(prepared.collection?.id == "\(Chain.baseMainnet.rawValue):0x495f947276749ce646f68ac8c248420045cb7b5e")
    }

    @Test("decodes base64 token URI metadata when available")
    @MainActor
    func decodesBase64TokenURIMetadata() async throws {
        let metadataJSON = #"{"name":"Decoded Name","image":"https://example.com/image.png"}"#
        let encoded = Data(metadataJSON.utf8).base64EncodedString()
        let nft = makeRefreshFixtureNFT(
            tokenURI: "data:application/json;base64,\(encoded)"
        )
        let useCase = LivePrepareNFTMetadataUseCase()

        let inventory = await useCase.prepareInventory(
            [nft],
            accountAddress: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .ethMainnet
        )
        let prepared = try #require(inventory.nfts.first)

        #expect(prepared.name == "Decoded Name")
        #expect(prepared.image?.originalUrl == "https://example.com/image.png")
    }

    @Test("falls back to raw metadata when token URI decoding is unavailable")
    @MainActor
    func fallsBackToRawMetadata() async throws {
        let nft = makeRefreshFixtureNFT(
            tokenURI: "ipfs://fixture-json",
            rawMetadata: [
                "name": .string("Raw Metadata Name"),
                "audioUrl": .string("https://example.com/audio.mp3")
            ]
        )
        let useCase = LivePrepareNFTMetadataUseCase()

        let inventory = await useCase.prepareInventory(
            [nft],
            accountAddress: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .ethMainnet
        )
        let prepared = try #require(inventory.nfts.first)

        #expect(prepared.name == "Raw Metadata Name")
        #expect(prepared.audioUrl == "https://example.com/audio.mp3")
    }

    @Test("deduplicates repeated NFT ids after preparation")
    @MainActor
    func deduplicatesRepeatedIDs() async {
        let first = makeRefreshFixtureNFT(tokenId: "1")
        let second = makeRefreshFixtureNFT(tokenId: "1")
        let useCase = LivePrepareNFTMetadataUseCase()

        let inventory = await useCase.prepareInventory(
            [first, second],
            accountAddress: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .ethMainnet
        )

        #expect(inventory.nfts.count == 1)
    }
}
