import AuralisPrimaryModels
import Foundation

public protocol NFTInventoryProviding: Sendable {
    func nftsForOwner(
        owner: String,
        pageKey: String?
    ) async throws -> AlchemyNFTResponse
}
