import Foundation
import SwiftData

enum TokenHoldingKind: String, Codable, Equatable, Sendable {
    case native
    case erc20
}

@Model
final class TokenHolding {
    #Index<TokenHolding>([\TokenHolding.accountAddressRawValue, \TokenHolding.chainRawValue])

    @Attribute(.unique) var id: String
    var accountAddressRawValue: String
    var chainRawValue: String
    var contractAddressRawValue: String?
    var symbol: String?
    var displayName: String
    var amountDisplay: String
    var balanceKindRawValue: String
    var updatedAt: Date
    var isPlaceholder: Bool
    var sortPriority: Int

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

    var chain: Chain {
        get { Chain(rawValue: chainRawValue) ?? .ethMainnet }
        set { chainRawValue = newValue.rawValue }
    }

    var balanceKind: TokenHoldingKind {
        get { TokenHoldingKind(rawValue: balanceKindRawValue) ?? .erc20 }
        set { balanceKindRawValue = newValue.rawValue }
    }

    var contractAddress: String? {
        get { contractAddressRawValue }
        set { contractAddressRawValue = NFT.normalizedScopeComponent(newValue) }
    }

    static func makeScopedID(
        accountAddress: String,
        chain: Chain,
        contractAddress: String?,
        balanceKind: TokenHoldingKind
    ) -> String {
        let resolvedContractAddress = contractAddress ?? balanceKind.rawValue
        return "\(accountAddress):\(chain.rawValue):\(resolvedContractAddress)"
    }

    static func defaultSortPriority(for balanceKind: TokenHoldingKind) -> Int {
        switch balanceKind {
        case .native:
            return 0
        case .erc20:
            return 1
        }
    }
}

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
            self.subtitle = "\(holding.chain.routingDisplayName) native asset"
        case .erc20:
            if holding.hidesAmountUntilMetadataLoads {
                self.subtitle = "Amount hidden until token decimals load"
            } else if let contractAddress = holding.contractAddress, !contractAddress.isEmpty {
                self.subtitle = contractAddress.displayAddress
            } else if holding.isPlaceholder {
                self.subtitle = "Placeholder token metadata"
            } else {
                self.subtitle = holding.chain.routingDisplayName
            }
        }
    }

    var canOpenDetail: Bool {
        kind == .erc20 && (contractAddress?.isEmpty == false)
    }
}

extension TokenHolding {
    static let hiddenAmountDisplay = "Amount hidden"

    var hidesAmountUntilMetadataLoads: Bool {
        amountDisplay == Self.hiddenAmountDisplay
    }

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
