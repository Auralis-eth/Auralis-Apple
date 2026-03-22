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
