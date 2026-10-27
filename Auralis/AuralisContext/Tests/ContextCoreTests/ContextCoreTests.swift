import ContextCore
import Foundation
import Testing

struct ContextCoreTests {
    @Test(
        "Freshness labels reflect context age and state",
        arguments: [
            (ContextRefreshState.refreshing, Optional<TimeInterval>.none, "Refreshing now"),
            (.idle, nil, "Unknown"),
            (.idle, 30, "Fresh now"),
            (.idle, 120, "2m ago"),
            (.idle, 600, "Stale")
        ]
    )
    func freshnessLabel(
        state: ContextRefreshState,
        age: TimeInterval?,
        expectedLabel: String
    ) {
        let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
        let refreshedAt = age.map { referenceDate.addingTimeInterval(-$0) }
        let freshness = ContextFreshness(
            refreshState: state,
            lastSuccessfulRefreshAt: refreshedAt,
            lastSuccessfulRefreshProvenance: .localCache,
            ttl: 300,
            referenceDate: referenceDate
        )

        #expect(freshness.label == expectedLabel)
    }

    @Test("Future refresh timestamps clamp to a non-negative age")
    func futureTimestampClampsToZero() {
        let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
        let freshness = ContextFreshness(
            refreshState: .idle,
            lastSuccessfulRefreshAt: referenceDate.addingTimeInterval(60),
            lastSuccessfulRefreshProvenance: .onChain,
            ttl: 300,
            referenceDate: referenceDate
        )

        #expect(freshness.age == 0)
        #expect(freshness.isStale == false)
    }

    @Test("Context fields preserve value provenance and update time")
    func contextFieldPreservesMetadata() {
        let updatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let field = ContextField(
            "0x1234",
            provenance: .userProvided,
            updatedAt: updatedAt
        )

        #expect(field.value == "0x1234")
        #expect(field.provenance == .userProvided)
        #expect(field.updatedAt == updatedAt)
    }

    @Test("Snapshot summaries remain domain-neutral and provenance-bearing")
    func snapshotSummaries() {
        let snapshot = ContextSnapshot(
            version: .v0,
            mode: ContextField("observe", provenance: .localCache),
            scope: ContextScope(
                accountAddress: ContextField(
                    "0x1234567890abcdef1234567890abcdef12345678",
                    provenance: .userProvided
                ),
                accountName: ContextField("Collector", provenance: .localCache),
                selectedChains: ContextField(
                    [ContextChainReference(id: "base-mainnet", displayName: "Base")],
                    provenance: .userProvided
                )
            ),
            balances: ContextBalancesSummary(
                nativeBalanceDisplay: ContextField(nil, provenance: .localCache),
                nativeBalanceStatusMessage: ContextField(nil, provenance: .localCache)
            ),
            libraryPointers: ContextLibraryPointers(
                trackedNFTCount: ContextField(12, provenance: .localCache),
                musicCollectionCount: ContextField(4, provenance: .localCache),
                receiptCount: ContextField(9, provenance: .localCache)
            ),
            modulePointers: ContextModulePointers(items: []),
            localPreferences: ContextLocalPreferences(
                prefersDemoData: ContextField(false, provenance: .userProvided),
                pinnedItemCount: ContextField(3, provenance: .userProvided)
            ),
            freshness: ContextFreshness(
                refreshState: .idle,
                lastSuccessfulRefreshAt: nil,
                lastSuccessfulRefreshProvenance: .localCache,
                ttl: 300
            )
        )

        #expect(snapshot.scopeSummary == "Collector • Base")
        #expect(snapshot.librarySummary == "NFTs: 12 • Playlists: 4 • Receipts: 9")
        #expect(snapshot.preferencesSummary == "Demo Data: Off • Pinned Items: 3")
        #expect(snapshot.modeDisplay == "Observe")
    }
}
