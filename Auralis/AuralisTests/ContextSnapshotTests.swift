import Foundation
import SwiftData
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
            musicCollectionCountProvider: { 3 },
            receiptCountProvider: { 7 },
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
        #expect(snapshot.libraryPointers.musicCollectionCount.value == 3)
        #expect(snapshot.libraryPointers.receiptCount.value == 7)
        #expect(snapshot.localPreferences.prefersDemoData.value == true)
        #expect(snapshot.freshness.refreshState == .idle)
        #expect(snapshot.freshness.lastSuccessfulRefreshAt == refreshDate)
        #expect(snapshot.freshness.ttl == 300)
        #expect(snapshot.librarySummary == "NFTs: 42 • Playlists: 3 • Receipts: 7")
        #expect(snapshot.preferencesSummary == "Demo Data: On • Pinned Items: Unknown")
    }

    @Test("context snapshot uses local count providers and guest-pass preference without inventing provider data")
    func contextSnapshotUsesLocalSchemaInputs() {
        let source = LiveContextSource(
            accountProvider: { nil },
            addressProvider: { "0x1234567890abcdef1234567890abcdef12345678" },
            chainProvider: { .baseMainnet },
            modeProvider: { .observe },
            loadingProvider: { false },
            refreshedAtProvider: { Date(timeIntervalSince1970: 1_700_000_500) },
            trackedNFTCountProvider: { 12 },
            musicCollectionCountProvider: { 4 },
            receiptCountProvider: { 9 },
            prefersDemoDataProvider: { true }
        )

        let snapshot = source.snapshot()

        #expect(snapshot.libraryPointers.trackedNFTCount.value == 12)
        #expect(snapshot.libraryPointers.musicCollectionCount.value == 4)
        #expect(snapshot.libraryPointers.receiptCount.value == 9)
        #expect(snapshot.localPreferences.prefersDemoData.value == true)
        #expect(snapshot.libraryPointers.receiptCount.updatedAt == Date(timeIntervalSince1970: 1_700_000_500))
        #expect(snapshot.librarySummary == "NFTs: 12 • Playlists: 4 • Receipts: 9")
        #expect(snapshot.preferencesSummary == "Demo Data: On • Pinned Items: Unknown")
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

    @Test("freshness stays relative while inside TTL and uses the shared label contract")
    func contextSnapshotUsesSharedFreshnessLabelContract() {
        let refreshedAt = Date().addingTimeInterval(-120)
        let source = LiveContextSource(
            accountProvider: { nil },
            addressProvider: { "" },
            chainProvider: { .ethMainnet },
            modeProvider: { .observe },
            loadingProvider: { false },
            refreshedAtProvider: { refreshedAt },
            freshnessTTLProvider: { 300 }
        )

        let snapshot = source.snapshot()
        let appContext = AppContext(snapshot: snapshot)

        #expect(snapshot.freshness.isStale == false)
        #expect(snapshot.freshness.label == "2m ago")
        #expect(snapshot.freshnessLabel == "2m ago")
        #expect(appContext.freshnessLabel == snapshot.freshness.label)
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

    @Test("refreshing freshness does not show stale even when the last success is older than TTL")
    func refreshingFreshnessOverridesStaleLabel() {
        let source = LiveContextSource(
            accountProvider: { nil },
            addressProvider: { "" },
            chainProvider: { .ethMainnet },
            modeProvider: { .observe },
            loadingProvider: { true },
            refreshedAtProvider: { Date().addingTimeInterval(-600) },
            freshnessTTLProvider: { 300 }
        )

        let snapshot = source.snapshot()

        #expect(snapshot.freshness.isStale == false)
        #expect(snapshot.freshness.label == "Refreshing now")
        #expect(snapshot.freshnessLabel == "Refreshing now")
    }

    @Test("context snapshot provides shell-facing account title and scope summary fallbacks")
    func contextSnapshotProvidesShellFacingSummary() {
        let namedSnapshot = LiveContextSource(
            accountProvider: {
                EOAccount(
                    address: "0x1234567890abcdef1234567890abcdef12345678",
                    access: .readonly,
                    name: "Collector"
                )
            },
            addressProvider: { "0x1234567890abcdef1234567890abcdef12345678" },
            chainProvider: { .baseMainnet },
            modeProvider: { .observe },
            loadingProvider: { false },
            refreshedAtProvider: { nil }
        ).snapshot()

        let fallbackSnapshot = LiveContextSource(
            accountProvider: { nil },
            addressProvider: { "0x1234567890abcdef1234567890abcdef12345678" },
            chainProvider: { .ethMainnet },
            modeProvider: { .observe },
            loadingProvider: { false },
            refreshedAtProvider: { nil }
        ).snapshot()

        #expect(namedSnapshot.chromeAccountTitle == "Collector")
        #expect(namedSnapshot.scopeSummary.contains("Collector"))
        #expect(fallbackSnapshot.chromeAccountTitle == "0x1234...5678")
        #expect(fallbackSnapshot.scopeSummary.contains("Ethereum"))
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
            nativeBalanceProvider: StubNativeBalanceProvider(),
            freshnessTTLProvider: { 300 },
            trackedNFTCountProvider: { nil },
            musicCollectionCountProvider: { nil },
            receiptCountProvider: { nil },
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
            nativeBalanceProvider: StubNativeBalanceProvider(),
            freshnessTTLProvider: { 300 },
            trackedNFTCountProvider: { nil },
            musicCollectionCountProvider: { nil },
            receiptCountProvider: { nil },
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

    @Test("context service refresh emits a context-built receipt when a logger is provided")
    func contextServiceRefreshEmitsReceipt() async throws {
        let builder = CountingContextSourceBuilder()
        let schema = Schema([StoredReceipt.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let modelContext = ModelContext(container)
        let receiptStore = SwiftDataReceiptStore(modelContext: modelContext)
        let logger = ReceiptEventLogger(receiptStore: receiptStore)

        let service = ContextService(
            contextSourceBuilder: builder,
            accountProvider: { nil },
            addressProvider: { "0x1234567890abcdef1234567890abcdef12345678" },
            chainProvider: { .ethMainnet },
            modeProvider: { .observe },
            loadingProvider: { false },
            refreshedAtProvider: { nil },
            nativeBalanceProvider: StubNativeBalanceProvider(),
            freshnessTTLProvider: { 300 },
            trackedNFTCountProvider: { nil },
            musicCollectionCountProvider: { nil },
            receiptCountProvider: { nil },
            prefersDemoDataProvider: { false }
        )

        _ = await service.refresh(
            correlationID: "context-build-1",
            receiptEventLogger: logger
        )

        let receipts = try receiptStore.receipts(
            forCorrelationID: "context-build-1",
            limit: 10
        )
        #expect(receipts.map { $0.kind } == ["context.built"])
    }

    @Test("racing context refreshes keep each context-built receipt tied to the resolved scope and correlation")
    func contextServiceRaceKeepsReceiptScopeBoundToResolvedSnapshot() async throws {
        let builder = CountingContextSourceBuilder()
        let resolveGate = ControlledResolveGate()
        let schema = Schema([StoredReceipt.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let modelContext = ModelContext(container)
        let receiptStore = SwiftDataReceiptStore(modelContext: modelContext)
        let logger = ReceiptEventLogger(receiptStore: receiptStore)

        var currentAddress = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        let service = ContextService(
            contextSourceBuilder: builder,
            accountProvider: { nil },
            addressProvider: { currentAddress },
            chainProvider: { .ethMainnet },
            modeProvider: { .observe },
            loadingProvider: { false },
            refreshedAtProvider: { nil },
            nativeBalanceProvider: StubNativeBalanceProvider(),
            freshnessTTLProvider: { 300 },
            trackedNFTCountProvider: { nil },
            musicCollectionCountProvider: { nil },
            receiptCountProvider: { nil },
            prefersDemoDataProvider: { false },
            beforeResolve: {
                await resolveGate.waitIfNeeded()
            }
        )

        async let firstSnapshot: ContextSnapshot = service.refresh(
            correlationID: "context-race-1",
            receiptEventLogger: logger
        )
        await Task.yield()

        currentAddress = "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        let secondSnapshot = await service.refresh(
            correlationID: "context-race-2",
            receiptEventLogger: logger
        )

        resolveGate.releaseFirst()
        let resolvedFirstSnapshot = await firstSnapshot

        let firstReceipts = try receiptStore.receipts(forCorrelationID: "context-race-1", limit: 10)
        let secondReceipts = try receiptStore.receipts(forCorrelationID: "context-race-2", limit: 10)

        let firstReceipt = try #require(firstReceipts.first)
        let secondReceipt = try #require(secondReceipts.first)

        #expect(resolvedFirstSnapshot.scope.accountAddress.value == "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
        #expect(secondSnapshot.scope.accountAddress.value == "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
        #expect(service.snapshot.scope.accountAddress.value == "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
        #expect(firstReceipt.details.values["accountAddress"] == .string("0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"))
        #expect(secondReceipt.details.values["accountAddress"] == .string("0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"))
    }

    @Test("context service resolves native balance through the injected read-only provider seam")
    func contextServiceLoadsNativeBalanceThroughProvider() async {
        let builder = CountingContextSourceBuilder()
        let provider = StubNativeBalanceProvider()
        let service = ContextService(
            contextSourceBuilder: builder,
            accountProvider: { nil },
            addressProvider: { "0x1234567890abcdef1234567890abcdef12345678" },
            chainProvider: { .ethMainnet },
            modeProvider: { .observe },
            loadingProvider: { false },
            refreshedAtProvider: { nil },
            nativeBalanceProvider: provider,
            freshnessTTLProvider: { 300 },
            trackedNFTCountProvider: { nil },
            musicCollectionCountProvider: { nil },
            receiptCountProvider: { nil },
            prefersDemoDataProvider: { false }
        )

        let snapshot = await service.refresh()

        #expect(provider.requests.count == 1)
        #expect(snapshot.balances.nativeBalanceDisplay.value == "1.5 ETH")
        #expect(snapshot.balances.nativeBalanceDisplay.provenance == .onChain)
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
        nativeBalanceDisplayProvider: @escaping () -> String?,
        nativeBalanceUpdatedAtProvider: @escaping () -> Date?,
        nativeBalanceProvenanceProvider: @escaping () -> ContextProvenance,
        freshnessTTLProvider: @escaping () -> TimeInterval?,
        trackedNFTCountProvider: @escaping () -> Int?,
        musicCollectionCountProvider: @escaping () -> Int?,
        receiptCountProvider: @escaping () -> Int?,
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
            nativeBalanceDisplayProvider: nativeBalanceDisplayProvider,
            nativeBalanceUpdatedAtProvider: nativeBalanceUpdatedAtProvider,
            nativeBalanceProvenanceProvider: nativeBalanceProvenanceProvider,
            freshnessTTLProvider: freshnessTTLProvider,
            trackedNFTCountProvider: trackedNFTCountProvider,
            musicCollectionCountProvider: musicCollectionCountProvider,
            receiptCountProvider: receiptCountProvider,
            prefersDemoDataProvider: prefersDemoDataProvider
        )
    }
}

private final class StubNativeBalanceProvider: NativeBalanceProviding {
    private(set) var requests: [(address: String, chain: Chain)] = []

    func nativeBalance(for address: String, chain: Chain) async throws -> NativeBalance {
        requests.append((address, chain))
        return NativeBalance(
            weiHex: "0x14d1120d7b160000",
            weiDecimal: "1500000000000000000"
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
