@testable import Auralis
import AuralisPrimaryModels
import Foundation
import MusicFeature
import Testing

@MainActor
struct AuraPlayBackgroundRefreshRegistrarTests {
    @Test("background refresh registers and schedules the AuraPlay task identifier")
    func registersAndSchedulesRefreshTask() {
        let scheduler = FakeBackgroundTaskScheduler()
        let registrar = AuraPlayBackgroundRefreshRegistrar(
            scheduler: scheduler,
            syncServiceFactory: { FakeNFTDiscoverySyncService() },
            earliestBeginDate: { Date(timeIntervalSince1970: 1_800_000_900) }
        )

        registrar.registerIfNeeded()
        registrar.registerIfNeeded()
        registrar.scheduleNextRefresh()

        #expect(scheduler.registeredIdentifiers == [AuraPlayBackgroundRefreshRegistrar.taskIdentifier])
        #expect(scheduler.submittedRequests == [
            FakeBackgroundTaskScheduler.Request(
                identifier: AuraPlayBackgroundRefreshRegistrar.taskIdentifier,
                earliestBeginDate: Date(timeIntervalSince1970: 1_800_000_900)
            )
        ])
    }

    @Test("background refresh completes successfully after sync")
    func completesSuccessfulRefreshAfterSync() async throws {
        let scheduler = FakeBackgroundTaskScheduler()
        let syncService = FakeNFTDiscoverySyncService()
        let registrar = AuraPlayBackgroundRefreshRegistrar(
            scheduler: scheduler,
            syncServiceFactory: { syncService }
        )
        registrar.registerIfNeeded()
        let task = FakeBackgroundRefreshTask()

        scheduler.launch(task)

        #expect(await waitForCondition { task.completedSuccess == true })
        #expect(syncService.syncAllIfNeededCallCount == 1)
    }

    @Test("background refresh reports failure when sync throws")
    func completesFailedRefreshWhenSyncThrows() async throws {
        let scheduler = FakeBackgroundTaskScheduler()
        let syncService = FakeNFTDiscoverySyncService(error: FixtureError.syncFailed)
        let registrar = AuraPlayBackgroundRefreshRegistrar(
            scheduler: scheduler,
            syncServiceFactory: { syncService }
        )
        registrar.registerIfNeeded()
        let task = FakeBackgroundRefreshTask()

        scheduler.launch(task)

        #expect(await waitForCondition { task.completedSuccess == false })
        #expect(syncService.syncAllIfNeededCallCount == 1)
    }
}

private func waitForCondition(
    maxAttempts: Int = 50,
    condition: @escaping @MainActor () -> Bool
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
private final class FakeBackgroundTaskScheduler: AuraPlayBackgroundTaskScheduling {
    struct Request: Equatable {
        let identifier: String
        let earliestBeginDate: Date?
    }

    private var launchHandler: (((any AuraPlayBackgroundRefreshTask)) -> Void)?
    private(set) var registeredIdentifiers: [String] = []
    private(set) var submittedRequests: [Request] = []

    func register(
        forTaskWithIdentifier identifier: String,
        launchHandler: @escaping (any AuraPlayBackgroundRefreshTask) -> Void
    ) -> Bool {
        registeredIdentifiers.append(identifier)
        self.launchHandler = launchHandler
        return true
    }

    func submitAppRefreshTask(identifier: String, earliestBeginDate: Date?) throws {
        submittedRequests.append(Request(identifier: identifier, earliestBeginDate: earliestBeginDate))
    }

    func launch(_ task: FakeBackgroundRefreshTask) {
        launchHandler?(task)
    }
}

@MainActor
private final class FakeBackgroundRefreshTask: AuraPlayBackgroundRefreshTask {
    var expirationHandler: (() -> Void)?
    private(set) var completedSuccess: Bool?

    func setTaskCompleted(success: Bool) {
        completedSuccess = success
    }
}

@MainActor
private final class FakeNFTDiscoverySyncService: AuraPlayNFTDiscoverySyncing {
    private let error: Error?
    private(set) var syncCallCount = 0
    private(set) var syncAllCallCount = 0
    private(set) var syncAllIfNeededCallCount = 0

    init(error: Error? = nil) {
        self.error = error
    }

    func sync(walletAddress: String, chain: Chain) async throws {
        syncCallCount += 1
        if let error { throw error }
    }

    func syncAll() async throws {
        syncAllCallCount += 1
        if let error { throw error }
    }

    func syncAllIfNeeded() async throws {
        syncAllIfNeededCallCount += 1
        if let error { throw error }
    }
}

private enum FixtureError: Error {
    case syncFailed
}
