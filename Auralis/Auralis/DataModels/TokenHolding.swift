import AuralisPrimaryModels
import Foundation
import NFTDomain
import NFTPersistence
import NFTPresentation
import NFTProviderAdapters
import TokenStorage

/// Presentation model for token rows rendered in the ERC-20 and holdings surfaces.
struct TokenHoldingRowModel: Identifiable, Equatable {
    let id: String
    let kind: TokenHoldingKind
    let title: String
    let symbol: String?
    let amountDisplay: String
    let subtitle: String
    let contractAddress: String?
    let updatedAt: Date
    let isPlaceholder: Bool
    let isAmountHidden: Bool
    let isMetadataStale: Bool

    init(holding: TokenHolding, now: Date = Date()) {
        self.id = holding.id
        self.kind = holding.balanceKind
        self.title = holding.displayName
        self.symbol = holding.symbol
        self.amountDisplay = holding.amountDisplay
        self.contractAddress = holding.contractAddress
        self.updatedAt = holding.updatedAt
        self.isPlaceholder = holding.isPlaceholder
        self.isAmountHidden = holding.hidesAmountUntilMetadataLoads
        self.isMetadataStale = holding.hasStaleMetadata(referenceDate: now)

        switch holding.balanceKind {
        case .native:
            if let resolvedChain = holding.resolvedChain {
                self.subtitle = "\(resolvedChain.routingDisplayName) native asset"
            } else {
                self.subtitle = "Unknown chain native asset"
            }
        case .erc20:
            if holding.hidesAmountUntilMetadataLoads {
                self.subtitle = "Amount hidden until token decimals load"
            } else if let contractAddress = holding.contractAddress, !contractAddress.isEmpty {
                self.subtitle = contractAddress.displayAddress
            } else if holding.isPlaceholder {
                self.subtitle = "Placeholder token metadata"
            } else if let resolvedChain = holding.resolvedChain {
                self.subtitle = resolvedChain.routingDisplayName
            } else {
                self.subtitle = "Unknown chain"
            }
        }
    }

    /// Whether the row has enough information to open a detail route.
    var canOpenDetail: Bool {
        kind == .erc20 && (contractAddress?.isEmpty == false)
    }
}
