import ContextCore
import Foundation
import Testing

@MainActor
struct ContextRefreshCoordinatorTests {
    @Test("Same-scope refreshes share one in-flight operation")
    func sameScopeRefreshesCoalesce() async {
        let coordinator = ContextRefreshCoordinator()
        let gate = ContextRefreshGate()
        let scope = ContextRequestScope(
            accountAddress: "0x1234",
            chainID: "base-mainnet",
            modeID: "observe"
        )
        let operationCounter = ContextOperationCounter()

        async let first = coordinator.resolve(scope: scope) {
            await operationCounter.increment()
            await gate.wait()
            return makeSnapshot(accountAddress: "0x1234")
        }
        await gate.waitUntilSuspended()
        async let second = coordinator.resolve(scope: scope) {
            await operationCounter.increment()
            return makeSnapshot(accountAddress: "unexpected")
        }

        await gate.release()
        let (firstResolution, secondResolution) = await (first, second)

        #expect(await operationCounter.count == 1)
        #expect(firstResolution.snapshot == secondResolution.snapshot)
        #expect(secondResolution.reusedInFlightRefresh)
    }

    @Test("Only the newest scope is allowed to commit")
    func newestScopeWins() async {
        let coordinator = ContextRefreshCoordinator()
        let gate = ContextRefreshGate()
        let firstScope = ContextRequestScope(
            accountAddress: "0xaaaa",
            chainID: "eth-mainnet",
            modeID: "observe"
        )
        let secondScope = ContextRequestScope(
            accountAddress: "0xbbbb",
            chainID: "base-mainnet",
            modeID: "observe"
        )

        async let first = coordinator.resolve(scope: firstScope) {
            await gate.wait()
            return makeSnapshot(accountAddress: firstScope.accountAddress)
        }
        await gate.waitUntilSuspended()
        let second = await coordinator.resolve(scope: secondScope) {
            makeSnapshot(accountAddress: secondScope.accountAddress)
        }
        await gate.release()
        let firstResolution = await first

        #expect(second.shouldCommit)
        #expect(firstResolution.shouldCommit == false)
        #expect(second.snapshot.scope.accountAddress.value == secondScope.accountAddress)
    }

    private func makeSnapshot(accountAddress: String) -> ContextSnapshot {
        ContextSnapshotBuilder().build(
            from: ContextSnapshotInput(
                mode: "observe",
                accountAddress: accountAddress,
                accountName: nil,
                accountAddedAt: nil,
                accountMostRecentActivityAt: nil,
                selectedChains: [],
                isRefreshing: false,
                refreshedAt: nil,
                nativeBalanceDisplay: nil,
                nativeBalanceStatusMessage: nil,
                nativeBalanceUpdatedAt: nil,
                nativeBalanceProvenance: .localCache,
                freshnessTTL: nil,
                trackedNFTCount: nil,
                musicCollectionCount: nil,
                receiptCount: nil,
                modulePointers: [],
                prefersDemoData: nil,
                pinnedItemCount: nil,
                referenceDate: Date(timeIntervalSince1970: 1_700_000_000)
            )
        )
    }
}

private actor ContextOperationCounter {
    private(set) var count = 0

    func increment() {
        count += 1
    }
}

private actor ContextRefreshGate {
    private var isSuspended = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        isSuspended = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilSuspended() async {
        while !isSuspended {
            await Task.yield()
        }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}
