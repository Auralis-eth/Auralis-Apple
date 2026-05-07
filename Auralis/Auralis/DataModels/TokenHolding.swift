import AuralisPrimaryModels
import Foundation

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

    init(holding: TokenHolding) {
        self.id = holding.id
        self.kind = holding.balanceKind
        self.title = holding.displayName
        self.symbol = holding.symbol
        self.amountDisplay = holding.amountDisplay
        self.contractAddress = holding.contractAddress
        self.updatedAt = holding.updatedAt
        self.isPlaceholder = holding.isPlaceholder
        self.isAmountHidden = holding.hidesAmountUntilMetadataLoads
        self.isMetadataStale = holding.hasStaleMetadata

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

extension TokenHolding {
    /// Placeholder amount string used until metadata finishes loading.
    static let hiddenAmountDisplay = "Amount hidden"

    /// Whether the amount should stay hidden until token metadata resolves.
    var hidesAmountUntilMetadataLoads: Bool {
        amountDisplay == Self.hiddenAmountDisplay
    }

    /// Whether the stored metadata should be considered stale for UI messaging.
    var hasStaleMetadata: Bool {
        balanceKind == .erc20 && TokenHoldingsMetadataFreshnessPolicy.isStale(updatedAt: updatedAt)
    }
}

extension Chain {
    var nativeTokenSymbol: String {
        switch self {
        case .polygonMainnet, .polygonAmoyTestnet:
            return "POL"
        case .optMainnet, .optSepoliaTestnet:
            return "ETH"
        case .arbMainnet, .arbSepoliaTestnet, .arbNovaMainnet:
            return "ETH"
        case .baseMainnet, .baseSepoliaTestnet:
            return "ETH"
        case .worldchainMainnet, .worldchainSepoliaTestnet:
            return "ETH"
        case .shapeMainnet, .shapeSepoliaTestnet:
            return "ETH"
        case .inkMainnet, .inkSepoliaTestnet:
            return "ETH"
        case .unichainMainnet, .unichainSepoliaTestnet:
            return "ETH"
        case .soneiumMainnet, .soneiumMinatoTestnet:
            return "ETH"
        case .solanaMainnet, .solanaDevnetTestnet:
            return "SOL"
        case .berachainMainnet:
            return "BERA"
        case .zoraMainnet, .zoraSepoliaTestnet:
            return "ETH"
        case .polynomialMainnet, .polynomialSepoliaTestnet:
            return "ETH"
        case .ethMainnet, .ethSepoliaTestnet:
            return "ETH"
        }
    }

    var nativeTokenDisplayName: String {
        switch self {
        case .polygonMainnet, .polygonAmoyTestnet:
            return "Polygon Native"
        case .solanaMainnet, .solanaDevnetTestnet:
            return "Solana Native"
        case .berachainMainnet:
            return "BeraChain Native"
        default:
            return "\(routingDisplayName) Native"
        }
    }
}
