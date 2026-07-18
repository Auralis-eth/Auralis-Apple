@testable import MusicFeature
import AuralisPrimaryModels
import Foundation
import SwiftData
import Testing

@MainActor
struct Phase5NFTDiscoveryIntegrationTests {
    @Test("Scenario A: EVM OpenSea metadata syncs playable audio media")
    func evmOpenSeaHappyPath() async throws {
        let fixture = try Fixture()
        let wallet = "0xABCDEFabcdefABCDEFabcdefABCDEFabcdefABCD"
        let tokens = (1...3).map {
            Fixture.token(wallet: wallet, chain: .ethMainnet, tokenId: "\($0)", metadataRaw: Fixture.openSeaAudioJSON(id: $0))
        }
        await fixture.evm.set(tokens: tokens, for: .ethMainnet)

        try await fixture.coordinator.sync(walletAddress: wallet, chain: .ethMainnet)

        let storedTokens = try fixture.fetchNFTTokens(walletAddress: wallet, chain: .ethMainnet)
        #expect(storedTokens.count == 3)
        let mediaItems = try fixture.fetchMediaItems()
        #expect(mediaItems.count == 3)
        #expect(!mediaItems.contains { !$0.hasAudio })
        #expect(!mediaItems.contains { !$0.isPlayable })
        #expect(mediaItems.allSatisfy { $0.artworkURLString?.hasPrefix("https://media.example/ipfs/") == true })
        #expect(await fixture.indexer.indexedIDs() == [mediaItems.map(\.id)])
        #expect(await waitForCondition { await fixture.prefetcher.requestedURLs().count == 1 })
        #expect(await fixture.prefetcher.requestedURLs().first?.sorted() == mediaItems.compactMap(\.artworkURLString).sorted())
        #expect(fixture.coordinator.progress.state == .complete)
    }

    @Test("Scenario B: Solana Metaplex metadata syncs playable audio media")
    func solanaMetaplexHappyPath() async throws {
        let fixture = try Fixture()
        let wallet = "SolanaOwnerAddress"
        await fixture.solana.set(tokens: [
            Fixture.token(wallet: wallet, chain: .solanaMainnet, contract: nil, tokenId: "mint-1", tokenStandard: "ProgrammableNFT", metadataRaw: Fixture.metaplexAudioJSON(id: 1)),
            Fixture.token(wallet: wallet, chain: .solanaMainnet, contract: nil, tokenId: "mint-2", tokenStandard: "ProgrammableNFT", metadataRaw: Fixture.metaplexAudioJSON(id: 2)),
        ])

        try await fixture.coordinator.sync(walletAddress: wallet, chain: .solanaMainnet)

        let storedTokens = try fixture.fetchNFTTokens(walletAddress: wallet, chain: .solanaMainnet)
        #expect(storedTokens.count == 2)
        let mediaItems = try fixture.fetchMediaItems()
        #expect(mediaItems.count == 2)
        #expect(!mediaItems.contains { !$0.hasAudio })
        #expect(Set(storedTokens.map(\.compositeID)) == [
            "solana-mainnet::mint-1:solanaowneraddress",
            "solana-mainnet::mint-2:solanaowneraddress"
        ])
    }

    @Test("Scenario C: Sound.xyz schema prefers lossless audio and artist metadata")
    func soundXyzSchemaDetection() async throws {
        let fixture = try Fixture()
        let wallet = "0x1234567890abcdef1234567890abcdef12345678"
        await fixture.evm.set(tokens: [
            Fixture.token(wallet: wallet, chain: .baseMainnet, tokenId: "sound-1", metadataRaw: Fixture.soundXyzJSON)
        ], for: .baseMainnet)

        try await fixture.coordinator.sync(walletAddress: wallet, chain: .baseMainnet)

        let mediaItems = try fixture.fetchMediaItems()
        let item = try #require(mediaItems.first)
        #expect(item.playbackURLString == "https://media.example/ipfs/lossless.flac")
        #expect(item.artistName == "Catalog Artist")
        let parsed = MetadataParser().parse(json: Fixture.soundXyzJSON)
        #expect(parsed.schemaVersion == .soundXyz)
    }

    @Test("Scenario D: non-playable tokens persist but are excluded from playable fetches")
    func nonPlayableTokenPersists() async throws {
        let fixture = try Fixture()
        let wallet = "0x1234567890abcdef1234567890abcdef12345678"
        await fixture.evm.set(tokens: [
            Fixture.token(wallet: wallet, chain: .ethMainnet, tokenId: "visual-1", metadataRaw: Fixture.visualOnlyJSON)
        ], for: .ethMainnet)

        try await fixture.coordinator.sync(walletAddress: wallet, chain: .ethMainnet)

        let storedTokens = try fixture.fetchNFTTokens(walletAddress: wallet, chain: .ethMainnet)
        #expect(storedTokens.count == 1)
        let mediaItems = try fixture.fetchMediaItems()
        let item = try #require(mediaItems.first)
        #expect(!item.isPlayable)
        #expect(!item.hasAudio)
        let playableItems = try fixture.fetchPlayableMediaItems()
        #expect(playableItems.isEmpty)
    }

    @Test("Scenario E: animation_url disambiguates audio and video by extension")
    func animationURLDisambiguation() async throws {
        let fixture = try Fixture()
        let wallet = "0x1234567890abcdef1234567890abcdef12345678"
        await fixture.evm.set(tokens: [
            Fixture.token(wallet: wallet, chain: .ethMainnet, tokenId: "mp3", metadataRaw: Fixture.openSeaAnimationJSON(name: "MP3", animationURL: "https://example.com/track.mp3")),
            Fixture.token(wallet: wallet, chain: .ethMainnet, tokenId: "mp4", metadataRaw: Fixture.openSeaAnimationJSON(name: "MP4", animationURL: "https://example.com/video.mp4")),
        ], for: .ethMainnet)

        try await fixture.coordinator.sync(walletAddress: wallet, chain: .ethMainnet)

        let items = Dictionary(uniqueKeysWithValues: try fixture.fetchMediaItems().map { ($0.tokenID, $0) })
        let mp3 = try #require(items["mp3"])
        let mp4 = try #require(items["mp4"])
        #expect(mp3.hasAudio)
        #expect(!mp3.hasVideo)
        #expect(mp3.playbackURLString == "https://example.com/track.mp3")
        #expect(!mp4.hasAudio)
        #expect(mp4.hasVideo)
        #expect(mp4.playbackURLString == "https://example.com/video.mp4")
    }

    @Test("Scenario F: nil metadataRaw falls back to tokenURI metadata fetch")
    func metadataFetchFallback() async throws {
        let fixture = try Fixture()
        let wallet = "0x1234567890abcdef1234567890abcdef12345678"
        await fixture.evm.set(tokens: [
            Fixture.token(wallet: wallet, chain: .ethMainnet, tokenId: "fallback", metadataURL: "ipfs://QmMetadata", metadataRaw: nil)
        ], for: .ethMainnet)
        await fixture.metadataFetcher.set(response: Fixture.openSeaAudioJSON(id: 1), for: "ipfs://QmMetadata")

        try await fixture.coordinator.sync(walletAddress: wallet, chain: .ethMainnet)

        let mediaItems = try fixture.fetchMediaItems()
        let item = try #require(mediaItems.first)
        #expect(item.title == "OpenSea Track 1")
        #expect(item.isPlayable)
        #expect(await fixture.metadataFetcher.requestedURLs() == ["ipfs://QmMetadata"])
    }

    @Test("metadata fetch failure for one token does not abort the remaining batch")
    func metadataFetchFailureContinuesBatch() async throws {
        let fixture = try Fixture()
        let wallet = "0x1234567890abcdef1234567890abcdef12345678"
        await fixture.evm.set(tokens: [
            Fixture.token(wallet: wallet, chain: .ethMainnet, tokenId: "missing", metadataURL: "ipfs://MissingMetadata", metadataRaw: nil),
            Fixture.token(wallet: wallet, chain: .ethMainnet, tokenId: "fetched", metadataURL: "ipfs://FetchedMetadata", metadataRaw: nil)
        ], for: .ethMainnet)
        await fixture.metadataFetcher.set(response: Fixture.openSeaAudioJSON(id: 2), for: "ipfs://FetchedMetadata")

        try await fixture.coordinator.sync(walletAddress: wallet, chain: .ethMainnet)

        let mediaItems = try fixture.fetchMediaItems()
        #expect(mediaItems.count == 2)
        #expect(mediaItems.filter(\.isPlayable).count == 1)
        #expect(Set(await fixture.metadataFetcher.requestedURLs()) == ["ipfs://MissingMetadata", "ipfs://FetchedMetadata"])
        #expect(fixture.coordinator.progress.state == .complete)
    }

    @Test("Scenario G: re-sync marks missing tokens inactive")
    func tokenRevocationMarksInactive() async throws {
        let fixture = try Fixture()
        let wallet = "0x1234567890abcdef1234567890abcdef12345678"
        let firstPage = (1...3).map {
            Fixture.token(wallet: wallet, chain: .ethMainnet, tokenId: "\($0)", metadataRaw: Fixture.openSeaAudioJSON(id: $0))
        }
        await fixture.evm.set(tokens: firstPage, for: .ethMainnet)
        try await fixture.coordinator.sync(walletAddress: wallet, chain: .ethMainnet)

        await fixture.evm.set(tokens: Array(firstPage.prefix(2)), for: .ethMainnet)
        try await fixture.coordinator.sync(walletAddress: wallet, chain: .ethMainnet)

        let tokens = try fixture.fetchNFTTokens(walletAddress: wallet, chain: .ethMainnet)
        #expect(tokens.count == 3)
        #expect(tokens.filter(\.isActive).count == 2)
        #expect(tokens.first { $0.tokenId == "3" }?.isActive == false)
        let inactiveID = try #require(tokens.first { $0.tokenId == "3" }?.compositeID)
        #expect(await fixture.indexer.deletedIDs().last == [inactiveID])
    }

    @Test("Scenario H: syncAll isolates one chain failure from another chain success")
    func partialChainFailure() async throws {
        let fixture = try Fixture(scopes: [
            NFTDiscoveryScope(walletAddress: "0x1234567890abcdef1234567890abcdef12345678", chain: .ethMainnet),
            NFTDiscoveryScope(walletAddress: "0x1234567890abcdef1234567890abcdef12345678", chain: .polygonMainnet),
        ])
        await fixture.evm.setFailure(AuraPlayError.library("Ethereum unavailable."), for: .ethMainnet)
        await fixture.evm.set(tokens: [
            Fixture.token(wallet: "0x1234567890abcdef1234567890abcdef12345678", chain: .polygonMainnet, tokenId: "polygon", metadataRaw: Fixture.openSeaAudioJSON(id: 1))
        ], for: .polygonMainnet)

        try await fixture.coordinator.syncAll()

        let mediaItems = try fixture.fetchMediaItems()
        #expect(mediaItems.count == 1)
        guard case .error(let errors) = fixture.coordinator.progress.state else {
            Issue.record("Expected syncAll to surface a partial failure.")
            return
        }
        #expect(errors.map(\.chain) == [.ethMainnet])
    }

    @Test("Scenario I: syncAllIfNeeded respects the 15 minute debounce")
    func debounceEnforcement() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_800_000_000))
        let defaults = try #require(UserDefaults(suiteName: "phase5-debounce-\(UUID().uuidString)"))
        let fixture = try Fixture(
            scopes: [NFTDiscoveryScope(walletAddress: "0x1234567890abcdef1234567890abcdef12345678", chain: .ethMainnet)],
            defaults: defaults,
            clock: { clock.now }
        )
        await fixture.evm.set(tokens: [
            Fixture.token(wallet: "0x1234567890abcdef1234567890abcdef12345678", chain: .ethMainnet, tokenId: "1", metadataRaw: Fixture.openSeaAudioJSON(id: 1))
        ], for: .ethMainnet)

        try await fixture.coordinator.syncAllIfNeeded()
        clock.advance(by: 5 * 60)
        try await fixture.coordinator.syncAllIfNeeded()
        clock.advance(by: 11 * 60)
        try await fixture.coordinator.syncAllIfNeeded()

        #expect(await fixture.evm.callCount(for: .ethMainnet) == 2)
    }
}

private func waitForCondition(
    maxAttempts: Int = 50,
    condition: @escaping @Sendable () async -> Bool
) async -> Bool {
    for _ in 0..<maxAttempts {
        if await condition() {
            return true
        }
        await Task.yield()
    }
    return false
}

@MainActor
private final class Fixture {
    let evm = MockEVMNFTClient()
    let solana = MockSolanaNFTClient()
    let metadataFetcher = MockMetadataFetcher()
    let tokenStore: AuraPlayNFTTokenService
    let mediaStore: AuraPlayMediaItemService
    let indexer = MockMediaItemIndexer()
    let prefetcher = MockArtworkPrefetcher()
    let coordinator: NFTSyncCoordinator
    private let container: ModelContainer

    init(
        scopes: [NFTDiscoveryScope] = [],
        defaults: UserDefaults = UserDefaults(suiteName: "phase5-\(UUID().uuidString)")!,
        clock: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 1_800_000_000) }
    ) throws {
        container = try AuraPlayModelContainer.make(inMemory: true)
        tokenStore = AuraPlayNFTTokenService(modelContainer: container)
        mediaStore = AuraPlayMediaItemService(modelContainer: container)
        coordinator = NFTSyncCoordinator(
            evmClient: evm,
            solanaClient: solana,
            metadataFetcher: metadataFetcher,
            metadataParser: MetadataParser(),
            mediaClassifier: MediaClassifier(
                urlResolver: URLResolver(configuration: .fixture),
                clock: clock
            ),
            tokenStore: tokenStore,
            mediaStore: mediaStore,
            scopeProvider: MockScopeProvider(scopes: scopes),
            artworkPrefetcher: prefetcher,
            mediaItemIndexer: indexer,
            defaults: defaults,
            clock: clock
        )
    }

    func fetchMediaItems() throws -> [AuraPlayMediaItem] {
        let context = ModelContext(container)
        return try context.fetch(
            FetchDescriptor<AuraPlayMediaItem>(
                sortBy: [SortDescriptor(\.tokenID)]
            )
        )
    }

    func fetchPlayableMediaItems() throws -> [AuraPlayMediaItem] {
        try fetchMediaItems().filter { $0.isPlayable }
    }

    func fetchNFTTokens(walletAddress: String, chain: Chain) throws -> [AuraPlayNFTToken] {
        let context = ModelContext(container)
        let tokens = try context.fetch(
            FetchDescriptor<AuraPlayNFTToken>(
                sortBy: [SortDescriptor(\.tokenId)]
            )
        )
        return tokens.filter {
            $0.walletAddress == NFTTokenDTO.normalizedScopeComponent(walletAddress) &&
            $0.chainRawValue == chain.rawValue
        }
    }

    static func token(
        wallet: String,
        chain: Chain,
        contract: String? = "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
        tokenId: String,
        tokenStandard: String = "ERC721",
        metadataURL: String? = nil,
        metadataRaw: String?
    ) -> NFTTokenDTO {
        NFTTokenDTO(
            chain: chain,
            walletAddress: wallet,
            contractAddress: contract,
            tokenId: tokenId,
            tokenStandard: tokenStandard,
            collectionName: "Phase 5 Collection",
            name: nil,
            metadataURL: metadataURL,
            metadataRaw: metadataRaw,
            provider: chain == .solanaMainnet ? .helius : .alchemy
        )
    }

    static func openSeaAudioJSON(id: Int) -> String {
        """
        {
          "name": "OpenSea Track \(id)",
          "image": "ipfs://cover-\(id).png",
          "animation_url": "ipfs://track-\(id).mp3",
          "attributes": [{"trait_type": "Mood", "value": "Bright"}]
        }
        """
    }

    static func openSeaAnimationJSON(name: String, animationURL: String) -> String {
        """
        {
          "name": "\(name)",
          "image": "https://example.com/\(name).png",
          "animation_url": "\(animationURL)"
        }
        """
    }

    static func metaplexAudioJSON(id: Int) -> String {
        """
        {
          "name": "Solana Track \(id)",
          "symbol": "AURA",
          "image": "https://example.com/sol-\(id).png",
          "properties": {
            "creators": [{"address": "CreatorAddress"}],
            "files": [{"uri": "ipfs://sol-track-\(id).mp3", "type": "audio/mpeg"}]
          }
        }
        """
    }

    static let soundXyzJSON = """
    {
      "name": "Lossless Track",
      "artist": "Catalog Artist",
      "project": "Catalog Project",
      "image": "ipfs://sound-cover.png",
      "losslessAudio": "ipfs://lossless.flac",
      "animation_url": "https://example.com/video.mp4"
    }
    """

    static let visualOnlyJSON = """
    {
      "name": "Visual Only",
      "image": "https://example.com/visual.png"
    }
    """
}

private extension AuraPlayStorageResolutionConfiguration {
    static let fixture = AuraPlayStorageResolutionConfiguration(
        ipfsGatewayURL: URL(string: "https://media.example")!,
        arweaveGatewayURL: URL(string: "https://ar.example")!,
        fallbackIPFSGatewayURLs: [],
        fallbackArweaveGatewayURLs: []
    )
}

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ value: Date) {
        self.value = value
    }

    var now: Date {
        lock.withLock { value }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock {
            value = value.addingTimeInterval(interval)
        }
    }
}

private actor MockEVMNFTClient: EVMNFTDiscovering {
    private var failures: [Chain: Error] = [:]
    private var tokensByChain: [Chain: [NFTTokenDTO]] = [:]
    private var callCounts: [Chain: Int] = [:]

    func set(tokens: [NFTTokenDTO], for chain: Chain) {
        tokensByChain[chain] = tokens
    }

    func setFailure(_ error: Error, for chain: Chain) {
        failures[chain] = error
    }

    func fetchAll(owner: String, chain: Chain) async throws -> [NFTTokenDTO] {
        callCounts[chain, default: 0] += 1
        if let failure = failures[chain] {
            throw failure
        }
        return tokensByChain[chain] ?? []
    }

    func callCount(for chain: Chain) -> Int {
        callCounts[chain, default: 0]
    }
}

private actor MockSolanaNFTClient: SolanaNFTDiscovering {
    private var tokens: [NFTTokenDTO] = []

    func set(tokens: [NFTTokenDTO]) {
        self.tokens = tokens
    }

    func fetchAll(owner: String) async throws -> [NFTTokenDTO] {
        tokens
    }
}

private actor MockMetadataFetcher: TokenMetadataFetching {
    private var responses: [String: String] = [:]
    private var requestedURLValues: [String] = []

    func set(response: String, for url: String) {
        responses[url] = response
    }

    func requestedURLs() -> [String] {
        requestedURLValues
    }

    func fetch(metadataURL: String) async throws -> String {
        requestedURLValues.append(metadataURL)
        guard let response = responses[metadataURL] else {
            throw AuraPlayError.mediaResolution("Missing metadata fixture.")
        }
        return response
    }
}

private struct MockScopeProvider: NFTDiscoveryScopeProviding {
    let scopes: [NFTDiscoveryScope]

    func activeScopes() async throws -> [NFTDiscoveryScope] {
        scopes
    }
}

private actor MockMediaItemIndexer: MediaItemIndexing {
    private var indexedIDBatches: [[String]] = []
    private var deletedIDBatches: [[String]] = []

    func indexedIDs() -> [[String]] {
        indexedIDBatches
    }

    func deletedIDs() -> [[String]] {
        deletedIDBatches
    }

    func indexItems(_ ids: [String]) async {
        indexedIDBatches.append(ids)
    }

    func deleteItems(_ ids: [String]) async {
        deletedIDBatches.append(ids)
    }
}

private actor MockArtworkPrefetcher: ArtworkPrefetching {
    private var requestedURLBatches: [[String]] = []

    func requestedURLs() -> [[String]] {
        requestedURLBatches
    }

    func prefetch(artworkURLs: [String]) async {
        requestedURLBatches.append(artworkURLs)
    }
}
