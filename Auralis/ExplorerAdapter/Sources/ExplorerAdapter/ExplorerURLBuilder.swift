import AuralisPrimaryModels
import Foundation

public struct ExplorerURLBuilder: ExplorerURLBuilding, Sendable {
    private let catalog: ExplorerCatalog

    public init(catalog: ExplorerCatalog = .default) {
        self.catalog = catalog
    }

    public func url(for destination: ExplorerDestination) throws -> URL {
        switch destination {
        case .address(let address, let chain):
            let normalizedAddress = try normalizedEthereumAddress(address)
            return try explorerURL(chain: chain, path: "address/\(normalizedAddress)")
        case .transaction(let hash, let chain):
            let normalizedHash = try normalizedTransactionHash(hash)
            return try explorerURL(chain: chain, path: "tx/\(normalizedHash)")
        case .token(let contract, let chain):
            let normalizedContract = try normalizedEthereumAddress(contract)
            return try explorerURL(chain: chain, path: "token/\(normalizedContract)")
        case .nft(let contract, let tokenID, let chain):
            let normalizedContract = try normalizedEthereumAddress(contract)
            let normalizedTokenID = try normalizedTokenID(tokenID)
            return try explorerURL(chain: chain, path: "token/\(normalizedContract)", queryItems: [
                URLQueryItem(name: "a", value: normalizedTokenID),
            ])
        }
    }

    public func label(for chain: Chain) -> String? {
        catalog.entry(for: chain)?.label
    }

    private func explorerURL(
        chain: Chain,
        path: String,
        queryItems: [URLQueryItem] = []
    ) throws -> URL {
        guard let entry = catalog.entry(for: chain) else {
            throw ExplorerURLBuildError.unsupportedChain(chain)
        }

        guard var components = URLComponents(url: entry.baseURL, resolvingAgainstBaseURL: false) else {
            throw ExplorerURLBuildError.missingExplorerBaseURL(chain)
        }

        components.path = "/" + path
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components.url else {
            throw ExplorerURLBuildError.missingExplorerBaseURL(chain)
        }

        return url
    }
}

private func normalizedEthereumAddress(_ address: String) throws -> String {
    let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
    let prefixedPattern = #"^0x[a-fA-F0-9]{40}$"#
    let unprefixedPattern = #"^[a-fA-F0-9]{40}$"#

    if trimmedAddress.range(of: prefixedPattern, options: .regularExpression) != nil {
        return trimmedAddress
    }

    if trimmedAddress.range(of: unprefixedPattern, options: .regularExpression) != nil {
        return "0x" + trimmedAddress
    }

    throw ExplorerURLBuildError.invalidAddress(address)
}

private func normalizedTransactionHash(_ hash: String) throws -> String {
    let trimmedHash = hash.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmedHash.range(of: #"^0x[a-fA-F0-9]{64}$"#, options: .regularExpression) != nil else {
        throw ExplorerURLBuildError.invalidTransactionHash(hash)
    }

    return trimmedHash
}

private func normalizedTokenID(_ tokenID: String) throws -> String {
    let trimmedTokenID = tokenID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedTokenID.isEmpty else {
        throw ExplorerURLBuildError.invalidTokenID(tokenID)
    }

    return trimmedTokenID
}
