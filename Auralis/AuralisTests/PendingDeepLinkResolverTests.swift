import Testing
@testable import Auralis

@Suite struct PendingDeepLinkResolverTests {
    private let resolver = PendingDeepLinkResolver()

    @Test("account deep link switches accounts before routing nested destinations")
    func accountLinkRequestsAccountSwitch() {
        let resolution = resolver.resolve(
            .account(
                address: "0x1234567890abcdef1234567890abcdef12345678",
                chain: .baseMainnet,
                destination: .nft(id: "nft-1")
            ),
            context: PendingDeepLinkContext(
                currentAddress: "",
                currentAccountAddress: nil,
                canResolveDeferredLink: false,
                shouldFailDeferredLink: false
            )
        )

        #expect(resolution.chainOverride == .baseMainnet)
        #expect(resolution.action == .switchAccount(address: "0x1234567890abcdef1234567890abcdef12345678"))
    }

    @Test("account deep link waits while the new account is still loading")
    func accountLinkWaitsForMatchingAccountState() {
        let resolution = resolver.resolve(
            .account(
                address: "0x1234567890abcdef1234567890abcdef12345678",
                chain: .ethMainnet,
                destination: .nft(id: "nft-1")
            ),
            context: PendingDeepLinkContext(
                currentAddress: "0x1234567890abcdef1234567890abcdef12345678",
                currentAccountAddress: nil,
                canResolveDeferredLink: true,
                shouldFailDeferredLink: false
            )
        )

        #expect(resolution.chainOverride == .ethMainnet)
        #expect(resolution.action == .wait)
    }

    @Test("account deep link can route home without a nested destination")
    func accountLinkRoutesHome() {
        let resolution = resolver.resolve(
            .account(
                address: "0x1234567890abcdef1234567890abcdef12345678",
                chain: .ethMainnet,
                destination: nil
            ),
            context: PendingDeepLinkContext(
                currentAddress: "0x1234567890abcdef1234567890abcdef12345678",
                currentAccountAddress: "0x1234567890abcdef1234567890abcdef12345678",
                canResolveDeferredLink: true,
                shouldFailDeferredLink: false
            )
        )

        #expect(resolution.chainOverride == .ethMainnet)
        #expect(resolution.action == .showHome)
    }

    @Test("top-level token deep link becomes a route when the shell is ready")
    func topLevelTokenLinkRoutesWhenReady() {
        let destination = AppDeepLinkDestination.token(
            contractAddress: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
            chain: .baseMainnet,
            symbol: "USDC"
        )
        let resolution = resolver.resolve(
            .destination(destination),
            context: PendingDeepLinkContext(
                currentAddress: "0x1234567890abcdef1234567890abcdef12345678",
                currentAccountAddress: "0x1234567890abcdef1234567890abcdef12345678",
                canResolveDeferredLink: true,
                shouldFailDeferredLink: false
            )
        )

        #expect(resolution.chainOverride == nil)
        #expect(resolution.action == .route(destination: destination, inheritedChain: nil))
    }

    @Test("cold-start top-level destinations wait instead of failing before restore completes")
    func topLevelDestinationWaitsBeforeInitialRestoreCompletes() {
        let resolution = resolver.resolve(
            .destination(.nft(id: "nft-1")),
            context: PendingDeepLinkContext(
                currentAddress: "",
                currentAccountAddress: nil,
                canResolveDeferredLink: false,
                shouldFailDeferredLink: false
            )
        )

        #expect(resolution.action == .wait)
    }

    @Test("receipt deep links are forwarded as route requests for the shell to handle safely")
    func receiptLinkRoutesForShellHandling() {
        let destination = AppDeepLinkDestination.receipt(id: "0xreceipt123")
        let resolution = resolver.resolve(
            .destination(destination),
            context: PendingDeepLinkContext(
                currentAddress: "0x1234567890abcdef1234567890abcdef12345678",
                currentAccountAddress: "0x1234567890abcdef1234567890abcdef12345678",
                canResolveDeferredLink: true,
                shouldFailDeferredLink: false
            )
        )

        #expect(resolution.action == .route(destination: destination, inheritedChain: nil))
    }

    @Test("destination deep links fail safely once restore has finished without an account")
    func destinationLinkFailsAfterRestoreWithoutAccount() {
        let resolution = resolver.resolve(
            .destination(.token(
                contractAddress: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
                chain: .baseMainnet,
                symbol: "USDC"
            )),
            context: PendingDeepLinkContext(
                currentAddress: "",
                currentAccountAddress: nil,
                canResolveDeferredLink: false,
                shouldFailDeferredLink: true
            )
        )

        guard case .showError(let error) = resolution.action else {
            Issue.record("Expected a safe route error after restore completed without an account")
            return
        }

        #expect(error.title == "No Active Account")
        #expect(error.message == "Open or restore an account before routing this deep link.")
        #expect(error.urlString == nil)
    }

    @Test("account deep links fail safely once restore has finished without an account")
    func accountLinkFailsAfterRestoreWithoutAccount() {
        let resolution = resolver.resolve(
            .account(
                address: "0x1234567890abcdef1234567890abcdef12345678",
                chain: nil,
                destination: nil
            ),
            context: PendingDeepLinkContext(
                currentAddress: "0x1234567890abcdef1234567890abcdef12345678",
                currentAccountAddress: nil,
                canResolveDeferredLink: false,
                shouldFailDeferredLink: true
            )
        )

        guard case .showError(let error) = resolution.action else {
            Issue.record("Expected a safe route error for an unresolved account deep link")
            return
        }

        #expect(error.title == "No Active Account")
        #expect(error.message == "Open or restore an account before using this account link.")
        #expect(error.urlString == nil)
    }
}
