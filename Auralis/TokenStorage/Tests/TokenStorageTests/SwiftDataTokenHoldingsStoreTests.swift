import AuralisPrimaryModels
import Foundation
import NFTKit
import SwiftData
import Testing
import TokenStorage

@MainActor
@Suite
struct SwiftDataTokenHoldingsStoreTests {
    @Test("save native token holding for account and chain scope")
    func saveNativeTokenHoldingForAccountAndChainScope() async throws {
        let context = try makeContext()
        let store = SwiftDataTokenHoldingsStore(modelContext: context)
        let updatedAt = Date(timeIntervalSince1970: 100)

        try await store.upsertNativeHolding(
            accountAddress: "0xABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCD",
            chain: .ethMainnet,
            amountDisplay: "1.25 ETH",
            updatedAt: updatedAt
        )

        let holdings = try fetchHoldings(context)

        #expect(holdings.count == 1)
        #expect(holdings.first?.accountAddressRawValue == "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd")
        #expect(holdings.first?.chain == .ethMainnet)
        #expect(holdings.first?.balanceKind == .native)
        #expect(holdings.first?.contractAddress == nil)
        #expect(holdings.first?.symbol == "ETH")
        #expect(holdings.first?.displayName == "Ethereum Native")
        #expect(holdings.first?.amountDisplay == "1.25 ETH")
        #expect(holdings.first?.updatedAt == updatedAt)
    }

    @Test("fetch token holdings by account and chain scope")
    func fetchTokenHoldingsByAccountAndChainScope() async throws {
        let context = try makeContext()
        let store = SwiftDataTokenHoldingsStore(modelContext: context)
        let accountAddress = "0x1111111111111111111111111111111111111111"

        try await store.replaceERC20Holdings(
            accountAddress: accountAddress,
            chain: .baseMainnet,
            holdings: [
                makeProviderHolding(contractAddress: "0xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", symbol: "AAA"),
                makeProviderHolding(contractAddress: "0xBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB", symbol: "BBB"),
            ]
        )

        let holdings = try fetchHoldings(
            context,
            accountAddress: accountAddress,
            chain: .baseMainnet,
            balanceKind: .erc20
        )

        #expect(holdings.compactMap(\.contractAddressRawValue).sorted() == [
            "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
        ])
        #expect(holdings.allSatisfy { $0.accountAddressRawValue == accountAddress })
        #expect(holdings.allSatisfy { $0.chain == .baseMainnet })
        #expect(holdings.allSatisfy { $0.balanceKind == .erc20 })
    }

    @Test("replace stale ERC-20 holdings without leaking across scopes")
    func replaceStaleERC20HoldingsWithoutLeakingAcrossScopes() async throws {
        let context = try makeContext()
        let store = SwiftDataTokenHoldingsStore(modelContext: context)
        let primaryAccount = "0x1111111111111111111111111111111111111111"
        let otherAccount = "0x2222222222222222222222222222222222222222"

        try await store.replaceERC20Holdings(
            accountAddress: primaryAccount,
            chain: .ethMainnet,
            holdings: [
                makeProviderHolding(contractAddress: "0xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", symbol: "AAA"),
                makeProviderHolding(contractAddress: "0xBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB", symbol: "BBB"),
            ]
        )
        try await store.replaceERC20Holdings(
            accountAddress: primaryAccount,
            chain: .baseMainnet,
            holdings: [
                makeProviderHolding(contractAddress: "0xCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC", symbol: "CCC"),
            ]
        )
        try await store.replaceERC20Holdings(
            accountAddress: otherAccount,
            chain: .ethMainnet,
            holdings: [
                makeProviderHolding(contractAddress: "0xDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD", symbol: "DDD"),
            ]
        )

        try await store.replaceERC20Holdings(
            accountAddress: primaryAccount,
            chain: .ethMainnet,
            holdings: [
                makeProviderHolding(contractAddress: "0xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", symbol: "AAA"),
            ]
        )

        let primaryEthHoldings = try fetchHoldings(
            context,
            accountAddress: primaryAccount,
            chain: .ethMainnet,
            balanceKind: .erc20
        )
        let primaryBaseHoldings = try fetchHoldings(
            context,
            accountAddress: primaryAccount,
            chain: .baseMainnet,
            balanceKind: .erc20
        )
        let otherEthHoldings = try fetchHoldings(
            context,
            accountAddress: otherAccount,
            chain: .ethMainnet,
            balanceKind: .erc20
        )

        #expect(primaryEthHoldings.compactMap(\.contractAddressRawValue) == [
            "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        ])
        #expect(primaryBaseHoldings.compactMap(\.contractAddressRawValue) == [
            "0xcccccccccccccccccccccccccccccccccccccccc",
        ])
        #expect(otherEthHoldings.compactMap(\.contractAddressRawValue) == [
            "0xdddddddddddddddddddddddddddddddddddddddd",
        ])
    }

    @Test("metadata freshness fields are persisted")
    func metadataFreshnessFieldsArePersisted() async throws {
        let context = try makeContext()
        let store = SwiftDataTokenHoldingsStore(modelContext: context)
        let updatedAt = Date(timeIntervalSinceNow: -60)

        try await store.replaceERC20Holdings(
            accountAddress: "0x3333333333333333333333333333333333333333",
            chain: .polygonMainnet,
            holdings: [
                makeProviderHolding(
                    contractAddress: "0xEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE",
                    symbol: nil,
                    displayName: "Metadata Pending",
                    amountDisplay: TokenHolding.hiddenAmountDisplay,
                    updatedAt: updatedAt,
                    isPlaceholder: true,
                    isAmountHidden: true
                ),
            ]
        )

        let holding = try #require(fetchHoldings(context).first)

        #expect(holding.updatedAt == updatedAt)
        #expect(holding.isPlaceholder)
        #expect(holding.hidesAmountUntilMetadataLoads)
        #expect(!holding.hasStaleMetadata)
    }

    @Test("clear all token holdings")
    func clearAllTokenHoldings() async throws {
        let context = try makeContext()
        let store = SwiftDataTokenHoldingsStore(modelContext: context)

        try await store.upsertNativeHolding(
            accountAddress: "0x4444444444444444444444444444444444444444",
            chain: .ethMainnet,
            amountDisplay: "2 ETH",
            updatedAt: .now
        )
        try await store.replaceERC20Holdings(
            accountAddress: "0x4444444444444444444444444444444444444444",
            chain: .ethMainnet,
            holdings: [
                makeProviderHolding(contractAddress: "0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF", symbol: "FFF"),
            ]
        )

        try await store.clearAll()

        #expect(try fetchHoldings(context).isEmpty)
    }

    @Test("invalid account scope throws")
    func invalidAccountScopeThrows() async throws {
        let context = try makeContext()
        let store = SwiftDataTokenHoldingsStore(modelContext: context)

        await #expect(throws: TokenHoldingsStoreError.invalidAccountAddress("   ")) {
            try await store.upsertNativeHolding(
                accountAddress: "   ",
                chain: .ethMainnet,
                amountDisplay: "1 ETH",
                updatedAt: .now
            )
        }
    }
}

private func makeContext() throws -> ModelContext {
    let container = try ModelContainer(
        for: Schema([TokenHolding.self]),
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return ModelContext(container)
}

private func fetchHoldings(
    _ context: ModelContext,
    accountAddress: String? = nil,
    chain: Chain? = nil,
    balanceKind: TokenHoldingKind? = nil
) throws -> [TokenHolding] {
    let allHoldings = try context.fetch(FetchDescriptor<TokenHolding>())
    return allHoldings
        .filter { holding in
            (accountAddress == nil || holding.accountAddressRawValue == accountAddress) &&
            (chain == nil || holding.chain == chain) &&
            (balanceKind == nil || holding.balanceKind == balanceKind)
        }
        .sorted { lhs, rhs in
            lhs.id < rhs.id
        }
}

private func makeProviderHolding(
    contractAddress: String,
    symbol: String?,
    displayName: String? = nil,
    amountDisplay: String = "10.0",
    updatedAt: Date = Date(timeIntervalSince1970: 100),
    isPlaceholder: Bool = false,
    isAmountHidden: Bool = false
) -> ProviderTokenHolding {
    ProviderTokenHolding(
        contractAddress: contractAddress,
        symbol: symbol,
        displayName: displayName ?? symbol ?? "Token",
        amountDisplay: amountDisplay,
        updatedAt: updatedAt,
        isPlaceholder: isPlaceholder,
        isAmountHidden: isAmountHidden
    )
}
