import AuralisTestSupport
import AuralisPrimaryModels
import AuralisPrimaryPersistence
import Foundation
import NFTDomain
import ReceiptStorage
import SwiftData

@MainActor
enum NFTKitTestModelContainers {
    static func refresh() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(refreshModels),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private static let refreshModels: [any PersistentModel.Type] = [
            EOAccount.self,
            NFT.self,
            NFT.Contract.self,
            NFT.Collection.self,
            NFT.Image.self,
            NFT.Raw.self,
            Tag.self,
            StoredReceipt.self,
    ]
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
