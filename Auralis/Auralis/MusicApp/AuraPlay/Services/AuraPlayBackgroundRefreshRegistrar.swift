import AuralisPrimaryPersistence
import Foundation
import MusicFeature
import OSLog
import SwiftData

#if canImport(BackgroundTasks)
import BackgroundTasks
#endif

@MainActor
protocol AuraPlayBackgroundRefreshTask: AnyObject {
    var expirationHandler: (() -> Void)? { get set }
    func setTaskCompleted(success: Bool)
}

@MainActor
protocol AuraPlayBackgroundTaskScheduling {
    func register(
        forTaskWithIdentifier identifier: String,
        launchHandler: @escaping (any AuraPlayBackgroundRefreshTask) -> Void
    ) -> Bool
    func submitAppRefreshTask(identifier: String, earliestBeginDate: Date?) throws
}

@MainActor
final class AuraPlayBackgroundRefreshRegistrar {
    static let taskIdentifier = "com.auraplay.nft-sync"

    private let scheduler: any AuraPlayBackgroundTaskScheduling
    private let syncServiceFactory: @MainActor () throws -> any AuraPlayNFTDiscoverySyncing
    private let earliestBeginDate: () -> Date
    private let logger: Logger
    private var isRegistered = false

    init(
        scheduler: any AuraPlayBackgroundTaskScheduling,
        syncServiceFactory: @escaping @MainActor () throws -> any AuraPlayNFTDiscoverySyncing,
        earliestBeginDate: @escaping () -> Date = { Date().addingTimeInterval(15 * 60) },
        logger: Logger = Logger(subsystem: "Auralis", category: "music.background-refresh")
    ) {
        self.scheduler = scheduler
        self.syncServiceFactory = syncServiceFactory
        self.earliestBeginDate = earliestBeginDate
        self.logger = logger
    }

    func registerIfNeeded() {
        guard !isRegistered else { return }

        isRegistered = scheduler.register(forTaskWithIdentifier: Self.taskIdentifier) { [weak self] task in
            Task { @MainActor [weak self] in
                self?.handle(task)
            }
        }
        if !isRegistered {
            logger.error("AuraPlay background refresh registration failed.")
        }
    }

    func scheduleNextRefresh() {
        do {
            try scheduler.submitAppRefreshTask(
                identifier: Self.taskIdentifier,
                earliestBeginDate: earliestBeginDate()
            )
        } catch {
            logger.error("AuraPlay background refresh scheduling failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func handle(_ task: any AuraPlayBackgroundRefreshTask) {
        scheduleNextRefresh()

        let syncTask = Task { @MainActor [syncServiceFactory, logger] in
            do {
                let syncService = try syncServiceFactory()
                try await syncService.syncAllIfNeeded()
                task.setTaskCompleted(success: true)
            } catch is CancellationError {
                task.setTaskCompleted(success: false)
            } catch {
                logger.error("AuraPlay background refresh failed: \(error.localizedDescription, privacy: .public)")
                task.setTaskCompleted(success: false)
            }
        }

        task.expirationHandler = {
            syncTask.cancel()
        }
    }
}

@MainActor
enum AuraPlayBackgroundRefreshRuntimeFactory {
    static func makeSyncService() throws -> any AuraPlayNFTDiscoverySyncing {
        let auraPlayModelContainer = try AuraPlayModelContainer.make(inMemory: false)
        let primaryModelContainer = try ModelContainer(for: PrimaryStoreSchema.schema)
        let accountModelContext = ModelContext(primaryModelContainer)
        return try MusicAssembly(
            providerAssembly: ProviderAssembly(),
            receiptAssembly: ReceiptAssembly()
        )
        .makeNFTSyncCoordinator(
            auraPlayModelContainer: auraPlayModelContainer,
            accountModelContext: accountModelContext
        )
    }
}

#if canImport(BackgroundTasks)
extension BGAppRefreshTask: AuraPlayBackgroundRefreshTask {}

struct SystemAuraPlayBackgroundTaskScheduler: AuraPlayBackgroundTaskScheduling {
    func register(
        forTaskWithIdentifier identifier: String,
        launchHandler: @escaping (any AuraPlayBackgroundRefreshTask) -> Void
    ) -> Bool {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            launchHandler(refreshTask)
        }
    }

    func submitAppRefreshTask(identifier: String, earliestBeginDate: Date?) throws {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = earliestBeginDate
        try BGTaskScheduler.shared.submit(request)
    }
}

extension AuraPlayBackgroundRefreshRegistrar {
    static func live() -> AuraPlayBackgroundRefreshRegistrar {
        AuraPlayBackgroundRefreshRegistrar(
            scheduler: SystemAuraPlayBackgroundTaskScheduler(),
            syncServiceFactory: AuraPlayBackgroundRefreshRuntimeFactory.makeSyncService
        )
    }
}
#endif
