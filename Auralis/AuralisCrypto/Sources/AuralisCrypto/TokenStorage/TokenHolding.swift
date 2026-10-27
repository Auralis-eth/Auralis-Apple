import Foundation
import SwiftData

/// Distinguishes native balances from ERC-20 balances in the holdings library.
public enum TokenHoldingKind: String, Codable, Equatable, Sendable {
    case native
    case erc20
}

@Model
public final class TokenHolding {
    #Index<TokenHolding>([\TokenHolding.accountAddressRawValue, \TokenHolding.chainRawValue])

    @Attribute(.unique) public var id: String
    public var accountAddressRawValue: String
    public var chainRawValue: String
    public var contractAddressRawValue: String?
    public var symbol: String?
    public var displayName: String
    public var amountDisplay: String
    public var balanceKindRawValue: String
    public var updatedAt: Date
    public var isPlaceholder: Bool
    public var sortPriority: Int

    public init(
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

    public var chain: Chain {
        get { Chain(rawValue: chainRawValue) ?? .ethMainnet }
        set { chainRawValue = newValue.rawValue }
    }

    public var resolvedChain: Chain? {
        Chain.resolved(rawValue: chainRawValue)
    }

    public var balanceKind: TokenHoldingKind {
        get { TokenHoldingKind(rawValue: balanceKindRawValue) ?? .erc20 }
        set { balanceKindRawValue = newValue.rawValue }
    }

    public var contractAddress: String? {
        get { contractAddressRawValue }
        set { contractAddressRawValue = NFT.normalizedScopeComponent(newValue) }
    }

    public static func makeScopedID(
        accountAddress: String,
        chain: Chain,
        contractAddress: String?,
        balanceKind: TokenHoldingKind
    ) -> String {
        let resolvedContractAddress = contractAddress ?? balanceKind.rawValue
        return "\(accountAddress):\(chain.rawValue):\(resolvedContractAddress)"
    }

    public static func defaultSortPriority(for balanceKind: TokenHoldingKind) -> Int {
        switch balanceKind {
        case .native:
            return 0
        case .erc20:
            return 1
        }
    }
}
