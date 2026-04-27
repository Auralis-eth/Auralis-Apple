import Foundation

protocol NFTInventoryProviding: Sendable {
    func nftsForOwner(
        owner: String,
        pageKey: String?
    ) async throws -> AlchemyNFTResponse
}
