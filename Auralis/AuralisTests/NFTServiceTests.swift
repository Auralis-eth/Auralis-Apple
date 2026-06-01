@testable import Auralis
import AuralisPrimaryModels
import AuralisPrimaryPersistence
import Foundation
import SwiftData
import Testing
import NFTDomain
import NFTPersistence
import NFTPresentation
import NFTProviderAdapters

@Suite
struct NFTServiceTests {
    @Test("service sequences fetch, prepare, persist, and event recording in order")
    @MainActor
    func sequencesCollaboratorsInOrder() async throws {
        let container = try makeNFTRefreshContainer()
        let context = ModelContext(container)
        let trace = ServiceTrace()
        let fetcher = ServiceFetcherStub()
        let recorder = ServiceEventRecorder(trace: trace)
        let service = NFTService(
            nftFetcher: fetcher,
            fetchInventoryUseCase: ServiceFetchUseCase(trace: trace),
            prepareMetadataUseCase: ServicePrepareUseCase(trace: trace),
            persistInventoryUseCase: ServicePersistUseCase(trace: trace),
            eventRecorderFactory: { _ in recorder }
        )

        await service.fetchAllNFTs(
            for: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .ethMainnet,
            modelContext: context,
            correlationID: "service-sequence"
        )

        #expect(trace.events == [
            "refresh.started",
            "fetch",
            "prepare",
            "persist",
            "cleanup",
            "persistence.completed"
        ])
        #expect(
            service.lastSuccessfulRefreshAt(
                for: "0x1234567890abcdef1234567890abcdef12345678",
                chain: .ethMainnet
            ) != nil
        )
    }

    @Test("partial refresh persists without cleanup or freshness update")
    @MainActor
    func partialRefreshDoesNotCleanupOrMarkFresh() async throws {
        let container = try makeNFTRefreshContainer()
        let context = ModelContext(container)
        let trace = ServiceTrace()
        let fetcher = ServiceFetcherStub()
        let recorder = ServiceEventRecorder(trace: trace)
        let service = NFTService(
            nftFetcher: fetcher,
            fetchInventoryUseCase: ServiceFetchUseCase(
                trace: trace,
                didCompleteFullRefresh: false
            ),
            prepareMetadataUseCase: ServicePrepareUseCase(trace: trace),
            persistInventoryUseCase: ServicePersistUseCase(trace: trace),
            eventRecorderFactory: { _ in recorder }
        )

        await service.fetchAllNFTs(
            for: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .ethMainnet,
            modelContext: context,
            correlationID: "service-partial"
        )

        #expect(trace.events == [
            "refresh.started",
            "fetch",
            "prepare",
            "persist",
            "persistence.completed"
        ])
        #expect(
            service.lastSuccessfulRefreshAt(
                for: "0x1234567890abcdef1234567890abcdef12345678",
                chain: .ethMainnet
            ) == nil
        )
    }

    @Test("same-scope refreshes reuse in-flight work")
    @MainActor
    func reusesInFlightWorkForSameScope() async throws {
        let container = try makeNFTRefreshContainer()
        let context = ModelContext(container)
        let fetcher = ServiceFetcherStub()
        let fetchUseCase = SlowSameScopeFetchUseCase()
        let service = NFTService(
            nftFetcher: fetcher,
            fetchInventoryUseCase: fetchUseCase,
            eventRecorderFactory: { _ in NoOpNFTRefreshEventRecorder() }
        )
        let account = EOAccount(address: "0x1234567890abcdef1234567890abcdef12345678")

        let first = Task { @MainActor in
            await service.refreshNFTs(
                for: account,
                chain: .ethMainnet,
                modelContext: context,
                correlationID: "same-scope-1"
            )
        }
        await fetchUseCase.waitUntilFetchStarts()
        let second = Task { @MainActor in
            await service.refreshNFTs(
                for: account,
                chain: .ethMainnet,
                modelContext: context,
                correlationID: "same-scope-2"
            )
        }
        fetchUseCase.resume()

        _ = await (first.value, second.value)

        #expect(fetchUseCase.callCount == 1)
    }

    @Test("changing scope cancels prior in-flight refreshes")
    @MainActor
    func cancelsPriorRefreshWhenScopeChanges() async throws {
        let container = try makeNFTRefreshContainer()
        let context = ModelContext(container)
        let fetcher = ServiceFetcherStub()
        let fetchUseCase = CancellableScopeFetchUseCase()
        let service = NFTService(
            nftFetcher: fetcher,
            fetchInventoryUseCase: fetchUseCase,
            eventRecorderFactory: { _ in NoOpNFTRefreshEventRecorder() }
        )

        let firstAccount = EOAccount(address: "0x1234567890abcdef1234567890abcdef12345678")
        let secondAccount = EOAccount(address: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd")

        let first = Task { @MainActor in
            await service.refreshNFTs(
                for: firstAccount,
                chain: .ethMainnet,
                modelContext: context,
                correlationID: "cancel-1"
            )
        }

        await fetchUseCase.waitUntilFetchStarts()

        await service.refreshNFTs(
            for: secondAccount,
            chain: .ethMainnet,
            modelContext: context,
            correlationID: "cancel-2"
        )
        await first.value

        #expect(fetchUseCase.startedScopes == [firstAccount.address, secondAccount.address])
        #expect(fetchUseCase.cancellationCount == 1)
    }

    @Test("scope changes do not persist inventory prepared by a cancelled refresh")
    @MainActor
    func cancelledRefreshDoesNotPersistPreparedInventory() async throws {
        let container = try makeNFTRefreshContainer()
        let context = ModelContext(container)
        let fetcher = ServiceFetcherStub()
        let prepareUseCase = CancellablePrepareUseCase()
        let persistUseCase = RecordingPersistUseCase()
        let service = NFTService(
            nftFetcher: fetcher,
            fetchInventoryUseCase: ScopeSnapshotFetchUseCase(),
            prepareMetadataUseCase: prepareUseCase,
            persistInventoryUseCase: persistUseCase,
            eventRecorderFactory: { _ in NoOpNFTRefreshEventRecorder() }
        )

        let firstAccount = EOAccount(address: "0x1234567890abcdef1234567890abcdef12345678")
        let secondAccount = EOAccount(address: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd")

        let first = Task { @MainActor in
            await service.refreshNFTs(
                for: firstAccount,
                chain: .ethMainnet,
                modelContext: context,
                correlationID: "cancel-during-prepare-1"
            )
        }

        await prepareUseCase.waitUntilPrepareStarts()

        await service.refreshNFTs(
            for: secondAccount,
            chain: .ethMainnet,
            modelContext: context,
            correlationID: "cancel-during-prepare-2"
        )
        await first.value

        #expect(prepareUseCase.startedScopes == [firstAccount.address, secondAccount.address])
        #expect(prepareUseCase.cancellationCount == 1)
        #expect(persistUseCase.persistedScopes == [secondAccount.address])
    }

    @Test("records persistence failure events and preserves the terminal error")
    @MainActor
    func recordsPersistenceFailurePath() async throws {
        let container = try makeNFTRefreshContainer()
        let context = ModelContext(container)
        let trace = ServiceTrace()
        let fetcher = ServiceFetcherStub()
        let recorder = ServiceEventRecorder(trace: trace)
        let expectedError = TestPersistenceError.failed
        let service = NFTService(
            nftFetcher: fetcher,
            fetchInventoryUseCase: ServiceFetchUseCase(trace: trace),
            prepareMetadataUseCase: ServicePrepareUseCase(trace: trace),
            persistInventoryUseCase: FailingPersistUseCase(trace: trace, error: expectedError),
            eventRecorderFactory: { _ in recorder }
        )

        await service.fetchAllNFTs(
            for: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .ethMainnet,
            modelContext: context,
            correlationID: "service-failure"
        )

        #expect(trace.events == [
            "refresh.started",
            "fetch",
            "prepare",
            "persist.failed",
            "persistence.failed"
        ])
        #expect(service.error as? TestPersistenceError == .failed)
    }
}

private enum TestPersistenceError: Error, Equatable {
    case failed
}

@MainActor
private final class ServiceTrace {
    var events: [String] = []
}

@MainActor
private final class ServiceEventRecorder: NFTRefreshEventRecording {
    private let trace: ServiceTrace

    init(trace: ServiceTrace) {
        self.trace = trace
    }

    func recordRefreshStarted(accountAddress: String, chain: Chain, correlationID: String) async {
        trace.events.append("refresh.started")
    }

    func recordFetchSucceeded(accountAddress: String, chain: Chain, correlationID: String, itemCount: Int, totalCount: Int?) async { }

    func recordFetchFailed(accountAddress: String, chain: Chain, correlationID: String, failure: NFTProviderFailure) async { }

    func recordPersistenceCompleted(accountAddress: String, chain: Chain, correlationID: String, persistedCount: Int) async {
        trace.events.append("persistence.completed")
    }

    func recordPersistenceFailed(accountAddress: String, chain: Chain, correlationID: String, error: Error) async {
        trace.events.append("persistence.failed")
    }
}

@MainActor
private final class ServiceFetcherStub: NFTFetching {
    func fetchAllNFTs(
        for account: String,
        chain: Chain,
        correlationID: String?,
        eventRecorder: any NFTRefreshEventRecording,
        progressHandler: NFTFetchProgressHandler?
    ) async throws -> NFTFetchInventoryResult {
        NFTFetchInventoryResult(nfts: [], didCompleteFullRefresh: true, totalCount: 0)
    }
}

@MainActor
private struct ServiceFetchUseCase: FetchNFTInventoryUsing {
    let trace: ServiceTrace
    let didCompleteFullRefresh: Bool

    init(trace: ServiceTrace, didCompleteFullRefresh: Bool = true) {
        self.trace = trace
        self.didCompleteFullRefresh = didCompleteFullRefresh
    }

    func fetchInventory(
        for accountAddress: String,
        chain: Chain,
        correlationID: String,
        eventRecorder: any NFTRefreshEventRecording,
        progressHandler: NFTFetchProgressHandler?
    ) async throws -> FetchedNFTInventory {
        trace.events.append("fetch")
        return FetchedNFTInventory(
            nfts: [makeRefreshFixtureSnapshot(accountAddress: accountAddress)],
            didCompleteFullRefresh: didCompleteFullRefresh
        )
    }
}

@MainActor
private struct ScopeSnapshotFetchUseCase: FetchNFTInventoryUsing {
    func fetchInventory(
        for accountAddress: String,
        chain: Chain,
        correlationID: String,
        eventRecorder: any NFTRefreshEventRecording,
        progressHandler: NFTFetchProgressHandler?
    ) async throws -> FetchedNFTInventory {
        FetchedNFTInventory(
            nfts: [makeRefreshFixtureSnapshot(accountAddress: accountAddress)],
            didCompleteFullRefresh: false
        )
    }
}

@MainActor
private struct ServicePrepareUseCase: PrepareNFTMetadataUsing {
    let trace: ServiceTrace

    func prepareInventory(
        _ fetchedNFTs: [NFTInventoryItemSnapshot],
        accountAddress: String,
        chain: Chain
    ) async -> PreparedNFTInventory {
        trace.events.append("prepare")
        return PreparedNFTInventory(nfts: fetchedNFTs)
    }
}

@MainActor
private final class CancellablePrepareUseCase: PrepareNFTMetadataUsing {
    private(set) var startedScopes: [String] = []
    private(set) var cancellationCount = 0
    private var prepareStartedContinuation: CheckedContinuation<Void, Never>?
    private var resumeContinuation: CheckedContinuation<Void, Never>?

    func prepareInventory(
        _ fetchedNFTs: [NFTInventoryItemSnapshot],
        accountAddress: String,
        chain: Chain
    ) async -> PreparedNFTInventory {
        startedScopes.append(accountAddress)
        prepareStartedContinuation?.resume()
        prepareStartedContinuation = nil

        if startedScopes.count == 1 {
            await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    resumeContinuation = continuation
                }
            } onCancel: {
                Task { @MainActor in
                    self.cancellationCount += 1
                    self.resume()
                }
            }
        }

        return PreparedNFTInventory(nfts: fetchedNFTs)
    }

    func waitUntilPrepareStarts() async {
        if startedScopes.isEmpty == false {
            return
        }

        await withCheckedContinuation { continuation in
            prepareStartedContinuation = continuation
        }
    }

    func resume() {
        resumeContinuation?.resume()
        resumeContinuation = nil
    }
}

@MainActor
private struct ServicePersistUseCase: PersistNFTInventoryUsing {
    let trace: ServiceTrace

    func persist(
        _ inventory: PreparedNFTInventory,
        accountAddress: String,
        chain: Chain,
        modelContainer: ModelContainer
    ) async throws {
        trace.events.append("persist")
    }

    func cleanupStaleInventory(
        currentNFTIDs: [String],
        accountAddress: String,
        chain: Chain,
        modelContainer: ModelContainer
    ) async throws {
        trace.events.append("cleanup")
    }
}

@MainActor
private final class RecordingPersistUseCase: PersistNFTInventoryUsing {
    private(set) var persistedScopes: [String] = []

    func persist(
        _ inventory: PreparedNFTInventory,
        accountAddress: String,
        chain: Chain,
        modelContainer: ModelContainer
    ) async throws {
        persistedScopes.append(accountAddress)
    }

    func cleanupStaleInventory(
        currentNFTIDs: [String],
        accountAddress: String,
        chain: Chain,
        modelContainer: ModelContainer
    ) async throws { }
}

@MainActor
private struct FailingPersistUseCase: PersistNFTInventoryUsing {
    let trace: ServiceTrace
    let error: TestPersistenceError

    func persist(
        _ inventory: PreparedNFTInventory,
        accountAddress: String,
        chain: Chain,
        modelContainer: ModelContainer
    ) async throws {
        trace.events.append("persist.failed")
        throw error
    }

    func cleanupStaleInventory(
        currentNFTIDs: [String],
        accountAddress: String,
        chain: Chain,
        modelContainer: ModelContainer
    ) async throws { }
}

@MainActor
private final class SlowSameScopeFetchUseCase: FetchNFTInventoryUsing {
    private(set) var callCount = 0
    private var fetchStartedContinuation: CheckedContinuation<Void, Never>?
    private var resumeContinuation: CheckedContinuation<Void, Never>?

    func fetchInventory(
        for accountAddress: String,
        chain: Chain,
        correlationID: String,
        eventRecorder: any NFTRefreshEventRecording,
        progressHandler: NFTFetchProgressHandler?
    ) async throws -> FetchedNFTInventory {
        callCount += 1
        fetchStartedContinuation?.resume()
        fetchStartedContinuation = nil
        await withCheckedContinuation { continuation in
            resumeContinuation = continuation
        }
        return FetchedNFTInventory(nfts: [], didCompleteFullRefresh: false)
    }

    func waitUntilFetchStarts() async {
        if callCount > 0 {
            return
        }

        await withCheckedContinuation { continuation in
            fetchStartedContinuation = continuation
        }
    }

    func resume() {
        resumeContinuation?.resume()
        resumeContinuation = nil
    }
}

@MainActor
private final class CancellableScopeFetchUseCase: FetchNFTInventoryUsing {
    private(set) var startedScopes: [String] = []
    private(set) var cancellationCount = 0
    private var fetchStartedContinuation: CheckedContinuation<Void, Never>?
    private var resumeContinuation: CheckedContinuation<Void, Never>?

    func fetchInventory(
        for accountAddress: String,
        chain: Chain,
        correlationID: String,
        eventRecorder: any NFTRefreshEventRecording,
        progressHandler: NFTFetchProgressHandler?
    ) async throws -> FetchedNFTInventory {
        startedScopes.append(accountAddress)
        fetchStartedContinuation?.resume()
        fetchStartedContinuation = nil

        if startedScopes.count == 1 {
            await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    resumeContinuation = continuation
                }
            } onCancel: {
                Task { @MainActor in
                    self.cancellationCount += 1
                    self.resume()
                }
            }

            if Task.isCancelled {
                throw CancellationError()
            }
        }

        return FetchedNFTInventory(nfts: [], didCompleteFullRefresh: false)
    }

    func waitUntilFetchStarts() async {
        if startedScopes.isEmpty == false {
            return
        }

        await withCheckedContinuation { continuation in
            fetchStartedContinuation = continuation
        }
    }

    func resume() {
        resumeContinuation?.resume()
        resumeContinuation = nil
    }
}
