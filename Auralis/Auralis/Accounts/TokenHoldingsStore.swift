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

    func replaceERC20Holdings(
        accountAddress: String,
        chain: Chain,
        holdings: [ProviderTokenHolding]
    ) throws {
        guard let normalizedAccountAddress = NFT.normalizedScopeComponent(accountAddress) else {
            return
        }

        let existingHoldings = try fetchScopedERC20Holdings(
            accountAddress: normalizedAccountAddress,
            chain: chain
        )
        var existingByID = Dictionary(
            uniqueKeysWithValues: existingHoldings.map { ($0.id, $0) }
        )
        var incomingIDs: Set<String> = []

        for providerHolding in holdings {
            guard let normalizedContractAddress = NFT.normalizedScopeComponent(providerHolding.contractAddress) else {
                continue
            }

            let id = TokenHolding.makeScopedID(
                accountAddress: normalizedAccountAddress,
                chain: chain,
                contractAddress: normalizedContractAddress,
                balanceKind: .erc20
            )
            incomingIDs.insert(id)

            let holding = existingByID[id] ?? {
                let newHolding = TokenHolding(
                    accountAddress: normalizedAccountAddress,
                    chain: chain,
                    contractAddress: normalizedContractAddress,
                    symbol: providerHolding.symbol,
                    displayName: providerHolding.displayName,
                    amountDisplay: providerHolding.amountDisplay,
                    balanceKind: .erc20,
                    updatedAt: providerHolding.updatedAt,
                    isPlaceholder: providerHolding.isPlaceholder
                )
                modelContext.insert(newHolding)
                existingByID[id] = newHolding
                return newHolding
            }()

            holding.chain = chain
            holding.contractAddress = normalizedContractAddress
            holding.symbol = providerHolding.symbol
            holding.displayName = providerHolding.displayName
            holding.amountDisplay = providerHolding.amountDisplay
            holding.updatedAt = providerHolding.updatedAt
            holding.balanceKind = .erc20
            holding.sortPriority = TokenHolding.defaultSortPriority(for: .erc20)
            holding.isPlaceholder = providerHolding.isPlaceholder
        }

        for staleHolding in existingHoldings where !incomingIDs.contains(staleHolding.id) {
            modelContext.delete(staleHolding)
        }

        try modelContext.save()
    }

    private func fetchScopedERC20Holdings(
        accountAddress: String,
        chain: Chain
    ) throws -> [TokenHolding] {
        let balanceKindRawValue = TokenHoldingKind.erc20.rawValue
        let chainRawValue = chain.rawValue
        let descriptor = FetchDescriptor<TokenHolding>(
            predicate: #Predicate<TokenHolding> { holding in
                holding.accountAddressRawValue == accountAddress &&
                holding.chainRawValue == chainRawValue &&
                holding.balanceKindRawValue == balanceKindRawValue
            }
        )

        return try modelContext.fetch(descriptor)
    }

    func clearAll() throws {
        let holdings = try modelContext.fetch(FetchDescriptor<TokenHolding>())
        for holding in holdings {
            modelContext.delete(holding)
        }

        try modelContext.save()
    }
}
