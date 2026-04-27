import Foundation
import SwiftData

/// Distinguishes native balances from ERC-20 balances in the holdings library.
enum TokenHoldingKind: String, Codable, Equatable, Sendable {
    /// Native asset for the selected chain.
    case native
    /// ERC-20 token balance.
    case erc20
}

@Model
/// Persisted token balance snapshot scoped to an account and chain.
final class TokenHolding {
    #Index<TokenHolding>([\TokenHolding.accountAddressRawValue, \TokenHolding.chainRawValue])

    /// Stable scoped identifier combining account, chain, and token identity.
    @Attribute(.unique) var id: String
    /// Normalized account address used for scoping.
    var accountAddressRawValue: String
    /// Raw chain identifier used for persistence and fetch predicates.
    var chainRawValue: String
    /// Optional normalized ERC-20 contract address.
    var contractAddressRawValue: String?
    /// Token ticker when metadata is available.
    var symbol: String?
    /// User-facing token name for rows and detail views.
    var displayName: String
    /// Preformatted amount string shown in the UI.
    var amountDisplay: String
    /// Raw persisted value for the holding kind.
    var balanceKindRawValue: String
    /// Timestamp of the most recent holdings sync or metadata update.
    var updatedAt: Date
    /// Marks rows created from degraded or partial provider data.
    var isPlaceholder: Bool
    /// Sort precedence used to keep native balances ahead of ERC-20 rows.
    var sortPriority: Int

    /// Creates a persisted token holding scoped to an account, chain, and optional contract.
    init(
        accountAddress: String,
        chain: Chain,
        contractAddress: String? = nil,
        symbol: String?,
        displayName: String,
        amountDisplay: String,
        balanceKind: TokenHoldingKind,
        updatedAt: Date = .now,
        isPlaceholder: Bool = false,
        sortPriority: Int? = nil
    ) {
        let normalizedAccountAddress = NFT.normalizedScopeComponent(accountAddress) ?? "unscoped"
        let normalizedContractAddress = NFT.normalizedScopeComponent(contractAddress)

        self.id = Self.makeScopedID(
            accountAddress: normalizedAccountAddress,
            chain: chain,
            contractAddress: normalizedContractAddress,
            balanceKind: balanceKind
        )
        self.accountAddressRawValue = normalizedAccountAddress
        self.chainRawValue = chain.rawValue
        self.contractAddressRawValue = normalizedContractAddress
        self.symbol = symbol
        self.displayName = displayName
        self.amountDisplay = amountDisplay
        self.balanceKindRawValue = balanceKind.rawValue
        self.updatedAt = updatedAt
        self.isPlaceholder = isPlaceholder
        self.sortPriority = sortPriority ?? Self.defaultSortPriority(for: balanceKind)
    }

    /// Decoded chain value backed by the persisted raw value.
    var chain: Chain {
        get { Chain(rawValue: chainRawValue) ?? .ethMainnet }
        set { chainRawValue = newValue.rawValue }
    }

    var resolvedChain: Chain? {
        Chain.resolved(rawValue: chainRawValue)
    }

    /// Decoded holding kind backed by the persisted raw value.
    var balanceKind: TokenHoldingKind {
        get { TokenHoldingKind(rawValue: balanceKindRawValue) ?? .erc20 }
        set { balanceKindRawValue = newValue.rawValue }
    }

    /// Normalized contract address helper for detail routing and display.
    var contractAddress: String? {
        get { contractAddressRawValue }
        set { contractAddressRawValue = NFT.normalizedScopeComponent(newValue) }
    }

    /// Builds the unique persistence key for a token holding scope.
    static func makeScopedID(
        accountAddress: String,
        chain: Chain,
        contractAddress: String?,
        balanceKind: TokenHoldingKind
    ) -> String {
        let resolvedContractAddress = contractAddress ?? balanceKind.rawValue
        return "\(accountAddress):\(chain.rawValue):\(resolvedContractAddress)"
    }

    /// Default row ordering for each holding kind.
    static func defaultSortPriority(for balanceKind: TokenHoldingKind) -> Int {
        switch balanceKind {
        case .native:
            return 0
        case .erc20:
            return 1
        }
    }
}

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
