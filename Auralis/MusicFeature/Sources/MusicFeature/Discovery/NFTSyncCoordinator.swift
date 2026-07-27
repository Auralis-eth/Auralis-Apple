import AuralisPrimaryModels
import Foundation
import Observation

@MainActor
@Observable
public final class NFTSyncCoordinator {
    public private(set) var progress = SyncProgress()

    private let evmClient: any EVMNFTDiscovering
    private let solanaClient: any SolanaNFTDiscovering
    private let metadataFetcher: any TokenMetadataFetching
    private let metadataParser: any MetadataParsing
    private let mediaClassifier: any MediaClassifying
    private let tokenStore: any NFTTokenPersisting
    private let mediaStore: any AuraPlayMediaPersisting
    private let scopeProvider: any NFTDiscoveryScopeProviding
    private let artworkPrefetcher: any ArtworkPrefetching
    private let mediaItemIndexer: any MediaItemIndexing
    private let embeddingQueueProcessor: any EmbeddingQueueProcessing
    private let defaults: UserDefaults
    private let clock: @Sendable () -> Date
    private let syncCooldown: TimeInterval

    public init(
        evmClient: any EVMNFTDiscovering,
        solanaClient: any SolanaNFTDiscovering,
        metadataFetcher: any TokenMetadataFetching,
        metadataParser: any MetadataParsing = MetadataParser(),
        mediaClassifier: any MediaClassifying = MediaClassifier(),
        tokenStore: any NFTTokenPersisting,
        mediaStore: any AuraPlayMediaPersisting,
        scopeProvider: any NFTDiscoveryScopeProviding,
        artworkPrefetcher: any ArtworkPrefetching = NoOpArtworkPrefetcher(),
        mediaItemIndexer: any MediaItemIndexing = NoOpMediaItemIndexer(),
        embeddingQueueProcessor: any EmbeddingQueueProcessing = NoOpEmbeddingQueueProcessor(),
        defaults: UserDefaults = .standard,
        clock: @escaping @Sendable () -> Date = Date.init,
        syncCooldown: TimeInterval = 15 * 60
    ) {
        self.evmClient = evmClient
        self.solanaClient = solanaClient
        self.metadataFetcher = metadataFetcher
        self.metadataParser = metadataParser
        self.mediaClassifier = mediaClassifier
        self.tokenStore = tokenStore
        self.mediaStore = mediaStore
        self.scopeProvider = scopeProvider
        self.artworkPrefetcher = artworkPrefetcher
        self.mediaItemIndexer = mediaItemIndexer
        self.embeddingQueueProcessor = embeddingQueueProcessor
        self.defaults = defaults
        self.clock = clock
        self.syncCooldown = syncCooldown
    }

    public func sync(walletAddress: String, chain: Chain) async throws {
        progress.state = .syncing(wallet: walletAddress, chain: chain)
        progress.tokensDiscovered = 0
        progress.itemsClassified = 0
        progress.itemsPlayable = 0

        let existingActiveIDs = try await tokenStore.activeIDs(walletAddress: walletAddress, chain: chain)
        let discoveredTokens = try await fetchTokens(walletAddress: walletAddress, chain: chain)
        progress.tokensDiscovered = discoveredTokens.count

        let tokensWithMetadata = await fillMissingMetadata(in: discoveredTokens)
        let mediaItems = classify(tokensWithMetadata)
        progress.itemsClassified = mediaItems.count
        progress.itemsPlayable = mediaItems.filter(\.isPlayable).count

        let syncedAt = clock()

        try await tokenStore.upsertAll(tokensWithMetadata)
        try await mediaStore.upsertAll(mediaItems)

        let discoveredIDs = Set(tokensWithMetadata.map(\.compositeID))
        let inactiveIDs = existingActiveIDs.subtracting(discoveredIDs)
        try await tokenStore.markInactive(ids: inactiveIDs)

        // Reconcile out media rows for tokens that left the wallet, capturing a
        // Smart Resume tombstone for any resumable position, then restore
        // positions for tokens whose exact on-chain identity has returned. Media
        // `sourceNFTID` == token `compositeID`, so `inactiveIDs` map directly to
        // media rows. Restore runs after `upsertAll` re-inserted returned rows.
        try await mediaStore.removeItems(ids: Array(inactiveIDs), capturedAt: syncedAt)
        try await mediaStore.restorePlaybackTombstones(at: syncedAt)

        let mediaIDs = mediaItems.map(\.id)
        await mediaItemIndexer.indexItems(mediaIDs)
        await mediaItemIndexer.deleteItems(Array(inactiveIDs))
        Task {
            await embeddingQueueProcessor.processQueue(limit: 50)
        }
        Task {
            await artworkPrefetcher.prefetch(artworkURLs: mediaItems.compactMap(\.artworkURL))
        }

        progress.lastSyncedAt = syncedAt
        progress.state = .complete
    }

    public func syncAll() async throws {
        let scopes = try await scopeProvider.activeScopes()
        var errors: [SyncError] = []

        for scope in scopes {
            do {
                try await sync(walletAddress: scope.walletAddress, chain: scope.chain)
            } catch {
                errors.append(
                    SyncError(
                        walletAddress: scope.walletAddress,
                        chain: scope.chain,
                        message: error.localizedDescription
                    )
                )
            }
        }

        if errors.isEmpty {
            progress.lastSyncedAt = clock()
            progress.state = .complete
        } else {
            progress.state = .error(errors)
        }
    }

    public func syncAllIfNeeded() async throws {
        if let lastSyncedAt = defaults.object(forKey: Self.lastSyncAtKey) as? Date,
           clock().timeIntervalSince(lastSyncedAt) < syncCooldown {
            return
        }

        try await syncAll()
        defaults.set(clock(), forKey: Self.lastSyncAtKey)
    }
}

extension NFTSyncCoordinator: AuraPlayNFTDiscoverySyncing, AuraPlaySyncProgressProviding {
    public var syncProgress: SyncProgress { progress }
}

public extension NFTSyncCoordinator {
    static let lastSyncAtKey = "com.auraplay.lastSyncAt"
}

private extension NFTSyncCoordinator {
    func fetchTokens(walletAddress: String, chain: Chain) async throws -> [NFTTokenDTO] {
        if chain == .solanaMainnet || chain == .solanaDevnetTestnet {
            return try await solanaClient.fetchAll(owner: walletAddress)
        }
        return try await evmClient.fetchAll(owner: walletAddress, chain: chain)
    }

    func fillMissingMetadata(in tokens: [NFTTokenDTO]) async -> [NFTTokenDTO] {
        var tokensByIndex = Dictionary(uniqueKeysWithValues: tokens.enumerated().map { ($0.offset, $0.element) })
        let missingMetadata = tokens.enumerated().filter { _, token in
            token.metadataRaw == nil && token.metadataURL?.isEmpty == false
        }

        for batch in missingMetadata.chunked(into: 10) {
            await withTaskGroup(of: (Int, String?).self) { group in
                for (index, token) in batch {
                    group.addTask { [metadataFetcher] in
                        guard let metadataURL = token.metadataURL else {
                            return (index, nil)
                        }
                        do {
                            return (index, try await metadataFetcher.fetch(metadataURL: metadataURL))
                        } catch {
                            return (index, nil)
                        }
                    }
                }

                for await (index, metadataRaw) in group {
                    guard let metadataRaw, let token = tokensByIndex[index] else {
                        continue
                    }
                    tokensByIndex[index] = token.copy(metadataRaw: metadataRaw)
                }
            }
        }

        return tokens.indices.compactMap { tokensByIndex[$0] }
    }

    func classify(_ tokens: [NFTTokenDTO]) -> [MediaItemDTO] {
        tokens.map { token in
            let parsed = token.metadataRaw
                .map { metadataParser.parse(json: $0) }
                ?? MetadataParsed(
                    name: token.name,
                    description: token.description,
                    collectionName: token.collectionName,
                    artworkURL: token.imageURL,
                    schemaVersion: .unknown,
                    rawJSON: "{}"
                )
            return mediaClassifier.classify(parsed: parsed, token: token)
        }
    }
}

public struct SyncProgress: Equatable, Sendable {
    public var state: SyncState
    public var tokensDiscovered: Int
    public var itemsClassified: Int
    public var itemsPlayable: Int
    public var lastSyncedAt: Date?

    public init(
        state: SyncState = .idle,
        tokensDiscovered: Int = 0,
        itemsClassified: Int = 0,
        itemsPlayable: Int = 0,
        lastSyncedAt: Date? = nil
    ) {
        self.state = state
        self.tokensDiscovered = tokensDiscovered
        self.itemsClassified = itemsClassified
        self.itemsPlayable = itemsPlayable
        self.lastSyncedAt = lastSyncedAt
    }
}

public enum SyncState: Equatable, Sendable {
    case idle
    case syncing(wallet: String, chain: Chain)
    case error([SyncError])
    case complete
}

public struct SyncError: Equatable, Sendable {
    public let walletAddress: String
    public let chain: Chain
    public let message: String

    public init(walletAddress: String, chain: Chain, message: String) {
        self.walletAddress = walletAddress
        self.chain = chain
        self.message = message
    }
}

public struct NoOpArtworkPrefetcher: ArtworkPrefetching {
    public init() {}
    public func prefetch(artworkURLs: [String]) async {}
}

private extension NFTTokenDTO {
    func copy(metadataRaw: String?) -> NFTTokenDTO {
        NFTTokenDTO(
            compositeID: compositeID,
            chain: chain,
            walletAddress: walletAddress,
            contractAddress: contractAddress,
            tokenId: tokenId,
            tokenStandard: tokenStandard,
            collectionName: collectionName,
            name: name,
            description: description,
            imageURL: imageURL,
            metadataURL: metadataURL,
            metadataRaw: metadataRaw,
            providerUpdatedAt: providerUpdatedAt,
            isActive: isActive,
            provider: provider
        )
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
