@testable import Auralis
import Foundation
import SwiftData
import Testing

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
            "persistence.completed"
        ])
        #expect(
            service.lastSuccessfulRefreshAt(
                for: "0x1234567890abcdef1234567890abcdef12345678",
                chain: .ethMainnet
            ) != nil
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
        let second = Task { @MainActor in
            await service.refreshNFTs(
                for: account,
                chain: .ethMainnet,
                modelContext: context,
                correlationID: "same-scope-2"
            )
        }

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

        while fetchUseCase.startedScopes.isEmpty {
            await Task.yield()
        }

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

    func recordFetchFailed(accountAddress: String, chain: Chain, correlationID: String, error: Error) async { }

    func recordPersistenceCompleted(accountAddress: String, chain: Chain, correlationID: String, persistedCount: Int) async {
        trace.events.append("persistence.completed")
    }

    func recordPersistenceFailed(accountAddress: String, chain: Chain, correlationID: String, error: Error) async {
        trace.events.append("persistence.failed")
    }
}

@MainActor
private final class ServiceFetcherStub: NFTFetching {
    var total: Int?
    var itemsLoaded: Int?
    var loading = false
    var error: Error?
    var currentCursor: String?

    func fetchAllNFTs(
        for account: String,
        chain: Chain,
        correlationID: String?,
        eventRecorder: any NFTRefreshEventRecording
    ) async throws -> [NFT] {
        []
    }

    func reset() {
        total = nil
        itemsLoaded = nil
        loading = false
        currentCursor = nil
        error = nil
    }
}

@MainActor
private struct ServiceFetchUseCase: FetchNFTInventoryUsing {
    let trace: ServiceTrace

    func fetchInventory(
        for accountAddress: String,
        chain: Chain,
        correlationID: String,
        eventRecorder: any NFTRefreshEventRecording
    ) async throws -> FetchedNFTInventory {
        trace.events.append("fetch")
        return FetchedNFTInventory(
            nfts: [makeRefreshFixtureNFT(accountAddress: accountAddress)],
            didCompleteFullRefresh: false
        )
    }
}

@MainActor
private struct ServicePrepareUseCase: PrepareNFTMetadataUsing {
    let trace: ServiceTrace

    func prepareInventory(
        _ fetchedNFTs: [NFT],
        accountAddress: String,
        chain: Chain
    ) async -> PreparedNFTInventory {
        trace.events.append("prepare")
        return PreparedNFTInventory(nfts: fetchedNFTs)
    }
}

@MainActor
private struct ServicePersistUseCase: PersistNFTInventoryUsing {
    let trace: ServiceTrace

    func persist(
        _ inventory: PreparedNFTInventory,
        accountAddress: String,
        chain: Chain,
        modelContext: ModelContext
    ) async throws {
        trace.events.append("persist")
    }

    func cleanupStaleInventory(
        currentNFTIDs: [String],
        accountAddress: String,
        chain: Chain,
        modelContext: ModelContext
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
        modelContext: ModelContext
    ) async throws {
        trace.events.append("persist.failed")
        throw error
    }

    func cleanupStaleInventory(
        currentNFTIDs: [String],
        accountAddress: String,
        chain: Chain,
        modelContext: ModelContext
    ) async throws { }
}

@MainActor
private final class SlowSameScopeFetchUseCase: FetchNFTInventoryUsing {
    private(set) var callCount = 0

    func fetchInventory(
        for accountAddress: String,
        chain: Chain,
        correlationID: String,
        eventRecorder: any NFTRefreshEventRecording
    ) async throws -> FetchedNFTInventory {
        callCount += 1
        try await Task.sleep(for: .milliseconds(50))
        return FetchedNFTInventory(nfts: [], didCompleteFullRefresh: false)
    }
}

@MainActor
private final class CancellableScopeFetchUseCase: FetchNFTInventoryUsing {
    private(set) var startedScopes: [String] = []
    private(set) var cancellationCount = 0

    func fetchInventory(
        for accountAddress: String,
        chain: Chain,
        correlationID: String,
        eventRecorder: any NFTRefreshEventRecording
    ) async throws -> FetchedNFTInventory {
        startedScopes.append(accountAddress)
        do {
            if startedScopes.count == 1 {
                try await Task.sleep(for: .seconds(5))
            }
        } catch is CancellationError {
            cancellationCount += 1
            throw CancellationError()
        }

        return FetchedNFTInventory(nfts: [], didCompleteFullRefresh: false)
    }
}
