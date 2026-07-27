import AuralisPrimaryPersistence
import Foundation
import MusicFeature
import NFTDomain
import NFTPersistence
import NFTPresentation
import NFTProviderAdapters
import ProviderKit
import ReceiptsCore
import SwiftData

struct MusicRuntime {
    let playbackRuntime: AuraPlayPlaybackRuntime?
    let playbackRuntimeInitializationErrorMessage: String?
    let auraPlayModelContainer: ModelContainer?
    let auraPlayInitializationErrorMessage: String?

    var unavailableMessage: String? {
        [playbackRuntimeInitializationErrorMessage, auraPlayInitializationErrorMessage]
            .compactMap { $0 }
            .joined(separator: " ")
            .nilIfEmpty
    }
}

private extension ProcessInfo {
    static var isHostedUnitTest: Bool {
        processInfo.environment["XCTestConfigurationFilePath"] != nil
            || Bundle.allBundles.contains { $0.bundlePath.hasSuffix(".xctest") }
    }
}

@MainActor
struct MusicAssembly {
    private let providerAssembly: ProviderAssembly
    private let receiptAssembly: ReceiptAssembly

    init(
        providerAssembly: ProviderAssembly,
        receiptAssembly: ReceiptAssembly
    ) {
        self.providerAssembly = providerAssembly
        self.receiptAssembly = receiptAssembly
    }

    func makeNFTService() -> NFTService {
        let readOnlyProviderFactory = providerAssembly.readOnlyProviderFactory
        return NFTService(
            nftFetcher: NFTFetcher(
                nftProviderFactory: { chain in
                    try readOnlyProviderFactory.makeNFTInventoryProvider(for: chain)
                }
            ),
            eventRecorderFactory: { [receiptAssembly] modelContext in
                receiptAssembly.makeNFTRefreshEventRecorder(modelContext: modelContext)
            }
        )
    }

    func makeRuntime() -> MusicRuntime {
        let auraPlayResult: (ModelContainer?, String?)
        do {
            auraPlayResult = (try AuraPlayModelContainer.make(inMemory: ProcessInfo.isHostedUnitTest), nil)
        } catch {
            auraPlayResult = (nil, "AuraPlay storage could not be opened on this launch.")
        }

        let audioResult: (AuraPlayPlaybackRuntime?, String?)
        if ProcessInfo.isHostedUnitTest {
            audioResult = (nil, nil)
        } else {
            do {
                let playbackRuntime = try AuraPlayPlaybackRuntime()
                configureMediaResolver(playbackRuntime)
                audioResult = (playbackRuntime, nil)
            } catch {
                audioResult = (nil, error.localizedDescription)
            }
        }

        return MusicRuntime(
            playbackRuntime: audioResult.0,
            playbackRuntimeInitializationErrorMessage: audioResult.1,
            auraPlayModelContainer: auraPlayResult.0,
            auraPlayInitializationErrorMessage: auraPlayResult.1
        )
    }

    func configureReceiptLogger(playbackRuntime: AuraPlayPlaybackRuntime?, modelContext: ModelContext) {
        playbackRuntime?.configureMusicReceiptLogger(
            MusicReceiptEventLogger(
                receiptStore: receiptAssembly.makeReceiptStore(modelContext: modelContext)
            )
        )
    }

    func configureMediaResolver(_ playbackRuntime: AuraPlayPlaybackRuntime?) {
        let configuration = AuraPlayStorageResolutionConfiguration.liveDefault
        playbackRuntime?.configureMediaResolver(
            GatewayFallbackChain(
                resolver: URLResolver(configuration: configuration),
                configuration: configuration
            ),
            configuration: configuration
        )
    }

    func makeMusicLibraryIndexer(modelContext: ModelContext) -> any MusicLibraryIndexing {
        SwiftDataMusicLibraryIndexer(modelContext: modelContext)
    }

    func makeNFTSyncCoordinator(
        auraPlayModelContainer: ModelContainer,
        accountModelContext: ModelContext
    ) throws -> NFTSyncCoordinator {
        let storageConfiguration = AuraPlayStorageResolutionConfiguration.liveDefault
        let resolver = URLResolver(configuration: storageConfiguration)
        let gatewayFallbackChain = GatewayFallbackChain(
            resolver: resolver,
            configuration: storageConfiguration
        )

        return NFTSyncCoordinator(
            evmClient: AlchemyNFTClient(
                apiKey: try Secrets.apiKey(.alchemy)
            ),
            solanaClient: HeliusNFTClient(
                apiKey: try Secrets.apiKey(.helius)
            ),
            metadataFetcher: MetadataFetcher(
                gatewayFallbackChain: gatewayFallbackChain
            ),
            metadataParser: MetadataParser(),
            mediaClassifier: MediaClassifier(
                urlResolver: resolver
            ),
            tokenStore: AuraPlayNFTTokenService(
                modelContainer: auraPlayModelContainer
            ),
            mediaStore: AuraPlayMediaItemService(
                modelContainer: auraPlayModelContainer
            ),
            scopeProvider: SwiftDataNFTDiscoveryScopeProvider(
                modelContainer: accountModelContext.container
            ),
            artworkPrefetcher: MediaItemArtworkPrefetcher(
                gatewayFallbackChain: gatewayFallbackChain
            ),
            mediaItemIndexer: AuraPlaySpotlightIndexer(
                modelContainer: auraPlayModelContainer,
                indexClient: CoreSpotlightAuraPlayIndexClient(indexName: SearchSpotlightIndexConfiguration.indexName)
            ),
            embeddingQueueProcessor: AuraPlayEmbeddingService(
                modelContainer: auraPlayModelContainer
            )
        )
    }

    func makeMusicFeatureDependencies(
        playbackRuntime: AuraPlayPlaybackRuntime,
        auraPlayModelContainer: ModelContainer,
        accountModelContext: ModelContext,
        musicLibraryIndexer: any MusicLibraryIndexing
    ) -> AuraPlayDependencies {
        let logger = LiveAuraPlayLogger()
        let nftDiscoverySyncService: any AuraPlayNFTDiscoverySyncing
        let syncProgressProvider: any AuraPlaySyncProgressProviding
        do {
            let syncCoordinator = try makeNFTSyncCoordinator(
                auraPlayModelContainer: auraPlayModelContainer,
                accountModelContext: accountModelContext
            )
            nftDiscoverySyncService = syncCoordinator
            syncProgressProvider = syncCoordinator
        } catch {
            logger.log(
                AuraPlayLogEvent(
                    category: .sync,
                    level: .error,
                    message: "AuraPlay NFT discovery sync is unavailable: \(error.localizedDescription)"
                )
            )
            nftDiscoverySyncService = NoOpAuraPlayNFTDiscoverySyncService()
            syncProgressProvider = NoOpAuraPlaySyncProgressProvider()
        }
        configureMediaResolver(playbackRuntime)
        playbackRuntime.configureAuraPlayModelContainer(auraPlayModelContainer)
        let textEmbeddingProvider = NaturalLanguageTextEmbeddingProvider()
        let semanticSearchService = AuraPlayEmbeddingService(
            modelContainer: auraPlayModelContainer,
            embeddingProvider: textEmbeddingProvider
        )
        let mediaQueryService = AuraPlayMediaItemService(modelContainer: auraPlayModelContainer)
        let playlistGenerator = AuraPlayPlaylistGenerator(
            semanticSearch: semanticSearchService,
            mediaQueryService: mediaQueryService
        )
        let recommendationProvider = AuraPlayRecommendationService(
            modelContainer: auraPlayModelContainer
        )

        let nftResolver: @MainActor ([String]) -> [NFT] = { ids in
            let requested = Set(ids)
            guard !requested.isEmpty else { return [] }
            let allNFTs = (try? accountModelContext.fetch(FetchDescriptor<NFT>())) ?? []
            return allNFTs.filter { requested.contains($0.id) }
        }
        playbackRuntime.configureLibraryQueueExtension(
            extender: AuraPlayMediaQueueWindowProvider(queryService: mediaQueryService),
            resolveNFTs: nftResolver
        )

        return AuraPlayDependencies(
            libraryRepository: LiveAuraPlayLibraryRepository(
                indexer: musicLibraryIndexer,
                receiptEventLogger: receiptAssembly.makeReceiptEventLogger(modelContext: accountModelContext),
                auraPlayModelContainer: auraPlayModelContainer,
                accountModelContext: accountModelContext
            ),
            librarySyncService: LiveAuraPlayLibrarySyncService(
                sourceModelContext: accountModelContext,
                musicReceiptLogger: MusicReceiptEventLogger(
                    receiptStore: receiptAssembly.makeReceiptStore(modelContext: accountModelContext)
                ),
                logger: logger
            ),
            nftDiscoverySyncService: nftDiscoverySyncService,
            syncProgressProvider: syncProgressProvider,
            semanticSearchService: semanticSearchService,
            embeddingAvailabilityProvider: AuraPlayEmbeddingAvailabilityProvider(
                embeddingProvider: textEmbeddingProvider
            ),
            playlistGenerator: playlistGenerator,
            recommendationProvider: recommendationProvider,
            playlistManager: AuraPlayPlaylistService(modelContainer: auraPlayModelContainer),
            playbackController: playbackRuntime,
            playbackPresenter: playbackRuntime,
            playbackOrchestrator: AuraPlayOrchestratorAdapter(
                runtime: playbackRuntime,
                resolveNFTs: nftResolver
            ),
            mediaQueryService: mediaQueryService,
            queueCoordinator: playbackRuntime,
            artworkLoader: AuraPlayTrackArtworkLoader(),
            logger: logger,
            configuration: AuraPlayModuleConfiguration.live(
                infoDictionary: Bundle.main.infoDictionary ?? [:]
            ),
            urlResolver: URLResolver(
                configuration: .liveDefault
            )
        )
    }
}

@ModelActor
private actor SwiftDataNFTDiscoveryScopeProvider: NFTDiscoveryScopeProviding {
    func activeScopes() async throws -> [NFTDiscoveryScope] {
        let descriptor = FetchDescriptor<EOAccount>(
            sortBy: [SortDescriptor(\.lastSelectedAt, order: .reverse), SortDescriptor(\.addedAt, order: .reverse)]
        )

        return try modelContext.fetch(descriptor).map { account in
            NFTDiscoveryScope(
                walletAddress: account.address,
                chain: account.currentChain
            )
        }
    }
}
