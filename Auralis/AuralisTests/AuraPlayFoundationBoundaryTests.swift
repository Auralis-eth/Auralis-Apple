@testable import Auralis
import AuralisPrimaryModels
import AuralisPrimaryPersistence
import Foundation
import MusicFeature
import SwiftData
import Testing

@MainActor
struct AuraPlayFoundationBoundaryTests {
    @Test("AuraPlay persistence contract exposes the current schema")
    func persistenceContractUsesCurrentSchema() {
        let modelNames = Set(AuraPlaySchema.models.map { String(describing: $0) })

        #expect(modelNames == [
            "AuraPlayNFTToken",
            "AuraPlayMediaItem",
            "AuraPlayMediaEmbedding",
            "AuraPlayPlaybackPositionState",
            "AuraPlayPlaybackPositionTombstone",
            "AuraPlayPlaylist",
            "AuraPlayPlaylistItem"
        ])
    }

    @Test("dependencies preserve injected feature collaborators")
    func dependenciesPreserveInjectedCollaborators() {
        let dependencies = AuraPlayDependencies(
            libraryRepository: MockAuraPlayLibraryRepository(),
            librarySyncService: NoOpAuraPlayLibrarySyncService(),
            playlistManager: MockAuraPlayPlaylistManager(),
            playbackController: MockAuraPlayPlaybackController(),
            queueCoordinator: MockAuraPlayQueueCoordinator(),
            artworkLoader: MockAuraPlayArtworkLoader(),
            logger: MockAuraPlayLogger(),
            configuration: .validFixture,
            urlResolver: URLResolver()
        )

        #expect(dependencies.configuration.missingRequirements.isEmpty)
        #expect(dependencies.urlResolver.resolve("ipfs://QmFixture")?.host == "cloudflare-ipfs.com")
    }

    @Test("root model refreshes the library summary for the active wallet scope")
    func rootModelRefreshesSummaryForActiveScope() async {
        let repository = MockAuraPlayLibraryRepository(itemCount: 12)
        let librarySyncService = NoOpAuraPlayLibrarySyncService()
        let playbackController = MockAuraPlayPlaybackController()
        let queueCoordinator = MockAuraPlayQueueCoordinator()
        let artworkLoader = MockAuraPlayArtworkLoader()
        let logger = MockAuraPlayLogger()
        let account = EOAccount(
            address: "0x1234567890abcdef1234567890abcdef12345678",
            access: .readonly
        )
        let model = AuraPlayRootModel(
            libraryRepository: repository,
            librarySyncService: librarySyncService,
            nftDiscoverySyncService: NoOpAuraPlayNFTDiscoverySyncService(),
            playlistManager: MockAuraPlayPlaylistManager(),
            playbackController: playbackController,
            queueCoordinator: queueCoordinator,
            artworkLoader: artworkLoader,
            logger: logger,
            configuration: .validFixture,
            urlResolver: URLResolver(),
            currentAccount: account,
            currentChain: .ethMainnet
        )

        await model.refreshLibrarySummary()

        #expect(model.libraryItemCount == 12)
        #expect(
            repository.requestedScopes == [
                AuraPlayLibraryScope(
                    accountAddress: account.address,
                    chain: .ethMainnet
                )
            ]
        )
        #expect(model.upcomingQueueCount == 2)
        #expect(model.playbackHistoryCount == 1)
        #expect(model.configurationStatus == "Bundle contract ready")
        #expect(logger.events.contains { $0.category == .library && $0.level == .info })
    }

    @Test("root model updates wallet scope when the shell selection changes")
    func rootModelUpdatesWalletScope() async throws {
        let repository = MockAuraPlayLibraryRepository(itemCount: 3)
        let librarySyncService = NoOpAuraPlayLibrarySyncService()
        let playbackController = MockAuraPlayPlaybackController()
        let queueCoordinator = MockAuraPlayQueueCoordinator()
        let artworkLoader = MockAuraPlayArtworkLoader()
        let logger = MockAuraPlayLogger()
        let initialAccount = EOAccount(
            address: "0x1234567890abcdef1234567890abcdef12345678",
            access: .readonly
        )
        let nextAccount = EOAccount(
            address: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
            access: .readonly
        )
        let model = AuraPlayRootModel(
            libraryRepository: repository,
            librarySyncService: librarySyncService,
            nftDiscoverySyncService: NoOpAuraPlayNFTDiscoverySyncService(),
            playlistManager: MockAuraPlayPlaylistManager(),
            playbackController: playbackController,
            queueCoordinator: queueCoordinator,
            artworkLoader: artworkLoader,
            logger: logger,
            configuration: .validFixture,
            urlResolver: URLResolver(),
            currentAccount: initialAccount,
            currentChain: .ethMainnet
        )

        model.updateContext(currentAccount: nextAccount, currentChain: .baseMainnet)
        await model.refreshLibrarySummary()

        #expect(try #require(model.currentAccount).address == nextAccount.address)
        #expect(model.currentChain == .baseMainnet)
        #expect(
            repository.requestedScopes.last == AuraPlayLibraryScope(
                accountAddress: nextAccount.address,
                chain: .baseMainnet
            )
        )
    }

    @Test("root model maps repository failures into AuraPlay domain errors and logs them")
    func rootModelMapsRepositoryFailures() async throws {
        let repository = MockAuraPlayLibraryRepository(error: FixtureError.libraryFailure)
        let librarySyncService = NoOpAuraPlayLibrarySyncService()
        let playbackController = MockAuraPlayPlaybackController()
        let queueCoordinator = MockAuraPlayQueueCoordinator()
        let artworkLoader = MockAuraPlayArtworkLoader()
        let logger = MockAuraPlayLogger()
        let model = AuraPlayRootModel(
            libraryRepository: repository,
            librarySyncService: librarySyncService,
            nftDiscoverySyncService: NoOpAuraPlayNFTDiscoverySyncService(),
            playlistManager: MockAuraPlayPlaylistManager(),
            playbackController: playbackController,
            queueCoordinator: queueCoordinator,
            artworkLoader: artworkLoader,
            logger: logger,
            configuration: .validFixture,
            urlResolver: URLResolver(),
            currentAccount: nil,
            currentChain: .ethMainnet
        )

        await model.refreshLibrarySummary()

        #expect(model.libraryItemCount == nil)
        let lastError = try #require(model.lastError)
        #expect({
            guard case .library(let message) = lastError else {
                return false
            }
            return message == "AuraPlay could not refresh the music library yet. Please try again."
        }())
        #expect(logger.events.contains { $0.category == .library && $0.level == .error })
    }

    @Test("root model runs semantic search in the active wallet scope")
    func rootModelRunsSemanticSearchInActiveScope() async throws {
        let repository = MockAuraPlayLibraryRepository()
        let semanticSearch = MockAuraPlaySemanticSearchService(results: [
            AuraPlaySemanticSearchResult(
                id: "media-1",
                title: "Late Night Synth",
                artistName: "Aura",
                collectionName: "Nocturne",
                artworkURLString: nil,
                playbackURLString: "https://example.com/media-1.mp3",
                isPlayable: true,
                score: 0.91
            )
        ])
        let account = EOAccount(
            address: "0x1234567890abcdef1234567890abcdef12345678",
            access: .readonly
        )
        let model = AuraPlayRootModel(
            libraryRepository: repository,
            librarySyncService: NoOpAuraPlayLibrarySyncService(),
            nftDiscoverySyncService: NoOpAuraPlayNFTDiscoverySyncService(),
            semanticSearchService: semanticSearch,
            playlistManager: MockAuraPlayPlaylistManager(),
            playbackController: MockAuraPlayPlaybackController(),
            queueCoordinator: MockAuraPlayQueueCoordinator(),
            artworkLoader: MockAuraPlayArtworkLoader(),
            logger: MockAuraPlayLogger(),
            configuration: .validFixture,
            urlResolver: URLResolver(),
            currentAccount: account,
            currentChain: .ethMainnet
        )

        model.semanticSearchText = "late synth"
        await model.runSemanticSearch()

        #expect(model.semanticSearchResults.map(\.id) == ["media-1"])
        #expect(model.semanticSearchStatus == "1 semantic match found.")
        #expect(
            semanticSearch.requests == [
                MockAuraPlaySemanticSearchService.Request(
                    query: "late synth",
                    scope: AuraPlayLibraryScope(accountAddress: account.address, chain: .ethMainnet),
                    limit: 8,
                    minimumScore: 0.18
                )
            ]
        )

        model.clearSemanticSearch()

        #expect(model.semanticSearchText.isEmpty)
        #expect(model.semanticSearchResults.isEmpty)
    }

    @Test("root model gates More Like This by the scoped stored embedding set")
    func rootModelGatesRecommendationsByStoredEmbeddingSet() async throws {
        let account = EOAccount(
            address: "0x1234567890abcdef1234567890abcdef12345678",
            access: .readonly
        )
        let recommendationProvider = MockAuraPlayRecommendationProvider(
            embeddedIDs: ["media-with-embedding"]
        )
        let model = AuraPlayRootModel(
            libraryRepository: MockAuraPlayLibraryRepository(),
            librarySyncService: NoOpAuraPlayLibrarySyncService(),
            nftDiscoverySyncService: NoOpAuraPlayNFTDiscoverySyncService(),
            embeddingAvailabilityProvider: AlwaysAvailableAuraPlayEmbeddingAvailabilityProvider(),
            recommendationProvider: recommendationProvider,
            playlistManager: MockAuraPlayPlaylistManager(),
            playbackController: MockAuraPlayPlaybackController(),
            queueCoordinator: MockAuraPlayQueueCoordinator(),
            artworkLoader: MockAuraPlayArtworkLoader(),
            logger: MockAuraPlayLogger(),
            configuration: .validFixture,
            urlResolver: URLResolver(),
            currentAccount: account,
            currentChain: .ethMainnet
        )

        await model.refreshEmbeddingAvailability()

        let expectedScope = AuraPlayLibraryScope(accountAddress: account.address, chain: .ethMainnet)
        #expect(model.shouldShowPlaylistPlayground)
        #expect(model.canRecommend(mediaItemID: "media-with-embedding"))
        #expect(!model.canRecommend(mediaItemID: "media-without-embedding"))
        #expect(recommendationProvider.embeddedIDScopes == [expectedScope])

        model.updateContext(currentAccount: account, currentChain: .baseMainnet)

        #expect(!model.canRecommend(mediaItemID: "media-with-embedding"))
    }

    @Test("root model hides More Like This when embedding availability is unavailable")
    func rootModelHidesRecommendationsWhenEmbeddingsAreUnavailable() async throws {
        let account = EOAccount(
            address: "0x1234567890abcdef1234567890abcdef12345678",
            access: .readonly
        )
        let recommendationProvider = MockAuraPlayRecommendationProvider(
            embeddedIDs: ["media-with-embedding"]
        )
        let model = AuraPlayRootModel(
            libraryRepository: MockAuraPlayLibraryRepository(),
            librarySyncService: NoOpAuraPlayLibrarySyncService(),
            nftDiscoverySyncService: NoOpAuraPlayNFTDiscoverySyncService(),
            embeddingAvailabilityProvider: UnavailableAuraPlayEmbeddingAvailabilityProvider(),
            recommendationProvider: recommendationProvider,
            playlistManager: MockAuraPlayPlaylistManager(),
            playbackController: MockAuraPlayPlaybackController(),
            queueCoordinator: MockAuraPlayQueueCoordinator(),
            artworkLoader: MockAuraPlayArtworkLoader(),
            logger: MockAuraPlayLogger(),
            configuration: .validFixture,
            urlResolver: URLResolver(),
            currentAccount: account,
            currentChain: .ethMainnet
        )

        await model.refreshEmbeddingAvailability()

        #expect(!model.shouldShowPlaylistPlayground)
        #expect(!model.canRecommend(mediaItemID: "media-with-embedding"))
        #expect(recommendationProvider.embeddedIDScopes.isEmpty)
    }

    @Test("Phase 10 player adapter presents live NFT metadata and context actions")
    func phase10PlayerAdapterPresentsLiveMetadataAndContextActions() async throws {
        let presenter = MockAuraPlayPlaybackPresenter()
        let recorder = PlaybackAdapterActionRecorder()
        let adapter = AuraPlayPlaybackPlayerAdapter(
            presenter: presenter,
            contextActions: recorder.handler
        )

        let presentation = adapter.presentation

        #expect(presentation.item?.id == "token-1")
        #expect(presentation.item?.title == "Live Phase 10")
        #expect(presentation.item?.creator == "Auralis")
        #expect(presentation.item?.collection == "Ship Set")
        #expect(presentation.item?.mediaKind == .video)
        #expect(presentation.item?.chainDisplayName == "Ethereum")
        #expect(presentation.item?.contractAddress == "0xabc")
        #expect(presentation.item?.tokenID == "42")
        #expect(presentation.queue.upcoming.map(\.id) == ["queue-2", "queue-3"])
        #expect(presentation.queue.history.map(\.id) == ["queue-0"])

        await adapter.shareCurrentItem()
        await adapter.viewOnExplorer()
        await adapter.copyContractAddress()

        #expect(recorder.shareRequests.map(\.text) == ["Live Phase 10 - Auralis - Ship Set"])
        #expect(recorder.shareRequests.compactMap(\.url) == [try #require(URL(string: "https://auralis.example/share/token-1"))])
        #expect(recorder.openedURLs == [try #require(URL(string: "https://etherscan.io/nft/0xabc/42"))])
        #expect(recorder.copiedValues == ["0xabc"])
    }

    @Test("Phase 10 player adapter drives queue reorder and delete interactions")
    func phase10PlayerAdapterDrivesQueueMutations() async {
        let presenter = MockAuraPlayPlaybackPresenter()
        let recorder = PlaybackAdapterActionRecorder()
        let adapter = AuraPlayPlaybackPlayerAdapter(
            presenter: presenter,
            contextActions: recorder.handler
        )

        await adapter.reorderQueueEntry(id: "queue-3", toIndex: 0)
        await adapter.removeQueueEntry(id: "queue-2")

        #expect(presenter.moveRequests == [MockAuraPlayPlaybackPresenter.MoveRequest(id: "queue-3", index: 0)])
        #expect(presenter.removedQueueIDs == ["queue-2"])
    }

    @Test("Phase 10 player adapter drives mode and video controls")
    func phase10PlayerAdapterDrivesModeAndVideoControls() async {
        let presenter = MockAuraPlayPlaybackPresenter()
        let adapter = AuraPlayPlaybackPlayerAdapter(presenter: presenter)

        #expect(adapter.presentation.queue.isShuffleEnabled == false)
        #expect(adapter.presentation.queue.repeatModeTitle == "Off")
        #expect(adapter.presentation.videoCapabilities?.hasRoutePicker == true)

        await adapter.setShuffleEnabled(true)
        await adapter.cycleRepeatMode()
        await adapter.startPiP()
        await adapter.selectSubtitle("English")
        await adapter.setPlaybackSpeed(1.5)
        await adapter.toggleVideoGravity()

        #expect(presenter.shuffleRequests == [true])
        #expect(presenter.didCycleRepeatMode)
        #expect(presenter.videoCommands == ["startPiP", "subtitle:English", "speed:1.5", "toggleGravity"])
    }

    @Test("playback preference settings round-trip default shuffle and repeat modes")
    func playbackPreferenceSettingsRoundTripDefaultModes() throws {
        let suiteName = "AuraPlayPlaybackPreferenceSettings.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(AuraPlayShuffleMode.on.rawValue, forKey: AuraPlayPlaybackPreferenceSettings.shuffleModeDefaultsKey)
        defaults.set(AuraPlayRepeatMode.all.rawValue, forKey: AuraPlayPlaybackPreferenceSettings.repeatModeDefaultsKey)

        #expect(AuraPlayPlaybackPreferenceSettings.shuffleMode(from: defaults) == .on)
        #expect(AuraPlayPlaybackPreferenceSettings.repeatMode(from: defaults) == .all)
    }
}

@MainActor
private final class MockAuraPlayPlaybackController: AuraPlayPlaybackControlling {
    var playbackState: AuraPlayPlaybackState = .stopped
    var currentTrack: AuraPlayTrack? = AuraPlayTrack(
        id: "track-1",
        title: "Foundation",
        artist: "AuraPlay",
        duration: 120,
        imageURLString: "https://example.com/cover.png"
    )
    var currentTrackID: String?
    var currentTime: TimeInterval = 0

    func play() throws {}
    func pause() {}
    func resume() throws {}
    func seek(to time: TimeInterval) throws {}
    func playNext() async {}
    func playPrevious() async {}
}

@MainActor
private final class MockAuraPlayLibraryRepository: AuraPlayLibraryRepository {
    let itemCountValue: Int
    let error: Error?
    private(set) var requestedScopes: [AuraPlayLibraryScope] = []

    init(itemCount: Int = 0, error: Error? = nil) {
        self.itemCountValue = itemCount
        self.error = error
    }

    func itemCount(in scope: AuraPlayLibraryScope) throws -> Int {
        requestedScopes.append(scope)
        if let error {
            throw error
        }
        return itemCountValue
    }

    func needsRebuild(in scope: AuraPlayLibraryScope) async throws -> Bool {
        false
    }

    func rebuildLibrary(
        in scope: AuraPlayLibraryScope,
        correlationID: String?
    ) async throws -> AuraPlayLibraryRebuildResult {
        AuraPlayLibraryRebuildResult(
            scannedCount: 0,
            writtenCount: 0,
            removedCount: 0
        )
    }
}

@MainActor
private final class MockAuraPlayQueueCoordinator: AuraPlayQueueCoordinating {
    func snapshot() -> AuraPlayQueueSnapshot {
        AuraPlayQueueSnapshot(upcomingCount: 2, historyCount: 1)
    }
}

private final class MockAuraPlayArtworkLoader: AuraPlayArtworkLoading {
    func artworkURL(for track: AuraPlayTrack?) throws -> URL? {
        _ = try #require(track?.imageURLString)
        return URL(string: track?.imageURLString ?? "")
    }
}

private final class MockAuraPlaySemanticSearchService: AuraPlaySemanticSearching, @unchecked Sendable {
    struct Request: Equatable {
        let query: String
        let scope: AuraPlayLibraryScope
        let limit: Int
        let minimumScore: Float
    }

    private let resultValues: [AuraPlaySemanticSearchResult]
    private let lock = NSLock()
    private var requestValues: [Request] = []

    init(results: [AuraPlaySemanticSearchResult]) {
        self.resultValues = results
    }

    var requests: [Request] {
        lock.withLock { requestValues }
    }

    func search(
        query: String,
        in scope: AuraPlayLibraryScope,
        limit: Int,
        minimumScore: Float
    ) async throws -> [AuraPlaySemanticSearchResult] {
        lock.withLock {
            requestValues.append(
                Request(
                    query: query,
                    scope: scope,
                    limit: limit,
                    minimumScore: minimumScore
                )
            )
        }
        return resultValues
    }
}

private final class MockAuraPlayRecommendationProvider: AuraPlayRecommendationProviding, @unchecked Sendable {
    private let embeddedIDs: Set<String>
    private let lock = NSLock()
    private var embeddedIDScopeValues: [AuraPlayLibraryScope] = []

    init(embeddedIDs: Set<String>) {
        self.embeddedIDs = embeddedIDs
    }

    var embeddedIDScopes: [AuraPlayLibraryScope] {
        lock.withLock { embeddedIDScopeValues }
    }

    func moreLikeThis(
        mediaItemID: String,
        in scope: AuraPlayLibraryScope,
        limit: Int,
        minimumScore: Float
    ) async throws -> [AuraPlayRecommendationResult] {
        []
    }

    func hasEmbedding(mediaItemID: String) async throws -> Bool {
        embeddedIDs.contains(mediaItemID)
    }

    func embeddedMediaItemIDs(in scope: AuraPlayLibraryScope) async throws -> Set<String> {
        lock.withLock {
            embeddedIDScopeValues.append(scope)
        }
        return embeddedIDs
    }
}

private final class MockAuraPlayPlaylistManager: AuraPlayPlaylistManaging, @unchecked Sendable {
    private(set) var createdNames: [String] = []
    private(set) var renamedIDs: [String] = []
    private(set) var deletedIDs: [String] = []

    func fetchPlaylistSnapshots() async throws -> [AuraPlayPlaylistSnapshot] {
        []
    }

    func fetchPlaylistSnapshot(id: String) async throws -> AuraPlayPlaylistSnapshot? {
        nil
    }

    func createID(name: String, at date: Date) async throws -> String {
        createdNames.append(name)
        return "playlist-\(createdNames.count)"
    }

    func createSmartPlaylistID(
        name: String,
        mediaItemIDs: [String],
        smartQueryData: Data,
        at date: Date
    ) async throws -> String {
        try await createID(name: name, at: date)
    }

    func rename(id: String, name: String, at date: Date) async throws {
        renamedIDs.append(id)
    }

    func delete(id: String) async throws {
        deletedIDs.append(id)
    }

    func add(mediaItemID: String, toPlaylist playlistID: String, at date: Date) async throws {}
    func remove(mediaItemID: String, fromPlaylist playlistID: String, at date: Date) async throws {}
    func reorderItem(playlistID: String, fromPosition: Int, toPosition: Int, at date: Date) async throws {}
    func toggle(mediaItemID: String, playlistID: String, at date: Date) async throws {}

    func createAndAddID(name: String, mediaItemID: String, at date: Date) async throws -> String {
        try await createID(name: name, at: date)
    }
}

@MainActor
private final class PlaybackAdapterActionRecorder {
    private(set) var shareRequests: [AuraPlayShareRequest] = []
    private(set) var openedURLs: [URL] = []
    private(set) var copiedValues: [String] = []

    var handler: AuraPlayPlayerContextActionHandler {
        AuraPlayPlayerContextActionHandler(
            share: { [weak self] request in
                self?.shareRequests.append(request)
            },
            open: { [weak self] url in
                self?.openedURLs.append(url)
            },
            copy: { [weak self] value in
                self?.copiedValues.append(value)
            }
        )
    }
}

@MainActor
private final class MockAuraPlayPlaybackPresenter: AuraPlayPlaybackPresenting, AuraPlayPlaybackItemPresenting, AuraPlayPlaybackModePresenting, AuraPlayPlayerVideoPresenting {
    struct MoveRequest: Equatable {
        let id: String
        let index: Int
    }

    var auraPlayCurrentTrack: AuraPlayTrack? = AuraPlayTrack(
        id: "token-1",
        title: "Legacy Track",
        artist: "Legacy Artist",
        duration: 240,
        imageURLString: "https://auralis.example/artwork.png"
    )
    var auraPlayPlaybackState: AuraPlayPlaybackState = .playing
    var auraPlayProgress: TimeInterval = 40
    var auraPlayNextPreviewTrack: AuraPlayTrack?
    var auraPlayPreviousPreviewTrack: AuraPlayTrack?
    var auraPlayCachePresentation = AuraPlayCachePresentation(
        state: .cached,
        progressFraction: 1,
        message: "Cached",
        canSaveOffline: false,
        canPin: true,
        canUnpin: false
    )
    var auraPlaySystemIntegrationPresentation = AuraPlaySystemIntegrationPresentation(
        routeMode: "Device",
        nowPlayingStatus: "Ready",
        remoteCommandStatus: "Ready",
        spatialAudioStatus: "Unavailable"
    )
    var auraPlayVisualizationPresentation = AuraPlayVisualizationPresentation()
    var auraPlayAudioTuningPresentation = AuraPlayAudioTuningPresentation()
    var auraPlayPlaybackAlert: AuraPlayPlaybackAlertPresentation?
    var auraPlayCurrentItemPresentation: AuraPlayCurrentItemPresentation? = AuraPlayCurrentItemPresentation(
        id: "token-1",
        title: "Live Phase 10",
        creator: "Auralis",
        collection: "Ship Set",
        artworkURLString: "https://auralis.example/artwork.png",
        mediaKind: .video,
        chainDisplayName: "Ethereum",
        contractAddress: "0xabc",
        tokenID: "42",
        shareURL: URL(string: "https://auralis.example/share/token-1"),
        explorerURL: URL(string: "https://etherscan.io/nft/0xabc/42")
    )
    private(set) var moveRequests: [MoveRequest] = []
    private(set) var removedQueueIDs: [String] = []
    private(set) var shuffleRequests: [Bool] = []
    private(set) var didCycleRepeatMode = false
    private(set) var videoCommands: [String] = []
    var auraPlayShuffleEnabled = false
    var auraPlayRepeatModeTitle = "Off"
    var auraPlayVideoCapabilities: AuraPlayPlayerVideoCapabilities? = AuraPlayPlayerVideoCapabilities(
        isPiPAvailable: true,
        hasRoutePicker: true,
        subtitleOptions: ["English"],
        audioDescriptionOptions: ["English Audio Description"],
        speedOptions: [1, 1.5],
        selectedSpeed: 1,
        canChangeAspect: true
    )

    func auraPlayPlay() throws {}
    func auraPlayPause() {}
    func auraPlayResume() throws {}
    func auraPlaySeek(to time: TimeInterval) throws {}
    func auraPlaySkipForward() {}
    func auraPlaySkipBackward() {}
    func auraPlayNext() async {}
    func auraPlayPrevious() async {}
    func auraPlayQueueItems() -> [AuraPlayQueuePresentationItem] {
        [
            AuraPlayQueuePresentationItem(
                id: "queue-0",
                title: "History",
                artist: "Auralis",
                imageURLString: nil,
                role: .history
            ),
            AuraPlayQueuePresentationItem(
                id: "queue-2",
                title: "Upcoming One",
                artist: "Auralis",
                imageURLString: nil,
                role: .upcoming
            ),
            AuraPlayQueuePresentationItem(
                id: "queue-3",
                title: "Upcoming Two",
                artist: "Auralis",
                imageURLString: nil,
                role: .upcoming
            )
        ]
    }

    func auraPlayRemoveQueueItem(id: String) {
        removedQueueIDs.append(id)
    }

    func auraPlayMoveQueueItem(id: String, toUpcomingIndex: Int) {
        moveRequests.append(MoveRequest(id: id, index: toUpcomingIndex))
    }

    func auraPlayClearUpcomingQueue() {}
    func auraPlaySaveOffline() async {}
    func auraPlayPinOffline() async {}
    func auraPlayUnpinOffline() async {}
    func auraPlaySetEQPreset(_ preset: AuraPlayEQPresetID) {}
    func auraPlaySetCustomEQBand(index: Int, gain: Float) {}
    func auraPlaySetNormalizationEnabled(_ isEnabled: Bool) {}
    func auraPlaySetCrossfadeDuration(_ duration: Double) {}
    func auraPlayDismissPlaybackAlert() {}
    func auraPlayStartVisualization() async {}
    func auraPlayStopVisualization() async {}
    func auraPlaySetShuffleEnabled(_ isEnabled: Bool) {
        auraPlayShuffleEnabled = isEnabled
        shuffleRequests.append(isEnabled)
    }

    func auraPlayCycleRepeatMode() {
        didCycleRepeatMode = true
        auraPlayRepeatModeTitle = "All"
    }

    func auraPlayStartPiP() {
        videoCommands.append("startPiP")
    }

    func auraPlayStopPiP() {
        videoCommands.append("stopPiP")
    }

    func auraPlayRestorePiP() {
        videoCommands.append("restorePiP")
    }

    func auraPlaySelectSubtitle(_ title: String?) async {
        videoCommands.append("subtitle:\(title ?? "off")")
    }

    func auraPlaySetPlaybackSpeed(_ speed: Double) async {
        videoCommands.append("speed:\(speed)")
    }

    func auraPlayToggleVideoGravity() async {
        videoCommands.append("toggleGravity")
    }
}

// `AuraPlayLogging` is synchronous, so this recorder cannot be an actor.
// Tests drive it serially through the synchronous logging protocol.
private final class MockAuraPlayLogger: AuraPlayLogging, Sendable {
    nonisolated(unsafe) private(set) var events: [AuraPlayLogEvent] = []

    func log(_ event: AuraPlayLogEvent) {
        events.append(event)
    }
}

private enum FixtureError: Error {
    case libraryFailure
}

private extension AuraPlayModuleConfiguration {
    static let validFixture = AuraPlayModuleConfiguration(
        backgroundAudioEnabled: true,
        declaredURLSchemes: ["auralis", "auraplay"],
        walletQuerySchemes: ["metamask", "cbwallet", "rainbow", "ledgerlive"]
    )
}
