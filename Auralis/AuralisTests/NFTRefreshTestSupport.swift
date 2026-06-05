@testable import Auralis
import AuralisPrimaryModels
import AuralisPrimaryPersistence
import Foundation
import NFTDomain
import ReceiptStorage
import SwiftData

@MainActor
func makeNFTRefreshContainer() throws -> ModelContainer {
    try TestModelContainers.primary()
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

func makeRefreshFixtureSnapshot(
    contractAddress: String = "0x495f947276749ce646f68ac8c248420045cb7b5e",
    tokenId: String = "42",
    collectionName: String = "Fixture Collection",
    network: Chain = .ethMainnet,
    accountAddress: String = "0x1234567890abcdef1234567890abcdef12345678",
    tokenURI: String? = nil,
    rawTokenURI: String? = nil,
    rawMetadata: [String: JSONValue]? = nil
) -> NFTInventoryItemSnapshot {
    let normalizedAccountAddress = NFTInventoryItemSnapshot.normalizedScopeComponent(accountAddress) ?? "unscoped"
    let normalizedContractAddress = NFTInventoryItemSnapshot.normalizedScopeComponent(contractAddress) ?? "unknown"
    let resolvedTokenURI = tokenURI ?? "ipfs://fixture-\(tokenId)"
    let raw = rawTokenURI == nil && rawMetadata == nil
        ? nil
        : NFTInventoryItemSnapshot.Raw(tokenURI: rawTokenURI, metadata: rawMetadata, error: nil)

    return NFTInventoryItemSnapshot(
        id: "\(normalizedAccountAddress):\(network.rawValue):\(normalizedContractAddress):\(tokenId)",
        contract: NFTInventoryItemSnapshot.Contract(address: contractAddress, chain: network),
        tokenId: tokenId,
        tokenType: nil,
        name: "Fixture NFT",
        nftDescription: nil,
        image: nil,
        raw: raw,
        collection: NFTInventoryItemSnapshot.Collection(
            name: collectionName,
            chain: network,
            contractAddress: contractAddress
        ),
        tokenURI: resolvedTokenURI,
        timeLastUpdated: nil,
        acquiredAt: nil,
        network: network,
        accountAddress: accountAddress,
        collectionName: collectionName
    )
}
