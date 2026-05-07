@testable import Auralis
import AuralisPrimaryModels
import Foundation
import SwiftData

@MainActor
func makeNFTRefreshContainer() throws -> ModelContainer {
    let schema = Schema([EOAccount.self, NFT.self, Tag.self, StoredReceipt.self])
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [configuration])
}

func makeRefreshFixtureNFT(
    contractAddress: String = "0x495f947276749ce646f68ac8c248420045cb7b5e",
    tokenId: String = "42",
    collectionName: String = "Fixture Collection",
    network: Chain = .ethMainnet,
    accountAddress: String = "0x1234567890abcdef1234567890abcdef12345678",
    tokenURI: String? = nil,
    rawTokenURI: String? = nil,
    rawMetadata: [String: JSONValue]? = nil
) -> NFT {
    let normalizedAccountAddress = NFT.normalizedScopeComponent(accountAddress) ?? "unscoped"
    let normalizedContractAddress = NFT.normalizedScopeComponent(contractAddress) ?? "unknown"
    let resolvedTokenURI = tokenURI ?? "ipfs://fixture-\(tokenId)"
    let raw = rawTokenURI == nil && rawMetadata == nil
        ? nil
        : NFT.Raw(tokenUri: rawTokenURI, metadata: rawMetadata)

    return NFT(
        id: "\(normalizedAccountAddress):\(network.rawValue):\(normalizedContractAddress):\(tokenId)",
        contract: NFT.Contract(address: contractAddress, chain: network),
        tokenId: tokenId,
        name: "Fixture NFT",
        image: nil,
        raw: raw,
        collection: NFT.Collection(
            name: collectionName,
            chain: network,
            contractAddress: contractAddress
        ),
        tokenUri: resolvedTokenURI,
        network: network,
        accountAddress: accountAddress,
        collectionName: collectionName
    )
}
