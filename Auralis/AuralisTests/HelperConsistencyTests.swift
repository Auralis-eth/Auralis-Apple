@testable import Auralis
import AuralisPrimaryModels
import SwiftData
import SwiftUI
import Testing

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

    @Test("playlist persistence coalesces duplicate identifiers into one stored row")
    @MainActor
    func playlistPersistenceCoalescesDuplicateIdentifiers() throws {
        let container = try makePlaylistContainer()
        let context = ModelContext(container)
        let sharedID = UUID()

        context.insert(Playlist(title: "First", id: sharedID))
        try context.save()
        context.insert(Playlist(title: "Second", id: sharedID))
        try context.save()

        let playlists = try context.fetch(FetchDescriptor<Playlist>())

        #expect(playlists.count == 1)
        #expect(playlists.first?.id == sharedID)
        #expect(playlists.first?.title == "Second")
    }

    @Test("playlist tracks relationship survives a save and refetch")
    @MainActor
    func playlistTracksRelationshipPersistsAcrossFetch() throws {
        let container = try makePlaylistContainer()
        let context = ModelContext(container)
        let nft = makeFixtureNFT(tokenId: "playlist-track")
        let playlist = Playlist(title: "Scoped Tracks", tracks: [nft])

        context.insert(playlist)
        try context.save()

        let persistedPlaylists = try context.fetch(FetchDescriptor<Playlist>())
        let persistedPlaylist = try #require(persistedPlaylists.first)

        #expect(persistedPlaylist.tracks.count == 1)
        #expect(persistedPlaylist.tracks.first?.id == nft.id)
    }

    @Test("deleting an NFT cascades its owned child models")
    @MainActor
    func deletingNFTCascadesOwnedChildModels() throws {
        let container = try makePlaylistContainer()
        let context = ModelContext(container)
        let nft = makeFixtureNFT(
            tokenId: "cascade-child-models",
            includeOwnedChildren: true
        )

        context.insert(nft)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<NFT.Image>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<NFT.Raw>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<NFT.AcquiredAt>()).count == 1)

        context.delete(nft)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<NFT>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<NFT.Image>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<NFT.Raw>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<NFT.AcquiredAt>()).isEmpty)
    }

    @Test("duplicate EOAccount addresses coalesce into one stored row")
    @MainActor
    func duplicateAccountsCoalesceToSingleRow() throws {
        let schema = Schema([EOAccount.self])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let sharedAddress = "0x1234567890abcdef1234567890abcdef12345678"

        context.insert(EOAccount(address: sharedAddress, name: "First"))
        try context.save()
        context.insert(EOAccount(address: sharedAddress, name: "Second"))
        try context.save()

        let accounts = try context.fetch(FetchDescriptor<EOAccount>())

        #expect(accounts.count == 1)
        #expect(accounts.first?.address == sharedAddress)
        #expect(accounts.first?.name == "Second")
    }

    @Test("native holdings persist by account and chain scope")
    @MainActor
    func nativeHoldingsPersistByScope() async throws {
        let container = try makeTokenHoldingContainer()
        let context = ModelContext(container)
        let store = TokenHoldingsStore(modelContext: context)

        try await store.upsertNativeHolding(
            accountAddress: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .ethMainnet,
            amountDisplay: "1.5 ETH",
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        try await store.upsertNativeHolding(
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
    func nativeHoldingUpsertReusesScopedRow() async throws {
        let container = try makeTokenHoldingContainer()
        let context = ModelContext(container)
        let store = TokenHoldingsStore(modelContext: context)

        try await store.upsertNativeHolding(
            accountAddress: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .ethMainnet,
            amountDisplay: "1.5 ETH",
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        try await store.upsertNativeHolding(
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
    func tokenHoldingsStayScopedAcrossAccountAndChain() async throws {
        let container = try makeTokenHoldingContainer()
        let context = ModelContext(container)
        let store = TokenHoldingsStore(modelContext: context)

        try await store.upsertNativeHolding(
            accountAddress: "0x1111111111111111111111111111111111111111",
            chain: .ethMainnet,
            amountDisplay: "1.0 ETH",
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        try await store.upsertNativeHolding(
            accountAddress: "0x2222222222222222222222222222222222222222",
            chain: .ethMainnet,
            amountDisplay: "2.0 ETH",
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        try await store.upsertNativeHolding(
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

    @Test("token holding row model hides ERC-20 amounts until decimals are known")
    func tokenHoldingRowModelFlagsHiddenAmounts() {
        let hiddenAmountHolding = TokenHolding(
            accountAddress: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .baseMainnet,
            contractAddress: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
            symbol: "USDC",
            displayName: "USD Coin",
            amountDisplay: "Amount hidden",
            balanceKind: .erc20,
            updatedAt: Date(timeIntervalSince1970: 100),
            isPlaceholder: true
        )

        let row = TokenHoldingRowModel(holding: hiddenAmountHolding)

        #expect(row.amountDisplay == "Amount hidden")
        #expect(row.subtitle == "Amount hidden until token decimals load")
    }

    @Test("token holding row model marks stale ERC-20 metadata after the freshness window expires")
    func tokenHoldingRowModelMarksStaleMetadata() {
        let staleHolding = TokenHolding(
            accountAddress: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .baseMainnet,
            contractAddress: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
            symbol: "USDC",
            displayName: "USD Coin",
            amountDisplay: "15 USDC",
            balanceKind: .erc20,
            updatedAt: Date(timeIntervalSinceNow: -(TokenHoldingsMetadataFreshnessPolicy.ttl + 60)),
            isPlaceholder: false
        )

        let row = TokenHoldingRowModel(holding: staleHolding)

        #expect(row.isMetadataStale)
        #expect(row.subtitle == "0xa0b8...eb48")
    }

    @Test("provider-backed ERC-20 replacement updates the active scope and removes stale token rows")
    @MainActor
    func replacingScopedERC20HoldingsReconcilesRows() async throws {
        let container = try makeTokenHoldingContainer()
        let context = ModelContext(container)
        let store = TokenHoldingsStore(modelContext: context)

        try await store.replaceERC20Holdings(
            accountAddress: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .ethMainnet,
            holdings: [
                ProviderTokenHolding(
                    contractAddress: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
                    symbol: "USDC",
                    displayName: "USD Coin",
                    amountDisplay: "15.25 USDC",
                    updatedAt: Date(timeIntervalSince1970: 100),
                    isPlaceholder: false,
                    isAmountHidden: false
                ),
                ProviderTokenHolding(
                    contractAddress: "0x6b175474e89094c44da98b954eedeac495271d0f",
                    symbol: "DAI",
                    displayName: "Dai",
                    amountDisplay: "7.5 DAI",
                    updatedAt: Date(timeIntervalSince1970: 100),
                    isPlaceholder: false,
                    isAmountHidden: false
                )
            ]
        )

        try await store.replaceERC20Holdings(
            accountAddress: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .ethMainnet,
            holdings: [
                ProviderTokenHolding(
                    contractAddress: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
                    symbol: "USDC",
                    displayName: "USD Coin",
                    amountDisplay: "20 USDC",
                    updatedAt: Date(timeIntervalSince1970: 200),
                    isPlaceholder: false,
                    isAmountHidden: false
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

    private func makeFixtureNFT(
        tokenId: String,
        accountAddress: String = "0x1111111111111111111111111111111111111111",
        contractAddress: String = "0x495f947276749ce646f68ac8c248420045cb7b5e",
        includeOwnedChildren: Bool = false
    ) -> NFT {
        let network: Chain = .ethMainnet
        let normalizedAccountAddress = NFT.normalizedScopeComponent(accountAddress) ?? "unscoped"
        let normalizedContractAddress = NFT.normalizedScopeComponent(contractAddress) ?? "unknown"

        return NFT(
            id: "\(normalizedAccountAddress):\(network.rawValue):\(normalizedContractAddress):\(tokenId)",
            contract: NFT.Contract(address: contractAddress, chain: network),
            tokenId: tokenId,
            name: "Fixture \(tokenId)",
            image: includeOwnedChildren ? NFT.Image(
                originalUrl: "https://example.com/\(tokenId).png",
                thumbnailUrl: "https://example.com/\(tokenId)-thumb.png"
            ) : nil,
            raw: includeOwnedChildren ? NFT.Raw(
                tokenUri: "ipfs://fixture-\(tokenId)",
                metadata: ["title": .string("Fixture \(tokenId)")]
            ) : nil,
            collection: NFT.Collection(
                name: "Fixture Collection",
                chain: network,
                contractAddress: contractAddress
            ),
            tokenUri: "ipfs://fixture-\(tokenId)",
            timeLastUpdated: "2025-01-01T00:00:00Z",
            acquiredAt: includeOwnedChildren ? NFT.AcquiredAt(blockTimestamp: "2025-01-01T00:00:00Z") : nil,
            network: network,
            accountAddress: accountAddress,
            contentType: "audio/mpeg",
            collectionName: "Fixture Collection",
            artistName: "Fixture Artist",
            animationUrl: "https://example.com/\(tokenId).mp3",
            audioUrl: "https://example.com/\(tokenId).mp3"
        )
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
