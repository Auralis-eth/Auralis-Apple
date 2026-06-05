import ReceiptsCore
import ReceiptStorage
@testable import Auralis
import AuralisPrimaryModels
import AuralisPrimaryPersistence
import Foundation
import PolicyCore
import ProviderKit
import SwiftData
import Testing

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
            prefersDemoDataProvider: { true },
            pinnedItemCountProvider: { 2 }
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
        #expect(snapshot.modulePointers.items.count == HomeLauncherAction.allCases.count)
        #expect(snapshot.primaryModuleSummary == "Music • NFT Tokens")
        #expect(snapshot.shortcutModuleSummary == "Search • News Feed • Receipts")
        #expect(snapshot.pinnedModuleSummary == "No pinned shortcuts")
        #expect(snapshot.localPreferences.prefersDemoData.value == true)
        #expect(snapshot.localPreferences.pinnedItemCount.value == 2)
        #expect(snapshot.freshness.refreshState == .idle)
        #expect(snapshot.freshness.lastSuccessfulRefreshAt == refreshDate)
        #expect(snapshot.freshness.ttl == 300)
        #expect(snapshot.librarySummary == "NFTs: 42 • Playlists: 3 • Receipts: 7")
        #expect(snapshot.preferencesSummary == "Demo Data: On • Pinned Items: 2")
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
            pinnedActionsProvider: { [.openSearch, .openReceipts] },
            prefersDemoDataProvider: { true },
            pinnedItemCountProvider: { 3 }
        )

        let snapshot = source.snapshot()

        #expect(snapshot.libraryPointers.trackedNFTCount.value == 12)
        #expect(snapshot.libraryPointers.musicCollectionCount.value == 4)
        #expect(snapshot.libraryPointers.receiptCount.value == 9)
        #expect(snapshot.modulePointers.items.filter(\.isPinned).map(\.routeID).sorted() == ["openReceipts", "openSearch"])
        #expect(snapshot.localPreferences.prefersDemoData.value == true)
        #expect(snapshot.localPreferences.pinnedItemCount.value == 3)
        #expect(snapshot.libraryPointers.receiptCount.updatedAt == Date(timeIntervalSince1970: 1_700_000_500))
        #expect(snapshot.librarySummary == "NFTs: 12 • Playlists: 4 • Receipts: 9")
        #expect(snapshot.preferencesSummary == "Demo Data: On • Pinned Items: 3")
        #expect(snapshot.pinnedModuleSummary == "Search, Receipts")
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
        let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
        let source = LiveContextSource(
            accountProvider: { nil },
            addressProvider: { "" },
            chainProvider: { .ethMainnet },
            modeProvider: { .observe },
            loadingProvider: { false },
            refreshedAtProvider: { referenceDate.addingTimeInterval(-600) },
            freshnessTTLProvider: { 300 },
            nowProvider: { referenceDate }
        )

        let snapshot = source.snapshot()

        #expect(snapshot.freshness.isStale)
        #expect(snapshot.freshnessLabel == "Stale")
    }

    @Test("freshness stays relative while inside TTL and uses the shared label contract")
    func contextSnapshotUsesSharedFreshnessLabelContract() {
        let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
        let refreshedAt = referenceDate.addingTimeInterval(-120)
        let source = LiveContextSource(
            accountProvider: { nil },
            addressProvider: { "" },
            chainProvider: { .ethMainnet },
            modeProvider: { .observe },
            loadingProvider: { false },
            refreshedAtProvider: { refreshedAt },
            freshnessTTLProvider: { 300 },
            nowProvider: { referenceDate }
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
        let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
        let source = LiveContextSource(
            accountProvider: { nil },
            addressProvider: { "" },
            chainProvider: { .ethMainnet },
            modeProvider: { .observe },
            loadingProvider: { false },
            refreshedAtProvider: { referenceDate.addingTimeInterval(600) },
            freshnessTTLProvider: { 300 },
            nowProvider: { referenceDate }
        )

        let snapshot = source.snapshot()

        #expect(snapshot.freshness.age == 0)
        #expect(snapshot.freshness.isStale == false)
        #expect(snapshot.freshnessLabel == "Fresh now")
    }

    @Test("refreshing freshness does not show stale even when the last success is older than TTL")
    func refreshingFreshnessOverridesStaleLabel() {
        let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
        let source = LiveContextSource(
            accountProvider: { nil },
            addressProvider: { "" },
            chainProvider: { .ethMainnet },
            modeProvider: { .observe },
            loadingProvider: { true },
            refreshedAtProvider: { referenceDate.addingTimeInterval(-600) },
            freshnessTTLProvider: { 300 },
            nowProvider: { referenceDate }
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
            pinnedActionsProvider: { [] },
            prefersDemoDataProvider: { false },
            pinnedItemCountProvider: { 0 }
        )

        #expect(builder.buildCount == 1)

        async let first: ContextSnapshot = service.refresh()
        async let second: ContextSnapshot = service.refresh()

        let (firstSnapshot, secondSnapshot) = await (first, second)

        #expect(builder.buildCount == 2)
        #expect(firstSnapshot.scope.accountAddress.value == currentAddress)
        #expect(secondSnapshot.scope.accountAddress.value == currentAddress)
    }

    @Test(
        "context service isolates rapid account switches so stale requests do not overwrite the latest scope",
        .timeLimit(.minutes(1))
    )
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
            pinnedActionsProvider: { [] },
            prefersDemoDataProvider: { false },
            pinnedItemCountProvider: { 0 },
            beforeResolve: {
                await resolveGate.waitIfNeeded()
            }
        )

        async let first: ContextSnapshot = service.refresh()
        await resolveGate.waitUntilFirstIsSuspended()

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
        let container = try TestModelContainers.inMemory(TestSchemas.receipts)
        let modelContext = ModelContext(container)
        let receiptStore = SwiftDataReceiptStore(
            modelContext: modelContext,
            sequenceAllocator: ReceiptSequenceAllocator()
        )
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
            pinnedActionsProvider: { [] },
            prefersDemoDataProvider: { false },
            pinnedItemCountProvider: { 0 }
        )

        _ = await service.refresh(
            correlationID: "context-build-1",
            receiptEventLogger: logger
        )

        let receipts = try await receiptStore.receipts(
            forCorrelationID: "context-build-1",
            limit: 10
        )
        #expect(receipts.map { $0.kind } == ["context.built"])
    }

    @Test(
        "racing context refreshes keep each context-built receipt tied to the resolved scope and correlation",
        .timeLimit(.minutes(1))
    )
    func contextServiceRaceKeepsReceiptScopeBoundToResolvedSnapshot() async throws {
        let builder = CountingContextSourceBuilder()
        let resolveGate = ControlledResolveGate()
        let container = try TestModelContainers.inMemory(TestSchemas.receipts)
        let modelContext = ModelContext(container)
        let receiptStore = SwiftDataReceiptStore(
            modelContext: modelContext,
            sequenceAllocator: ReceiptSequenceAllocator()
        )
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
            pinnedActionsProvider: { [] },
            prefersDemoDataProvider: { false },
            pinnedItemCountProvider: { 0 },
            beforeResolve: {
                await resolveGate.waitIfNeeded()
            }
        )

        async let firstSnapshot: ContextSnapshot = service.refresh(
            correlationID: "context-race-1",
            receiptEventLogger: logger
        )
        await resolveGate.waitUntilFirstIsSuspended()

        currentAddress = "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        let secondSnapshot = await service.refresh(
            correlationID: "context-race-2",
            receiptEventLogger: logger
        )

        resolveGate.releaseFirst()
        let resolvedFirstSnapshot = await firstSnapshot

        let firstReceipts = try await receiptStore.receipts(forCorrelationID: "context-race-1", limit: 10)
        let secondReceipts = try await receiptStore.receipts(forCorrelationID: "context-race-2", limit: 10)

        let firstReceipt = try #require(firstReceipts.first)
        let secondReceipt = try #require(secondReceipts.first)

        #expect(resolvedFirstSnapshot.scope.accountAddress.value == "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
        #expect(secondSnapshot.scope.accountAddress.value == "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
        #expect(service.snapshot.scope.accountAddress.value == "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
        guard case .string(let firstAccountValue)? = firstReceipt.details.values["accountAddress"] else {
            Issue.record("Expected hashed first account address")
            return
        }
        guard case .string(let secondAccountValue)? = secondReceipt.details.values["accountAddress"] else {
            Issue.record("Expected hashed second account address")
            return
        }
        #expect(firstAccountValue == "<redacted-opaque-token>")
        #expect(secondAccountValue == "<redacted-opaque-token>")
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
            pinnedActionsProvider: { [] },
            prefersDemoDataProvider: { false },
            pinnedItemCountProvider: { 0 }
        )

        let snapshot = await service.refresh()

        #expect(await provider.requestCount() == 1)
        #expect(snapshot.balances.nativeBalanceDisplay.value == "1.5 ETH")
        #expect(snapshot.balances.nativeBalanceDisplay.provenance == .onChain)
    }

    @Test("context service keeps the last native balance for the same scope when refresh fails")
    func contextServiceKeepsCachedNativeBalanceOnRefreshFailure() async {
        let builder = CountingContextSourceBuilder()
        let provider = SequencedNativeBalanceProvider(
            results: [
                .success(
                    NativeBalance(
                        weiHex: "0x14d1120d7b160000",
                        weiDecimal: "1500000000000000000"
                    )
                ),
                .failure(URLError(.timedOut))
            ]
        )
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
            pinnedActionsProvider: { [] },
            prefersDemoDataProvider: { false },
            pinnedItemCountProvider: { 0 }
        )

        let firstSnapshot = await service.refresh()
        let secondSnapshot = await service.refresh()

        #expect(firstSnapshot.balances.nativeBalanceDisplay.value == "1.5 ETH")
        #expect(firstSnapshot.balances.nativeBalanceDisplay.provenance == .onChain)
        #expect(secondSnapshot.balances.nativeBalanceDisplay.value == "1.5 ETH")
        #expect(secondSnapshot.balances.nativeBalanceDisplay.provenance == .localCache)
        #expect(secondSnapshot.balances.nativeBalanceStatusMessage.value == "Auralis kept the last native balance because the live provider did not respond cleanly for this wallet and chain.")
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
        nativeBalanceStatusMessageProvider: @escaping () -> String?,
        nativeBalanceUpdatedAtProvider: @escaping () -> Date?,
        nativeBalanceProvenanceProvider: @escaping () -> ContextProvenance,
        freshnessTTLProvider: @escaping () -> TimeInterval?,
        trackedNFTCountProvider: @escaping () -> Int?,
        musicCollectionCountProvider: @escaping () -> Int?,
        receiptCountProvider: @escaping () -> Int?,
        pinnedActionsProvider: @escaping () -> [HomeLauncherAction],
        prefersDemoDataProvider: @escaping () -> Bool?,
        pinnedItemCountProvider: @escaping () -> Int?
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
            nativeBalanceStatusMessageProvider: nativeBalanceStatusMessageProvider,
            nativeBalanceUpdatedAtProvider: nativeBalanceUpdatedAtProvider,
            nativeBalanceProvenanceProvider: nativeBalanceProvenanceProvider,
            freshnessTTLProvider: freshnessTTLProvider,
            trackedNFTCountProvider: trackedNFTCountProvider,
            musicCollectionCountProvider: musicCollectionCountProvider,
            receiptCountProvider: receiptCountProvider,
            pinnedActionsProvider: pinnedActionsProvider,
            prefersDemoDataProvider: prefersDemoDataProvider,
            pinnedItemCountProvider: pinnedItemCountProvider
        )
    }
}

private actor StubNativeBalanceProvider: NativeBalanceProviding {
    private var requests: [(address: String, chain: Chain)] = []

    func nativeBalance(for address: String, chain: Chain) async throws -> NativeBalance {
        requests.append((address, chain))
        return NativeBalance(
            weiHex: "0x14d1120d7b160000",
            weiDecimal: "1500000000000000000"
        )
    }

    func requestCount() -> Int {
        requests.count
    }
}

private actor SequencedNativeBalanceProvider: NativeBalanceProviding {
    private var results: [Result<NativeBalance, Error>]

    init(results: [Result<NativeBalance, Error>]) {
        self.results = results
    }

    func nativeBalance(for address: String, chain: Chain) async throws -> NativeBalance {
        let nextResult = results.isEmpty ? .failure(URLError(.badServerResponse)) : results.removeFirst()
        switch nextResult {
        case .success(let balance):
            return balance
        case .failure(let error):
            throw error
        }
    }
}

@MainActor
private final class ControlledResolveGate {
    private var firstContinuation: CheckedContinuation<Void, Never>?
    private var firstDidSuspendContinuation: CheckedContinuation<Void, Never>?
    private var didSuspendFirst = false
    private var waitCount = 0

    func waitIfNeeded() async {
        waitCount += 1
        guard waitCount == 1 else {
            return
        }

        didSuspendFirst = true
        firstDidSuspendContinuation?.resume()
        firstDidSuspendContinuation = nil

        await withCheckedContinuation { continuation in
            firstContinuation = continuation
        }
    }

    func waitUntilFirstIsSuspended() async {
        guard !didSuspendFirst else {
            return
        }

        await withCheckedContinuation { continuation in
            firstDidSuspendContinuation = continuation
        }
    }

    func releaseFirst() {
        firstContinuation?.resume()
        firstContinuation = nil
    }
}
