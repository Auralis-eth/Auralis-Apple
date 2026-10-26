import AccountsCore
import AuralisPrimaryModels
import Foundation
import OperatorsFeature
import ProviderKit
import RuntimeCore

/// Adds bounded, read-only RPC snapshots to the local receipt history used by operators.
/// The adapter exposes only native balances for explicitly supplied watch targets; it cannot sign,
/// submit transactions, enumerate unrelated accounts, or widen the caller's requested scope.
struct LiveOnChainOperatorDataSource: OperatorDataSource {
    private let localDataSource: any OperatorDataSource
    private let balanceProvider: any NativeBalanceProviding
    private let now: @Sendable () -> Date

    init(
        localDataSource: any OperatorDataSource,
        balanceProvider: any NativeBalanceProviding,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.localDataSource = localDataSource
        self.balanceProvider = balanceProvider
        self.now = now
    }

    func recentActivity(matching request: OperatorRequest, limit: Int) async -> [ObservedActivity] {
        // Bounded **once**, at the top, and that single value is what every half is given.
        //
        // `Array.prefix(_:)` has a `maxLength >= 0` precondition and `OperatorDataSource` declares
        // `limit: Int` with no stated contract, so a negative limit traps. Two of the three uses
        // were individually guarded with `max(0, limit)` and the third — the pass-through to the
        // wrapped local source — was not, which is exactly the asymmetry that reads as deliberate
        // and is not: the trap simply moved into whatever implementation sits behind
        // `localDataSource`, one frame further from the guard that looked like it covered this.
        let bounded = max(0, limit)
        async let localActivity = localDataSource.recentActivity(matching: request, limit: bounded)
        // `limit` bounds the *work*, not just the result. Each target costs one live RPC round trip,
        // so taking the prefix here rather than only on the merged output keeps a long watchlist
        // from issuing calls whose answers are then discarded by the merge below.
        let liveActivity = await liveSnapshots(for: Array(request.watchlist.prefix(bounded)))
        return Self.merged(local: await localActivity, live: liveActivity, limit: bounded)
    }

    /// Merges the two halves under a *reserved share* rather than by recency alone.
    ///
    /// Sorting the union by `occurredAt` and taking the prefix looked right and starved the half
    /// that matters most. Every live snapshot is stamped `now()`, so live entries are always the
    /// newest things in the merged list — and the watchlist and the result share one `limit`. Once
    /// the watchlist reaches `limit` entries (50 in the shipping path), the 50 live balance
    /// snapshots fill the whole prefix and evict **every** receipt-backed event, including the
    /// `.failed` outcomes that are the only thing that prepares an action. A 50-account watch
    /// reported "0 alerts" no matter what the ledger held. Below ~50 targets nothing is evicted,
    /// which is exactly why it read as fine.
    ///
    /// Each half is therefore guaranteed up to half the budget, and whatever one half does not use
    /// flows to the other — so a watch with no local history still gets a full page of live
    /// snapshots, and a watch with no live targets still gets a full page of receipts.
    static func merged(
        local: [ObservedActivity],
        live: [ObservedActivity],
        limit: Int
    ) -> [ObservedActivity] {
        guard limit > 0 else { return [] }
        let localByRecency = local.sorted { $0.occurredAt > $1.occurredAt }
        let liveByRecency = live.sorted { $0.occurredAt > $1.occurredAt }
        // The local half is floored first, so an odd budget favours receipt-backed history over a
        // balance snapshot that can be re-read at any time.
        let localFloor = min(localByRecency.count, (limit + 1) / 2)
        let liveTake = min(liveByRecency.count, limit - localFloor)
        let localTake = min(localByRecency.count, limit - liveTake)
        return (localByRecency.prefix(localTake) + liveByRecency.prefix(liveTake))
            .sorted { $0.occurredAt > $1.occurredAt }
    }

    private func liveSnapshots(for targets: [WatchTarget]) async -> [ObservedActivity] {
        await withTaskGroup(of: ObservedActivity?.self) { group in
            for target in targets {
                group.addTask {
                    // `.unobserved`, not `.failed`. These two arms report *our* inability to look —
                    // an unsupported chain and a provider error — not anything that happened to the
                    // watched account. Reported as failures they were rendered into a durable,
                    // receipted artifact as on-chain alerts against the user's address, and once the
                    // watch's prepared-action trigger became "something failed", a network blip
                    // would have been the thing that queued a wallet draft for approval.
                    guard let chain = Self.resolveChain(target.chain) else {
                        return ObservedActivity(
                            title: "Live chain snapshot unavailable",
                            detail: "The selected chain is not supported by the read-only provider.",
                            occurredAt: now(),
                            chain: target.chain,
                            address: target.address,
                            outcome: .unobserved
                        )
                    }

                    do {
                        let balance = try await balanceProvider.nativeBalance(for: target.address, chain: chain)
                        return ObservedActivity(
                            title: "Live native balance",
                            detail: "Current balance: \(balance.weiDecimal) wei",
                            occurredAt: now(),
                            chain: target.chain,
                            address: target.address,
                            outcome: .succeeded
                        )
                    } catch is CancellationError {
                        return nil
                    } catch {
                        return ObservedActivity(
                            title: "Live chain snapshot failed",
                            detail: "The read-only provider could not refresh this target.",
                            occurredAt: now(),
                            chain: target.chain,
                            address: target.address,
                            outcome: .unobserved
                        )
                    }
                }
            }

            var snapshots: [ObservedActivity] = []
            for await snapshot in group {
                if let snapshot { snapshots.append(snapshot) }
            }
            return snapshots
        }
    }

    /// Resolved through the one chain vocabulary the governance stack uses, rather than a local
    /// alias table.
    ///
    /// This used to be a fourth private copy of that table, and a narrower one: it omitted the
    /// testnets (`sepolia`, `base-sepolia-testnet`) that `StandardCheckConfiguration.allowedChains`
    /// admits and that `RuntimeAssembly.governedChainScope` widens to every EVM chain. So a watch on
    /// a chain the policy had already authorized came back as "chain not supported". Divergence here
    /// also now shows up directly in the report, because `WatchTarget.chainKey` canonicalizes the
    /// same way the checks do — a chain this resolver rejected but the composer matched would be a
    /// target reporting a monitoring gap for a chain it is perfectly able to read.
    private static func resolveChain(_ value: String) -> Chain? {
        ChainScopeReference.resolve(value)
    }
}
