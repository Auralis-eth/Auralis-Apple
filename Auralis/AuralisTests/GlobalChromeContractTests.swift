@testable import Auralis
import Foundation
import Testing

@Suite
struct GlobalChromeContractTests {
    @Test("chrome-facing snapshot fields expose account scope freshness and preference context")
    func chromeSnapshotFieldsStayReadable() {
        let snapshot = LiveContextSource(
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
            refreshedAtProvider: { Date().addingTimeInterval(-120) },
            freshnessTTLProvider: { 300 },
            prefersDemoDataProvider: { false },
            pinnedItemCountProvider: { 2 }
        ).snapshot()

        #expect(snapshot.modeDisplay == "Observe")
        #expect(snapshot.chromeAccountTitle == "Collector")
        #expect(snapshot.selectedChainDisplayNames == "Base")
        #expect(snapshot.scopeSummary == "Collector • Base")
        #expect(snapshot.freshnessLabel == snapshot.freshness.label)
        #expect(snapshot.preferencesSummary == "Demo Data: Off • Pinned Items: 2")
    }

    @Test("chrome-facing snapshot falls back to canonical address when the account has no display name")
    func chromeSnapshotFallsBackToAddressSummary() {
        let snapshot = LiveContextSource(
            accountProvider: { nil },
            addressProvider: { "0x1234567890abcdef1234567890abcdef12345678" },
            chainProvider: { .ethMainnet },
            modeProvider: { .observe },
            loadingProvider: { false },
            refreshedAtProvider: { nil }
        ).snapshot()

        #expect(snapshot.chromeAccountTitle == "0x1234...5678")
        #expect(snapshot.scopeSummary == "0x1234...5678 • Ethereum")
        #expect(snapshot.freshnessLabel == "Freshness Unknown")
    }
}
