@testable import Auralis
import Foundation
import Testing

@Suite
struct ExternalWalletAppProbeTests {
    @MainActor
    @Test("wallet app probe asks UIApplication about the expected deep-link URL")
    func probeUsesExpectedURL() {
        let application = MockApplication(openableSchemes: ["metamask"])
        let probe = ExternalWalletAppProbe(application: application)

        #expect(probe.canOpen(.metaMask))
        #expect(application.queriedURLs == [URL(string: "metamask://")!])
    }

    @MainActor
    @Test("wallet app probe reports unsupported wallets as unavailable")
    func probeReturnsFalseForUnavailableWallet() {
        let application = MockApplication(openableSchemes: [])
        let probe = ExternalWalletAppProbe(application: application)

        #expect(probe.canOpen(.ledgerLive) == false)
        #expect(application.queriedURLs == [URL(string: "ledgerlive://")!])
    }
}

@MainActor
private final class MockApplication: ApplicationURLChecking {
    private let openableSchemes: Set<String>
    private(set) var queriedURLs: [URL] = []

    init(openableSchemes: Set<String>) {
        self.openableSchemes = openableSchemes
    }

    func canOpenURL(_ url: URL) -> Bool {
        queriedURLs.append(url)
        guard let scheme = url.scheme else {
            return false
        }
        return openableSchemes.contains(scheme)
    }
}
