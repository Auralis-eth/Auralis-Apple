import AuralisPrimaryModels
import Foundation
import SwiftData
import SwiftDataAdapters

/// Complete value snapshot used when an account-scoped token library is removed and later undone.
public struct TokenHoldingAccountSnapshot {
    let accountAddress: String
    let chain: Chain
    let contractAddress: String?
    let symbol: String?
    let displayName: String
    let amountDisplay: String
    let balanceKind: TokenHoldingKind
    let updatedAt: Date
    let isPlaceholder: Bool
    let sortPriority: Int

    init(_ holding: TokenHolding) {
        self.accountAddress = holding.accountAddressRawValue
        self.chain = holding.chain
        self.contractAddress = holding.contractAddressRawValue
        self.symbol = holding.symbol
        self.displayName = holding.displayName
        self.amountDisplay = holding.amountDisplay
        self.balanceKind = holding.balanceKind
        self.updatedAt = holding.updatedAt
        self.isPlaceholder = holding.isPlaceholder
        self.sortPriority = holding.sortPriority
    }

    func model() -> TokenHolding {
        TokenHolding(
            accountAddress: accountAddress,
            chain: chain,
            contractAddress: contractAddress,
            symbol: symbol,
            displayName: displayName,
            amountDisplay: amountDisplay,
            balanceKind: balanceKind,
            updatedAt: updatedAt,
            isPlaceholder: isPlaceholder,
            sortPriority: sortPriority
        )
    }
}

/// TokenStorage-owned participation in a caller-coordinated account lifecycle transaction.
public enum TokenHoldingAccountPersistenceParticipant: ScopedPersistenceParticipant {
    public static func capture(scope accountAddress: String, in context: ModelContext) throws -> [TokenHoldingAccountSnapshot] {
        guard context.container.schema.entity(for: TokenHolding.self) != nil else {
            return []
        }
        let descriptor = FetchDescriptor<TokenHolding>(
            predicate: #Predicate<TokenHolding> { holding in
                holding.accountAddressRawValue == accountAddress
            }
        )
        return try context.fetch(descriptor).map(TokenHoldingAccountSnapshot.init)
    }

    public static func delete(scope accountAddress: String, in context: ModelContext) throws {
        for holding in try tokenHoldings(accountAddress: accountAddress, in: context) {
            context.delete(holding)
        }
    }

    public static func restore(_ snapshot: [TokenHoldingAccountSnapshot], in context: ModelContext) throws {
        guard context.container.schema.entity(for: TokenHolding.self) != nil else {
            return
        }
        snapshot.forEach { context.insert($0.model()) }
    }

    private static func tokenHoldings(accountAddress: String, in context: ModelContext) throws -> [TokenHolding] {
        guard context.container.schema.entity(for: TokenHolding.self) != nil else {
            return []
        }
        let descriptor = FetchDescriptor<TokenHolding>(
            predicate: #Predicate<TokenHolding> { holding in
                holding.accountAddressRawValue == accountAddress
            }
        )
        return try context.fetch(descriptor)
    }
}
