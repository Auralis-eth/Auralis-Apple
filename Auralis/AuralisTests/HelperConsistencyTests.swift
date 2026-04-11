import SwiftData
import SwiftUI
import Testing
@testable import Auralis

@Suite
struct HelperConsistencyTests {
    @Test("8 character hex values resolve consistently across helper paths")
    func hexHelpersUseSharedRGBAConvention() {
        let fromColorInit = Color(hexString: "11223344")
        let fromStringHelper = "11223344".toColor()

        #expect(rgbaComponents(fromColorInit) == rgbaComponents(fromStringHelper))
    }

    @Test("Solana formatted chain IDs use the Solana label")
    func solanaFormattedChainIDUsesExpectedLabel() {
        #expect(Chain.solanaMainnet.formattedChainId == "Solana Network")
        #expect(Chain.solanaDevnetTestnet.formattedChainId == "Solana Network")
    }

    @Test("playlist creation persists the trimmed title")
    @MainActor
    func playlistCreationPersistsTrimmedTitle() throws {
        let container = try makePlaylistContainer()
        let context = ModelContext(container)

        let playlist = try context.createPlaylist(title: "  Chill Mix  ")

        #expect(playlist.title == "Chill Mix")
    }

    @Test("native holdings persist by account and chain scope")
    @MainActor
    func nativeHoldingsPersistByScope() throws {
        let container = try makeTokenHoldingContainer()
        let context = ModelContext(container)
        let store = TokenHoldingsStore(modelContext: context)

        try store.upsertNativeHolding(
            accountAddress: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .ethMainnet,
            amountDisplay: "1.5 ETH",
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        try store.upsertNativeHolding(
            accountAddress: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .baseMainnet,
            amountDisplay: "2.0 ETH",
            updatedAt: Date(timeIntervalSince1970: 200)
        )

        let holdings = try context.fetch(FetchDescriptor<TokenHolding>())

        #expect(holdings.count == 2)

        let ethereumHolding = try #require(
            holdings.first(where: {
                $0.accountAddressRawValue == "0x1234567890abcdef1234567890abcdef12345678" &&
                $0.chainRawValue == Chain.ethMainnet.rawValue
            })
        )
        let baseHolding = try #require(
            holdings.first(where: {
                $0.accountAddressRawValue == "0x1234567890abcdef1234567890abcdef12345678" &&
                $0.chainRawValue == Chain.baseMainnet.rawValue
            })
        )

        #expect(ethereumHolding.balanceKind == .native)
        #expect(ethereumHolding.amountDisplay == "1.5 ETH")
        #expect(ethereumHolding.symbol == "ETH")
        #expect(baseHolding.amountDisplay == "2.0 ETH")
        #expect(baseHolding.id != ethereumHolding.id)
    }

    @Test("upserting the same native scope updates one persisted row instead of duplicating it")
    @MainActor
    func nativeHoldingUpsertReusesScopedRow() throws {
        let container = try makeTokenHoldingContainer()
        let context = ModelContext(container)
        let store = TokenHoldingsStore(modelContext: context)

        try store.upsertNativeHolding(
            accountAddress: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .ethMainnet,
            amountDisplay: "1.5 ETH",
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        try store.upsertNativeHolding(
            accountAddress: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .ethMainnet,
            amountDisplay: "1.75 ETH",
            updatedAt: Date(timeIntervalSince1970: 200)
        )

        let holdings = try context.fetch(FetchDescriptor<TokenHolding>())

        #expect(holdings.count == 1)
        #expect(holdings[0].amountDisplay == "1.75 ETH")
        #expect(holdings[0].updatedAt == Date(timeIntervalSince1970: 200))
    }

    @Test("token holding persistence stays isolated across account and chain boundaries")
    @MainActor
    func tokenHoldingsStayScopedAcrossAccountAndChain() throws {
        let container = try makeTokenHoldingContainer()
        let context = ModelContext(container)
        let store = TokenHoldingsStore(modelContext: context)

        try store.upsertNativeHolding(
            accountAddress: "0x1111111111111111111111111111111111111111",
            chain: .ethMainnet,
            amountDisplay: "1.0 ETH",
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        try store.upsertNativeHolding(
            accountAddress: "0x2222222222222222222222222222222222222222",
            chain: .ethMainnet,
            amountDisplay: "2.0 ETH",
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        try store.upsertNativeHolding(
            accountAddress: "0x1111111111111111111111111111111111111111",
            chain: .baseMainnet,
            amountDisplay: "3.0 ETH",
            updatedAt: Date(timeIntervalSince1970: 300)
        )

        let holdings = try context.fetch(FetchDescriptor<TokenHolding>())

        #expect(holdings.count == 3)
        #expect(
            Set(holdings.map(\.id)) == [
                TokenHolding.makeScopedID(
                    accountAddress: "0x1111111111111111111111111111111111111111",
                    chain: .ethMainnet,
                    contractAddress: nil,
                    balanceKind: .native
                ),
                TokenHolding.makeScopedID(
                    accountAddress: "0x2222222222222222222222222222222222222222",
                    chain: .ethMainnet,
                    contractAddress: nil,
                    balanceKind: .native
                ),
                TokenHolding.makeScopedID(
                    accountAddress: "0x1111111111111111111111111111111111111111",
                    chain: .baseMainnet,
                    contractAddress: nil,
                    balanceKind: .native
                )
            ]
        )
    }

    @Test("token holding row model remains readable when ERC-20 metadata is missing")
    func tokenHoldingRowModelSupportsPlaceholderMetadata() {
        let placeholderHolding = TokenHolding(
            accountAddress: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .ethMainnet,
            contractAddress: nil,
            symbol: nil,
            displayName: "Unknown Token",
            amountDisplay: "Balance unavailable",
            balanceKind: .erc20,
            updatedAt: Date(timeIntervalSince1970: 100),
            isPlaceholder: true
        )

        let row = TokenHoldingRowModel(holding: placeholderHolding)

        #expect(row.title == "Unknown Token")
        #expect(row.amountDisplay == "Balance unavailable")
        #expect(row.subtitle == "Placeholder token metadata")
        #expect(row.canOpenDetail == false)
    }

    @Test("provider-backed ERC-20 replacement updates the active scope and removes stale token rows")
    @MainActor
    func replacingScopedERC20HoldingsReconcilesRows() throws {
        let container = try makeTokenHoldingContainer()
        let context = ModelContext(container)
        let store = TokenHoldingsStore(modelContext: context)

        try store.replaceERC20Holdings(
            accountAddress: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .ethMainnet,
            holdings: [
                ProviderTokenHolding(
                    contractAddress: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
                    symbol: "USDC",
                    displayName: "USD Coin",
                    amountDisplay: "15.25 USDC",
                    updatedAt: Date(timeIntervalSince1970: 100),
                    isPlaceholder: false
                ),
                ProviderTokenHolding(
                    contractAddress: "0x6b175474e89094c44da98b954eedeac495271d0f",
                    symbol: "DAI",
                    displayName: "Dai",
                    amountDisplay: "7.5 DAI",
                    updatedAt: Date(timeIntervalSince1970: 100),
                    isPlaceholder: false
                )
            ]
        )

        try store.replaceERC20Holdings(
            accountAddress: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .ethMainnet,
            holdings: [
                ProviderTokenHolding(
                    contractAddress: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
                    symbol: "USDC",
                    displayName: "USD Coin",
                    amountDisplay: "20 USDC",
                    updatedAt: Date(timeIntervalSince1970: 200),
                    isPlaceholder: false
                )
            ]
        )

        let holdings = try context.fetch(FetchDescriptor<TokenHolding>())
            .filter { $0.balanceKind == .erc20 }
            .sorted { $0.displayName < $1.displayName }

        #expect(holdings.count == 1)
        #expect(holdings[0].contractAddress == "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48")
        #expect(holdings[0].amountDisplay == "20 USDC")
        #expect(holdings[0].updatedAt == Date(timeIntervalSince1970: 200))
    }

    @MainActor
    private func makePlaylistContainer() throws -> ModelContainer {
        let schema = Schema([Playlist.self, NFT.self, Tag.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @MainActor
    private func makeTokenHoldingContainer() throws -> ModelContainer {
        let schema = Schema([TokenHolding.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func rgbaComponents(_ color: Color) -> [CGFloat] {
        #if canImport(UIKit)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return [red, green, blue, alpha]
        #else
        return []
        #endif
    }
}
