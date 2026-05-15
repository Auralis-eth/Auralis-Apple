import AuralisPrimaryModels
import MusicFeature
import Testing

@Suite
struct AuraPlayDomainTests {
    @Test("library scope keeps account and chain together")
    func libraryScopeStoresAccountAndChain() {
        let scope = AuraPlayLibraryScope(
            accountAddress: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .ethMainnet
        )

        #expect(scope.accountAddress == "0x1234567890abcdef1234567890abcdef12345678")
        #expect(scope.chain == .ethMainnet)
    }

    @Test("configuration reports missing bundle requirements")
    func configurationReportsMissingRequirements() {
        let configuration = AuraPlayModuleConfiguration(
            backgroundAudioEnabled: false,
            declaredURLSchemes: ["auralis"],
            walletQuerySchemes: ["metamask"]
        )

        #expect(configuration.missingRequirements.contains("Background audio mode is missing."))
        #expect(configuration.missingRequirements.contains("The auraplay URL scheme is missing."))
        #expect(configuration.missingRequirements.contains("Wallet query schemes missing: cbwallet, ledgerlive, rainbow."))
    }

    @Test("artwork loader returns valid track artwork URL")
    @MainActor
    func artworkLoaderReturnsTrackURL() throws {
        let loader = AuraPlayTrackArtworkLoader()
        let track = AuraPlayTrack(
            id: "track-1",
            title: "Foundation",
            artist: "AuraPlay",
            duration: 120,
            imageURLString: "https://example.com/cover.png"
        )

        #expect(try loader.artworkURL(for: track)?.absoluteString == "https://example.com/cover.png")
    }
}
