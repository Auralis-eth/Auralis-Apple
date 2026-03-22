import Foundation
import Testing
@testable import Auralis

@Suite struct ContextSnapshotTests {
    @Test("live context source builds a versioned snapshot with provenance-bearing scope fields")
    func liveContextSourceBuildsVersionedSnapshot() {
        let refreshDate = Date(timeIntervalSince1970: 1_700_000_000)
        let account = EOAccount(
            address: "0x1234567890abcdef1234567890abcdef12345678",
            access: .readonly,
            name: "Collector",
            addedAt: Date(timeIntervalSince1970: 1_699_999_000),
            lastSelectedAt: Date(timeIntervalSince1970: 1_700_000_100),
            trackedNFTCount: 42
        )
        account.currentChain = .baseMainnet

        let source = LiveContextSource(
            accountProvider: { account },
            addressProvider: { account.address },
            chainProvider: { .baseMainnet },
            modeProvider: { .observe },
            loadingProvider: { false },
            refreshedAtProvider: { refreshDate },
            freshnessTTLProvider: { 300 },
            prefersDemoDataProvider: { true }
        )

        let snapshot = source.snapshot()

        #expect(snapshot.version == .v0)
        #expect(snapshot.mode.value == AppMode.observe.rawValue)
        #expect(snapshot.scope.accountAddress.value == account.address)
        #expect(snapshot.scope.accountAddress.provenance == .userProvided)
        #expect(snapshot.scope.accountName.value == "Collector")
        #expect(snapshot.scope.selectedChains.value == [.baseMainnet])
        #expect(snapshot.scope.selectedChains.provenance == .userProvided)
        #expect(snapshot.libraryPointers.trackedNFTCount.value == 42)
        #expect(snapshot.localPreferences.prefersDemoData.value == true)
        #expect(snapshot.freshness.refreshState == .idle)
        #expect(snapshot.freshness.lastSuccessfulRefreshAt == refreshDate)
        #expect(snapshot.freshness.ttl == 300)
    }

    @Test("context snapshot remains valid when optional provider-backed values are absent")
    func contextSnapshotSupportsMissingOptionalValues() {
        let source = LiveContextSource(
            accountProvider: { nil },
            addressProvider: { "" },
            chainProvider: { .ethMainnet },
            modeProvider: { .observe },
            loadingProvider: { true },
            refreshedAtProvider: { nil }
        )

        let snapshot = source.snapshot()
        let appContext = AppContext(snapshot: snapshot)

        #expect(snapshot.balances.nativeBalanceDisplay.value == nil)
        #expect(snapshot.libraryPointers.musicCollectionCount.value == nil)
        #expect(snapshot.libraryPointers.receiptCount.value == nil)
        #expect(snapshot.freshness.refreshState == .refreshing)
        #expect(snapshot.freshness.lastSuccessfulRefreshAt == nil)
        #expect(appContext.accountDisplay == "No active account")
        #expect(appContext.chainDisplay == "Ethereum")
        #expect(appContext.freshnessLabel == "Refreshing now")
    }

    @Test("freshness becomes stale after the configured TTL expires")
    func contextSnapshotUsesTTLBackedStaleEvaluation() {
        let source = LiveContextSource(
            accountProvider: { nil },
            addressProvider: { "" },
            chainProvider: { .ethMainnet },
            modeProvider: { .observe },
            loadingProvider: { false },
            refreshedAtProvider: { Date().addingTimeInterval(-600) },
            freshnessTTLProvider: { 300 }
        )

        let snapshot = source.snapshot()

        #expect(snapshot.freshness.isStale)
        #expect(snapshot.freshnessLabel == "Stale")
    }

    @Test("future refresh timestamps clamp to a non-negative age instead of looking stale")
    func contextSnapshotClampsFutureRefreshTimestamps() {
        let source = LiveContextSource(
            accountProvider: { nil },
            addressProvider: { "" },
            chainProvider: { .ethMainnet },
            modeProvider: { .observe },
            loadingProvider: { false },
            refreshedAtProvider: { Date().addingTimeInterval(600) },
            freshnessTTLProvider: { 300 }
        )

        let snapshot = source.snapshot()

        #expect(snapshot.freshness.age == 0)
        #expect(snapshot.freshness.isStale == false)
        #expect(snapshot.freshnessLabel == "Fresh now")
    }
}

@MainActor
@Suite
struct ContextServiceTests {
    @Test("context service coalesces duplicate in-flight requests for the same scope")
    func contextServiceCoalescesDuplicateRequests() async {
        let builder = CountingContextSourceBuilder()
        let currentAddress = "0x1234567890abcdef1234567890abcdef12345678"
        let currentChain = Chain.ethMainnet
        let service = ContextService(
            contextSourceBuilder: builder,
            accountProvider: { nil },
            addressProvider: { currentAddress },
            chainProvider: { currentChain },
            modeProvider: { .observe },
            loadingProvider: { false },
            refreshedAtProvider: { nil },
            freshnessTTLProvider: { 300 },
            trackedNFTCountProvider: { nil },
            prefersDemoDataProvider: { false }
        )

        #expect(builder.buildCount == 1)

        async let first: ContextSnapshot = service.refresh()
        async let second: ContextSnapshot = service.refresh()

        let (firstSnapshot, secondSnapshot) = await (first, second)

        #expect(builder.buildCount == 2)
        #expect(firstSnapshot.scope.accountAddress.value == currentAddress)
        #expect(secondSnapshot.scope.accountAddress.value == currentAddress)
    }

    @Test("context service isolates rapid account switches so stale requests do not overwrite the latest scope")
    func contextServiceAvoidsStaleOverwriteOnRapidAccountSwitch() async {
        let builder = CountingContextSourceBuilder()
        let resolveGate = ControlledResolveGate()
        var currentAddress = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        let service = ContextService(
            contextSourceBuilder: builder,
            accountProvider: { nil },
            addressProvider: { currentAddress },
            chainProvider: { .ethMainnet },
            modeProvider: { .observe },
            loadingProvider: { false },
            refreshedAtProvider: { nil },
            freshnessTTLProvider: { 300 },
            trackedNFTCountProvider: { nil },
            prefersDemoDataProvider: { false },
            beforeResolve: {
                await resolveGate.waitIfNeeded()
            }
        )

        async let first: ContextSnapshot = service.refresh()
        await Task.yield()

        currentAddress = "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        let secondSnapshot = await service.refresh()

        resolveGate.releaseFirst()
        _ = await first

        #expect(secondSnapshot.scope.accountAddress.value == currentAddress)
        #expect(service.snapshot.scope.accountAddress.value == currentAddress)
        #expect(builder.buildCount == 3)
    }
}

private final class CountingContextSourceBuilder: ShellContextSourceBuilding {
    private let liveBuilder = LiveShellContextSourceBuilder()
    nonisolated(unsafe) private(set) var buildCount = 0

    func makeContextSource(
        accountProvider: @escaping () -> EOAccount?,
        addressProvider: @escaping () -> String,
        chainProvider: @escaping () -> Chain,
        modeProvider: @escaping () -> AppMode,
        loadingProvider: @escaping () -> Bool,
        refreshedAtProvider: @escaping () -> Date?,
        freshnessTTLProvider: @escaping () -> TimeInterval?,
        trackedNFTCountProvider: @escaping () -> Int?,
        prefersDemoDataProvider: @escaping () -> Bool?
    ) -> any ContextSource {
        buildCount += 1
        return liveBuilder.makeContextSource(
            accountProvider: accountProvider,
            addressProvider: addressProvider,
            chainProvider: chainProvider,
            modeProvider: modeProvider,
            loadingProvider: loadingProvider,
            refreshedAtProvider: refreshedAtProvider,
            freshnessTTLProvider: freshnessTTLProvider,
            trackedNFTCountProvider: trackedNFTCountProvider,
            prefersDemoDataProvider: prefersDemoDataProvider
        )
    }
}

@MainActor
private final class ControlledResolveGate {
    private var firstContinuation: CheckedContinuation<Void, Never>?
    private var waitCount = 0

    func waitIfNeeded() async {
        waitCount += 1
        guard waitCount == 1 else {
            return
        }

        await withCheckedContinuation { continuation in
            firstContinuation = continuation
        }
    }

    func releaseFirst() {
        firstContinuation?.resume()
        firstContinuation = nil
    }
}
