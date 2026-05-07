@testable import Auralis
import AuralisPrimaryModels
import Foundation
import SwiftData
import Testing

@Suite
@MainActor
struct AuraPlayFoundationBoundaryTests {
    @Test("AuraPlay persistence contract exposes the current schema")
    func persistenceContractUsesCurrentSchema() {
        let modelNames = Set(AuraPlaySchema.models.map { String(describing: $0) })

        #expect(modelNames == ["AuraPlayMediaItem"])
    }

    @Test("dependencies preserve the injected AuraPlay model container identity")
    func dependenciesPreserveInjectedModelContainer() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let dependencies = AuraPlayDependencies(
            libraryRepository: MockAuraPlayLibraryRepository(),
            librarySyncService: NoOpAuraPlayLibrarySyncService(),
            playbackController: MockAuraPlayPlaybackController(),
            queueCoordinator: MockAuraPlayQueueCoordinator(),
            artworkLoader: MockAuraPlayArtworkLoader(),
            logger: MockAuraPlayLogger(),
            configuration: .validFixture,
            modelContainer: container
        )

        #expect(ObjectIdentifier(dependencies.modelContainer) == ObjectIdentifier(container))
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
            playbackController: playbackController,
            queueCoordinator: queueCoordinator,
            artworkLoader: artworkLoader,
            logger: logger,
            configuration: .validFixture,
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
    func rootModelUpdatesWalletScope() async {
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
            playbackController: playbackController,
            queueCoordinator: queueCoordinator,
            artworkLoader: artworkLoader,
            logger: logger,
            configuration: .validFixture,
            currentAccount: initialAccount,
            currentChain: .ethMainnet
        )

        model.updateContext(currentAccount: nextAccount, currentChain: .baseMainnet)
        await model.refreshLibrarySummary()

        #expect(model.currentAccount?.address == nextAccount.address)
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
            playbackController: playbackController,
            queueCoordinator: queueCoordinator,
            artworkLoader: artworkLoader,
            logger: logger,
            configuration: .validFixture,
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
            return message.contains("AuraPlay could not load the music library summary yet:")
                && message.contains("FixtureError")
        }())
        #expect(logger.events.contains { $0.category == .library && $0.level == .error })
    }
}

@MainActor
private final class MockAuraPlayPlaybackController: AuraPlayPlaybackControlling {
    var playbackState: AudioEngine.PlaybackState = .stopped
    var currentTrack: AudioEngine.Track? = AudioEngine.Track(
        id: "track-1",
        title: "Foundation",
        artist: "AuraPlay",
        duration: 120,
        imageUrl: "https://example.com/cover.png"
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
    ) async throws -> MusicLibraryIndexRebuildResult {
        MusicLibraryIndexRebuildResult(
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

@MainActor
private final class MockAuraPlayArtworkLoader: AuraPlayArtworkLoading {
    func artworkURL(for track: AudioEngine.Track?) throws -> URL? {
        _ = try #require(track?.imageUrl)
        return URL(string: track?.imageUrl ?? "")
    }
}

@MainActor
private final class MockAuraPlayLogger: AuraPlayLogging {
    private(set) var events: [AuraPlayLogEvent] = []

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
