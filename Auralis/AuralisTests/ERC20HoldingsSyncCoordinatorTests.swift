@testable import Auralis
import Foundation
import Testing

@Suite
struct ERC20HoldingsSyncCoordinatorTests {
    @Test("a newer ERC-20 sync drops stale results from the previous wallet scope")
    @MainActor
    func newerSyncSupersedesOlderScope() async throws {
        let coordinator = ERC20HoldingsSyncCoordinator()
        let firstFetchStarted = AsyncSignal()
        let releaseFirstFetch = AsyncSignal()
        let persistedScopes = PersistedScopeRecorder()

        let firstTask = Task {
            await coordinator.sync(
                request: .init(
                    accountAddress: "0x1111111111111111111111111111111111111111",
                    chain: .baseMainnet
                ),
                fetch: { _ in
                    await firstFetchStarted.signal()
                    await releaseFirstFetch.wait()
                    return [
                        ProviderTokenHolding(
                            contractAddress: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
                            symbol: "USDC",
                            displayName: "USD Coin",
                            amountDisplay: "10 USDC",
                            updatedAt: .now,
                            isPlaceholder: false,
                            isAmountHidden: false
                        )
                    ]
                },
                persist: { request, _ in
                    persistedScopes.record(request.accountAddress)
                }
            )
        }

        await firstFetchStarted.wait()

        let secondResult = await coordinator.sync(
            request: .init(
                accountAddress: "0x2222222222222222222222222222222222222222",
                chain: .baseMainnet
            ),
            fetch: { _ in
                [
                    ProviderTokenHolding(
                        contractAddress: "0x6b175474e89094c44da98b954eedeac495271d0f",
                        symbol: "DAI",
                        displayName: "Dai",
                        amountDisplay: "2 DAI",
                        updatedAt: .now,
                        isPlaceholder: false,
                        isAmountHidden: false
                    )
                ]
            },
            persist: { request, _ in
                persistedScopes.record(request.accountAddress)
            }
        )

        await releaseFirstFetch.signal()
        let firstResult = await firstTask.value

        #expect(secondResult == .applied)
        #expect(firstResult == .dropped)
        #expect(persistedScopes.values() == [
            "0x2222222222222222222222222222222222222222"
        ])
    }
}

private actor AsyncSignal {
    private var hasSignaled = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if hasSignaled {
            return
        }

        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func signal() {
        hasSignaled = true
        let pending = continuations
        continuations.removeAll()
        for continuation in pending {
            continuation.resume()
        }
    }
}

@MainActor
private final class PersistedScopeRecorder {
    private var recordedValues: [String] = []

    func record(_ accountAddress: String) {
        recordedValues.append(accountAddress)
    }

    func values() -> [String] {
        recordedValues
    }
}
