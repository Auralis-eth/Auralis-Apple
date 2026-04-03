import Foundation
import SwiftData

@MainActor
struct TokenHoldingsStore {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func upsertNativeHolding(
        accountAddress: String,
        chain: Chain,
        amountDisplay: String,
        updatedAt: Date
    ) throws {
        guard let normalizedAccountAddress = NFT.normalizedScopeComponent(accountAddress) else {
            return
        }

        let id = TokenHolding.makeScopedID(
            accountAddress: normalizedAccountAddress,
            chain: chain,
            contractAddress: nil,
            balanceKind: .native
        )
        let descriptor = FetchDescriptor<TokenHolding>(
            predicate: #Predicate<TokenHolding> { holding in
                holding.id == id
            }
        )

        let holding = try modelContext.fetch(descriptor).first ?? {
            let newHolding = TokenHolding(
                accountAddress: normalizedAccountAddress,
                chain: chain,
                symbol: chain.nativeTokenSymbol,
                displayName: chain.nativeTokenDisplayName,
                amountDisplay: amountDisplay,
                balanceKind: .native,
                updatedAt: updatedAt
            )
            modelContext.insert(newHolding)
            return newHolding
        }()

        holding.chain = chain
        holding.symbol = chain.nativeTokenSymbol
        holding.displayName = chain.nativeTokenDisplayName
        holding.amountDisplay = amountDisplay
        holding.updatedAt = updatedAt
        holding.balanceKind = .native
        holding.sortPriority = TokenHolding.defaultSortPriority(for: .native)
        holding.isPlaceholder = false

        try modelContext.save()
    }
}
