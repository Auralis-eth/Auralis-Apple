@testable import Auralis
import Foundation
import Testing

struct ExternalWalletAppProbeTests {
    @MainActor
    @Test("wallet app probe asks UIApplication about the expected deep-link URL")
    func probeUsesExpectedURL() throws {
        let application = MockApplication(openableSchemes: ["metamask"])
        let probe = ExternalWalletAppProbe(application: application)

        let expectedMetaMaskURL = try #require(URL(string: "metamask://"))
        #expect(probe.canOpen(.metaMask))
        #expect(application.queriedURLs == [expectedMetaMaskURL])
    }

    @MainActor
    @Test("wallet app probe reports unsupported wallets as unavailable")
    func probeReturnsFalseForUnavailableWallet() throws {
        let application = MockApplication(openableSchemes: [])
        let probe = ExternalWalletAppProbe(application: application)

        let expectedLedgerURL = try #require(URL(string: "ledgerlive://"))
        #expect(probe.canOpen(.ledgerLive) == false)
        #expect(application.queriedURLs == [expectedLedgerURL])
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
