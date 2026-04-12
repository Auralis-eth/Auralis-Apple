import Foundation
import Testing
@testable import Auralis

@Suite
struct ShellStatusPresentationTests {
    @Test("provider failure status uses degraded warning chrome and retry when the provider is recoverable")
    func providerFailureStatusUsesExpectedTone() throws {
        let failure = try #require(
            NFTProviderFailure(
                error: NFTFetcher.FetcherError.networkError(URLError(.notConnectedToInternet))
            )
        ).presentation(mode: .degraded)

        let presentation = ShellProviderFailureStateView.presentation(for: failure)

        #expect(presentation.eyebrow == "Degraded Mode")
        #expect(presentation.title == "Refresh Paused")
        #expect(presentation.systemImage == "bolt.horizontal.circle")
        #expect(presentation.tone == .warning)
        #expect(presentation.primaryAction?.title == "Try Again")
    }

    @Test("provider failure status uses blocking critical chrome when the failure replaces the surface")
    func blockingFailureStatusUsesCriticalTone() throws {
        let failure = try #require(
            NFTProviderFailure(
                error: DecodingError.dataCorrupted(
                    .init(codingPath: [], debugDescription: "Unreadable provider payload.")
                )
            )
        ).presentation(mode: .blocking)

        let presentation = ShellProviderFailureStateView.presentation(for: failure)

        #expect(presentation.eyebrow == "Provider Error")
        #expect(presentation.title == "Provider Data Unavailable")
        #expect(presentation.tone == .critical)
    }

    @Test("empty-library message includes the active scope when context exists")
    func emptyLibraryMessageIncludesScopeSummary() {
        let snapshot = makeSnapshot(
            address: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .baseMainnet
        )

        let message = ShellEmptyLibraryStateView.message(for: .token, snapshot: snapshot)

        #expect(message.contains("Token holdings for the active wallet and chain will appear here"))
        #expect(message.contains(snapshot.scopeSummary))
    }

    @Test("no-receipts message stays generic without context and scoped with context")
    func noReceiptsMessageSupportsBothGenericAndScopedStates() {
        let generic = ShellNoReceiptsStateView.message(snapshot: nil)
        let scoped = ShellNoReceiptsStateView.message(
            snapshot: makeSnapshot(
                address: "0x1234567890abcdef1234567890abcdef12345678",
                chain: .ethMainnet
            )
        )

        #expect(generic.contains("there is nothing to inspect or export from this device."))
        #expect(scoped.contains("for 0x1234...5678 • Ethereum."))
    }

    private func makeSnapshot(address: String, chain: Chain) -> ContextSnapshot {
        LiveContextSource(
            accountProvider: { nil },
            addressProvider: { address },
            chainProvider: { chain },
            modeProvider: { .observe },
            loadingProvider: { false },
            refreshedAtProvider: { Date(timeIntervalSince1970: 1_700_000_000) }
        ).snapshot()
    }
}
