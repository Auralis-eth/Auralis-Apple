@testable import Auralis
import AuralisPrimaryModels
import Foundation
import OperatorsFeature
import ProviderKit
import Testing

private struct OperatorActivityStub: OperatorDataSource {
    let activity: [ObservedActivity]

    func recentActivity(matching request: OperatorRequest, limit: Int) async -> [ObservedActivity] {
        Array(activity.prefix(limit))
    }
}

private struct NativeBalanceStub: NativeBalanceProviding {
    let result: Result<NativeBalance, Error>

    func nativeBalance(for address: String, chain: Chain) async throws -> NativeBalance {
        try result.get()
    }
}

private enum NativeBalanceStubError: Error {
    case unavailable
}

@Suite("Live on-chain operator data")
struct LiveOnChainOperatorDataSourceTests {
    @Test("A watch combines scoped receipt history with a live native balance snapshot")
    func combinesLocalAndLiveActivity() async {
        let oldDate = Date(timeIntervalSince1970: 100)
        let snapshotDate = Date(timeIntervalSince1970: 200)
        let target = WatchTarget(
            chain: "eth-mainnet",
            address: "0x0000000000000000000000000000000000000001"
        )
        let subject = LiveOnChainOperatorDataSource(
            localDataSource: OperatorActivityStub(activity: [
                ObservedActivity(
                    title: "Prior transfer",
                    detail: "Receipt-backed observation",
                    occurredAt: oldDate,
                    chain: target.chain,
                    address: target.address
                )
            ]),
            balanceProvider: NativeBalanceStub(result: .success(NativeBalance(weiHex: "0x2a", weiDecimal: "42"))),
            now: { snapshotDate }
        )

        let result = await subject.recentActivity(
            matching: OperatorRequest(watchlist: [target]),
            limit: 10
        )

        #expect(result.map(\.title) == ["Live native balance", "Prior transfer"])
        #expect(result.first?.detail == "Current balance: 42 wei")
        #expect(result.first?.chain == target.chain)
        #expect(result.first?.address == target.address)
    }

    /// A provider failure is a *monitoring gap*, not an alert — the test's old name said "alerts",
    /// and that is precisely what it was: `isSuccess == false` meant the composer rendered an RPC
    /// timeout into a durable, receipted artifact as an on-chain alert against the user's address,
    /// and once the watch's prepared-action trigger became "something failed", a network blip would
    /// have been the thing that queued a wallet draft for approval.
    @Test("Provider failures become bounded monitoring gaps without leaking provider details")
    func mapsProviderFailureToSafeObservation() async {
        let target = WatchTarget(
            chain: "base-mainnet",
            address: "0x0000000000000000000000000000000000000001"
        )
        let subject = LiveOnChainOperatorDataSource(
            localDataSource: OperatorActivityStub(activity: []),
            balanceProvider: NativeBalanceStub(result: .failure(NativeBalanceStubError.unavailable))
        )

        let result = await subject.recentActivity(
            matching: OperatorRequest(watchlist: [target]),
            limit: 10
        )

        #expect(result.count == 1)
        #expect(result.first?.title == "Live chain snapshot failed")
        #expect(result.first?.outcome == .unobserved)
        #expect(result.first?.isSuccess == false)
        #expect(result.first?.detail.contains("NativeBalanceStubError") == false)
    }

    /// A full watchlist must not starve the receipt-backed half.
    ///
    /// Every live snapshot is stamped `now()`, so live entries are always the newest things in the
    /// merged list, and the watchlist and the result share one `limit`. Sorting the union by
    /// recency and taking the prefix therefore meant that once the watchlist reached `limit`
    /// entries, the live balance snapshots evicted **every** receipt-backed event — including the
    /// `.failed` outcomes that are the only thing that prepares an action. The watch reported no
    /// history at all while the ledger was full of it. Below a full watchlist nothing was evicted,
    /// which is why it read as correct.
    @Test("A full watchlist still leaves room for receipt-backed history")
    func liveSnapshotsCannotEvictEveryReceiptBackedEvent() async {
        let snapshotDate = Date(timeIntervalSince1970: 9_000)
        let targets = (1...4).map { index in
            WatchTarget(chain: "eth-mainnet", address: "0x000000000000000000000000000000000000000\(index)")
        }
        let localHistory = (1...4).map { index in
            ObservedActivity(
                title: "Prior transfer \(index)",
                detail: "Receipt-backed observation",
                // Deliberately older than the live snapshots, which is the real ordering.
                occurredAt: Date(timeIntervalSince1970: TimeInterval(100 + index)),
                chain: targets[index - 1].chain,
                address: targets[index - 1].address
            )
        }
        let subject = LiveOnChainOperatorDataSource(
            localDataSource: OperatorActivityStub(activity: localHistory.reversed()),
            balanceProvider: NativeBalanceStub(result: .success(NativeBalance(weiHex: "0x2a", weiDecimal: "42"))),
            now: { snapshotDate }
        )

        let result = await subject.recentActivity(
            matching: OperatorRequest(watchlist: targets),
            limit: targets.count
        )

        #expect(result.count == targets.count)
        let receiptBacked = result.filter { $0.title.hasPrefix("Prior transfer") }
        let live = result.filter { $0.title == "Live native balance" }
        // Half each. Pre-fix this read 0 and 4.
        #expect(receiptBacked.count == 2)
        #expect(live.count == 2)
        // The reserved share keeps the *most recent* receipts, not an arbitrary two.
        #expect(receiptBacked.map(\.title) == ["Prior transfer 4", "Prior transfer 3"])
    }

    /// The reserved share is a floor, not a quota: an unused half flows to the other.
    @Test("An unused half gives its budget to the other")
    func anUnusedHalfReleasesItsBudget() async {
        let targets = (1...3).map { index in
            WatchTarget(chain: "eth-mainnet", address: "0x000000000000000000000000000000000000000\(index)")
        }

        // No local history at all — the live half should still fill the page.
        let liveOnly = LiveOnChainOperatorDataSource(
            localDataSource: OperatorActivityStub(activity: []),
            balanceProvider: NativeBalanceStub(result: .success(NativeBalance(weiHex: "0x2a", weiDecimal: "42"))),
            now: { Date(timeIntervalSince1970: 9_000) }
        )
        let liveResult = await liveOnly.recentActivity(
            matching: OperatorRequest(watchlist: targets),
            limit: 3
        )
        #expect(liveResult.count == 3)

        // No watch targets at all — the local half should still fill the page.
        let localOnly = LiveOnChainOperatorDataSource(
            localDataSource: OperatorActivityStub(activity: (1...3).map { index in
                ObservedActivity(
                    title: "Prior transfer \(index)",
                    detail: "Receipt-backed observation",
                    occurredAt: Date(timeIntervalSince1970: TimeInterval(100 + index)),
                    chain: "eth-mainnet",
                    address: "0x0000000000000000000000000000000000000001"
                )
            }),
            balanceProvider: NativeBalanceStub(result: .success(NativeBalance(weiHex: "0x2a", weiDecimal: "42")))
        )
        let localResult = await localOnly.recentActivity(
            matching: OperatorRequest(watchlist: []),
            limit: 3
        )
        #expect(localResult.count == 3)
    }

    /// `Array.prefix(_:)` has a `maxLength >= 0` precondition and `OperatorDataSource` states no
    /// contract for `limit`, so the guard is load-bearing rather than defensive.
    @Test(arguments: [0, -1])
    func aNonPositiveLimitYieldsNothingRatherThanTrapping(limit: Int) async {
        let subject = LiveOnChainOperatorDataSource(
            localDataSource: OperatorActivityStub(activity: []),
            balanceProvider: NativeBalanceStub(result: .success(NativeBalance(weiHex: "0x2a", weiDecimal: "42")))
        )

        let result = await subject.recentActivity(
            matching: OperatorRequest(watchlist: [
                WatchTarget(chain: "eth-mainnet", address: "0x0000000000000000000000000000000000000001")
            ]),
            limit: limit
        )

        #expect(result.isEmpty)
    }
}
