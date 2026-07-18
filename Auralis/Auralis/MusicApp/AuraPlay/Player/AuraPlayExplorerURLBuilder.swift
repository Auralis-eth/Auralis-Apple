import AuralisPrimaryModels
import ExplorerAdapter
import Foundation

/// Explorer URL policy for AuraPlay media. EVM chains route through the
/// tested `ExplorerAdapter` catalog; Solana uses Solscan, which the catalog
/// does not model. Unsupported chains return nil instead of silently falling
/// back to Etherscan.
enum AuraPlayExplorerURLBuilder {
    static let builder = ExplorerURLBuilder()

    static func nftURL(chain: Chain, contractAddress: String?, tokenID: String?) -> URL? {
        guard let contractAddress, !contractAddress.isEmpty else { return nil }

        if chain == .solanaMainnet {
            let escaped = contractAddress.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? contractAddress
            return URL(string: "https://solscan.io/token/\(escaped)")
        }

        if let tokenID, !tokenID.isEmpty {
            if let url = try? builder.url(for: .nft(contract: contractAddress, tokenID: tokenID, chain: chain)) {
                return url
            }
        }
        return try? builder.url(for: .token(contract: contractAddress, chain: chain))
    }
}
