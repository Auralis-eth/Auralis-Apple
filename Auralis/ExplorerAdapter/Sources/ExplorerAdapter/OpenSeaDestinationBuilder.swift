import AuralisPrimaryModels
import Foundation

public struct OpenSeaDestinationBuilder: Sendable {
    public init() { }

    public func url(contract: String, tokenID: String, chain: Chain) throws -> URL {
        guard let chainSlug = openSeaChainSlug(for: chain) else {
            throw ExplorerURLBuildError.unsupportedChain(chain)
        }

        let normalizedContract = try normalizedOpenSeaAddress(contract)
        let normalizedTokenID = tokenID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTokenID.isEmpty else {
            throw ExplorerURLBuildError.invalidTokenID(tokenID)
        }

        guard let url = URL(string: "https://opensea.io/assets/\(chainSlug)/\(normalizedContract)/\(normalizedTokenID)") else {
            throw ExplorerURLBuildError.missingExplorerBaseURL(chain)
        }

        return url
    }

    private func openSeaChainSlug(for chain: Chain) -> String? {
        switch chain {
        case .ethMainnet:
            return "ethereum"
        case .baseMainnet:
            return "base"
        case .arbMainnet:
            return "arbitrum"
        case .optMainnet:
            return "optimism"
        case .polygonMainnet:
            return "matic"
        case .zoraMainnet:
            return "zora"
        default:
            return nil
        }
    }

    private func normalizedOpenSeaAddress(_ address: String) throws -> String {
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedAddress.range(of: #"^0x[a-fA-F0-9]{40}$"#, options: .regularExpression) != nil else {
            throw ExplorerURLBuildError.invalidAddress(address)
        }

        return trimmedAddress
    }
}
