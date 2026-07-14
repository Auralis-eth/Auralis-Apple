import Foundation
import MusicFeature
import NFTDomain
import NFTPersistence
import NFTPresentation
import NFTProviderAdapters
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

    func makeMusicFeatureDependencies(
        playbackRuntime: AuraPlayPlaybackRuntime,
        auraPlayModelContainer: ModelContainer,
        accountModelContext: ModelContext,
        musicLibraryIndexer: any MusicLibraryIndexing
    ) -> AuraPlayDependencies {
        let logger = LiveAuraPlayLogger()
        configureMediaResolver(playbackRuntime)
        playbackRuntime.configureAuraPlayModelContainer(auraPlayModelContainer)
        return AuraPlayDependencies(
            libraryRepository: LiveAuraPlayLibraryRepository(
                indexer: musicLibraryIndexer,
                receiptEventLogger: receiptAssembly.makeReceiptEventLogger(modelContext: accountModelContext),
                auraPlayModelContainer: auraPlayModelContainer,
                accountModelContext: accountModelContext
            ),
            librarySyncService: LiveAuraPlayLibrarySyncService(
                sourceModelContext: accountModelContext,
                auraPlayModelContainer: auraPlayModelContainer,
                musicReceiptLogger: MusicReceiptEventLogger(
                    receiptStore: receiptAssembly.makeReceiptStore(modelContext: accountModelContext)
                ),
                logger: logger
            ),
            playbackController: playbackRuntime,
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
