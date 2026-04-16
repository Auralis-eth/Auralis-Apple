import Foundation

protocol NFTInventoryProviding {
    func nftsForOwner(
        owner: String,
        pageKey: String?
    ) async throws -> AlchemyNFTResponse
}
