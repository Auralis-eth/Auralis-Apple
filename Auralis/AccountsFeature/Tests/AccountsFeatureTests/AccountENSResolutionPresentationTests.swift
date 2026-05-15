import AccountsFeature
import Testing

@Suite
struct AccountENSResolutionPresentationTests {
    private let presenter = AccountENSResolutionPresenter()

    @Test("verified ENS resolution exposes the resolved account fields without an alert")
    func verifiedENSResolutionPresentsResolvedFields() {
        let presentation = presenter.presentation(
            for: AccountENSResolution(
                address: "0x1234567890abcdef1234567890abcdef12345678",
                ensName: "vitalik.eth",
                isStale: false
            )
        )

        #expect(presentation.resolvedAddress == "0x1234567890abcdef1234567890abcdef12345678")
        #expect(presentation.resolvedName == "vitalik.eth")
        #expect(presentation.alert == nil)
    }

    @Test("stale ENS resolution blocks save with explicit trust messaging")
    func staleENSResolutionPresentsVerificationWarning() throws {
        let presentation = presenter.presentation(
            for: AccountENSResolution(
                address: "0x1234567890abcdef1234567890abcdef12345678",
                ensName: "vitalik.eth",
                isStale: true
            )
        )
        let alert = try #require(presentation.alert)

        #expect(presentation.resolvedAddress == nil)
        #expect(presentation.resolvedName == nil)
        #expect(alert.title == "ENS Verification Unavailable")
        #expect(alert.message.contains("cached ENS mapping"))
    }

    @Test("ENS failures map to user-facing account entry alerts")
    func ensFailuresPresentUserFacingAlerts() {
        let unavailable = presenter.presentation(for: .unavailable("Provider unavailable"))
        let changed = presenter.presentation(
            for: .mappingChanged(
                ensName: "vitalik.eth",
                cachedAddress: "0x1111111111111111111111111111111111111111",
                resolvedAddress: "0x2222222222222222222222222222222222222222"
            )
        )

        #expect(unavailable.title == "Save Failed")
        #expect(unavailable.message == "Failed to save account: Provider unavailable")
        #expect(changed.title == "ENS Mapping Changed")
        #expect(changed.message.contains("Review the resolved address"))
    }
}
