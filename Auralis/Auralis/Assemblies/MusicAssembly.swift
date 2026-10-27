import AuralisPrimaryModels
import AuralisPrimaryPersistence
import Foundation
import MusicFeature
import NFTDomain
import NFTPersistence
import NFTPresentation
import NFTProviderAdapters
import ProviderKit
import AuralisReceipts
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

struct MusicPlaybackRuntimeResult {
    let playbackRuntime: AuraPlayPlaybackRuntime?
    let initializationErrorMessage: String?
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

    private var storageResolutionConfiguration: AuraPlayStorageResolutionConfiguration {
        (try? AuraPlayStorageResolutionConfiguration(
            infoDictionary: Bundle.main.infoDictionary ?? [:]
        )) ?? .liveDefault
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

        return MusicRuntime(
            playbackRuntime: nil,
            playbackRuntimeInitializationErrorMessage: nil,
            auraPlayModelContainer: auraPlayResult.0,
            auraPlayInitializationErrorMessage: auraPlayResult.1
        )
    }

    /// Constructs the audio graph only after the user opens Music. AVAudioEngine may
    /// synchronously contact the audio server while its output node is created, so it
    /// must not be part of the app-launch composition path.
    func makePlaybackRuntime() -> MusicPlaybackRuntimeResult {
        guard !ProcessInfo.isHostedUnitTest else {
            return MusicPlaybackRuntimeResult(
                playbackRuntime: nil,
                initializationErrorMessage: nil
            )
        }

        do {
            let playbackRuntime = try AuraPlayPlaybackRuntime()
            configureMediaResolver(playbackRuntime)
            return MusicPlaybackRuntimeResult(
                playbackRuntime: playbackRuntime,
                initializationErrorMessage: nil
            )
        } catch {
            return MusicPlaybackRuntimeResult(
                playbackRuntime: nil,
                initializationErrorMessage: error.localizedDescription
            )
        }
    }

    func configureReceiptLogger(playbackRuntime: AuraPlayPlaybackRuntime?, modelContext: ModelContext) {
        playbackRuntime?.configureMusicReceiptLogger(
            MusicReceiptEventLogger(
                receiptStore: receiptAssembly.makeReceiptStore(modelContext: modelContext)
            )
        )
    }

    func configureMediaResolver(_ playbackRuntime: AuraPlayPlaybackRuntime?) {
        let configuration = storageResolutionConfiguration
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
        let storageConfiguration = storageResolutionConfiguration
        let resolver = URLResolver(configuration: storageConfiguration)
        let gatewayFallbackChain = GatewayFallbackChain(
            resolver: resolver,
            configuration: storageConfiguration
        )

        return NFTSyncCoordinator(
            evmClient: Self.makeEVMDiscoveryClient(),
            solanaClient: Self.makeSolanaDiscoveryClient(),
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

    private static func makeEVMDiscoveryClient() -> any EVMNFTDiscovering {
        do {
            return AlchemyNFTClient(apiKey: try Secrets.apiKey(.alchemy))
        } catch {
            return UnavailableEVMNFTDiscoveryClient(error: error)
        }
    }

    private static func makeSolanaDiscoveryClient() -> any SolanaNFTDiscovering {
        do {
            return HeliusNFTClient(apiKey: try Secrets.apiKey(.helius))
        } catch {
            return UnavailableSolanaNFTDiscoveryClient(error: error)
        }
    }

    func makeMusicFeatureDependencies(
        playbackRuntime: AuraPlayPlaybackRuntime,
        auraPlayModelContainer: ModelContainer,
        accountModelContext: ModelContext,
        musicLibraryIndexer: any MusicLibraryIndexing,
        videoRouteOpening: AuraPlayVideoRouteOpening
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
        playbackRuntime.configureVideoRouteOpening(videoRouteOpening.open)
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
            playlistManager: ReceiptBackedAuraPlayPlaylistManager(
                base: AuraPlayPlaylistService(modelContainer: auraPlayModelContainer),
                receiptLogger: MusicReceiptEventLogger(
                    receiptStore: receiptAssembly.makeReceiptStore(modelContext: accountModelContext)
                ),
                context: MusicReceiptContext(
                    triggerCause: .userInitiated,
                    actor: .user,
                    surface: "music.library.playlist"
                )
            ),
            autoOrganizationRunner: MusicAutoOrganizationReceiptService(
                receiptLogger: MusicReceiptEventLogger(
                    receiptStore: receiptAssembly.makeReceiptStore(modelContext: accountModelContext)
                )
            ),
            playbackController: playbackRuntime,
            playbackPresenter: playbackRuntime,
            playbackOrchestrator: AuraPlayOrchestratorAdapter(
                runtime: playbackRuntime,
                resolveNFTs: nftResolver,
                openVideoPlayer: videoRouteOpening.open
            ),
            mediaQueryService: mediaQueryService,
            queueCoordinator: playbackRuntime,
            artworkLoader: AuraPlayTrackArtworkLoader(),
            logger: logger,
            configuration: AuraPlayModuleConfiguration.live(
                infoDictionary: Bundle.main.infoDictionary ?? [:]
            ),
            urlResolver: URLResolver(
                configuration: storageResolutionConfiguration
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

private struct UnavailableEVMNFTDiscoveryClient: EVMNFTDiscovering {
    let errorMessage: String

    init(error: Error) {
        self.errorMessage = error.localizedDescription
    }

    func fetchAll(owner: String, chain: Chain) async throws -> [NFTTokenDTO] {
        throw ProviderAbstractionError.providerError(errorMessage)
    }
}

private struct UnavailableSolanaNFTDiscoveryClient: SolanaNFTDiscovering {
    let errorMessage: String

    init(error: Error) {
        self.errorMessage = error.localizedDescription
    }

    func fetchAll(owner: String) async throws -> [NFTTokenDTO] {
        throw ProviderAbstractionError.providerError(errorMessage)
    }
}
