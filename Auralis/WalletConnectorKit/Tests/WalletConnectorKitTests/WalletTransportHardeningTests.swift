import CryptoKit
import Foundation
import Testing
@testable import WalletConnectorKit

/// Hardening coverage for the custom WalletConnect v2 transport: inbound message
/// dedup (relay redelivery), settle-expiry validation, and JSON-RPC id
/// uniqueness. Drives the handshake against a scriptable mock relay/wallet.
@Suite("WalletConnect transport hardening")
struct WalletTransportHardeningTests {
    static let walletAddress = "0xAbc0000000000000000000000000000000000001"
    static let account = "eip155:1:\(walletAddress)"

    // MARK: - #3 inbound message dedup

    @Test("A redelivered settle produces only one sessionApproved event")
    func redeliveredSettleIsDeduplicated() async throws {
        let wallet = ScriptableWalletRelay(account: Self.account, redeliverSettle: true)
        let transport = try await Self.makeTransport(wallet: wallet)

        let collector = ApprovalCollector()
        let events = transport.events()
        Task { for await event in events { await collector.add(event) } }

        try await Self.startHandshake(transport: transport, wallet: wallet)

        _ = await collector.waitForApproval()
        // Give the redelivered settle time to be received and dropped.
        try await Task.sleep(for: .milliseconds(200))
        #expect(await collector.approvalCount() == 1)
        #expect(try await transport.sessions().count == 1)
    }

    // MARK: - #4 settle expiry validation

    @Test("A settle with a past expiry is not stored and yields no approval")
    func expiredSettleIsRejected() async throws {
        let wallet = ScriptableWalletRelay(
            account: Self.account,
            settleExpiry: Date().addingTimeInterval(-60)
        )
        let transport = try await Self.makeTransport(wallet: wallet)

        let collector = ApprovalCollector()
        let events = transport.events()
        Task { for await event in events { await collector.add(event) } }

        try await Self.startHandshake(transport: transport, wallet: wallet)

        // Wait long enough for the settle to have arrived and been evaluated.
        try await Task.sleep(for: .milliseconds(300))
        #expect(await collector.approvalCount() == 0)
        #expect(try await transport.sessions().isEmpty)
    }

    @Test("A settle expiry beyond the 7-day cap is clamped")
    func farFutureSettleExpiryIsClamped() async throws {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let clock = ClockBox(base)
        // Wallet asks for a 100-day session; the transport must clamp to 7 days.
        let wallet = ScriptableWalletRelay(account: Self.account, settleExpiry: base.addingTimeInterval(100 * 86_400))
        let transport = try await Self.makeTransport(wallet: wallet, now: { clock.now })

        let collector = ApprovalCollector()
        let events = transport.events()
        Task { for await event in events { await collector.add(event) } }

        try await Self.startHandshake(transport: transport, wallet: wallet)
        let session = await collector.waitForApproval()

        #expect(session.expiryDate == base.addingTimeInterval(604_800))
    }

    // MARK: - Settled-namespace scoping

    @Test("A settle granting an unproposed chain drops that account")
    func settleScopesAccountsToProposedChains() async throws {
        // Wallet settles an extra Solana account, but we propose only Ethereum.
        let solanaAccount = "solana:5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp:11111111111111111111111111111111"
        let wallet = ScriptableWalletRelay(account: Self.account, extraAccounts: [solanaAccount])
        let transport = try await Self.makeTransport(wallet: wallet)

        let collector = ApprovalCollector()
        let events = transport.events()
        Task { for await event in events { await collector.add(event) } }

        let ethOnly = WalletNamespaceProposalSet(proposals: [
            "eip155": WalletNamespaceProposal(
                chains: [WalletBlockchain(namespace: "eip155", reference: "1")],
                methods: ["personal_sign"],
                events: ["chainChanged"]
            ),
        ])
        let pairing = try await transport.createPairing(
            request: WalletPairingRequest(
                providerID: "mock",
                supportedChains: [.ethereum],
                metadata: WalletConnectionMetadata(
                    appName: "AuraPlay",
                    appDescription: "test",
                    appURL: URL(string: "https://auraplay.app")!
                ),
                requiredNamespaces: .empty,
                optionalNamespaces: ethOnly
            )
        )
        let uri = try #require(pairing.uri.flatMap(WalletConnectURI.init(absoluteString:)))
        let symKey = try #require(WalletConnectV2Crypto.data(hexEncoded: uri.symKey))
        await wallet.setPairing(topic: uri.topic, symKey: symKey)

        let session = await collector.waitForApproval()
        // The proposed Ethereum account survives; the unproposed Solana account is dropped.
        #expect(session.accounts.contains(WalletAccount(caip10: Self.account)))
        #expect(!session.accounts.contains(WalletAccount(caip10: solanaAccount)))
    }

    // MARK: - Settled-session grant enforcement

    @Test("A session update with no approved accounts deletes the session")
    func emptyAccountSessionUpdateDeletesSession() async throws {
        let wallet = ScriptableWalletRelay(account: Self.account)
        let transport = try await Self.makeTransport(wallet: wallet)
        let collector = ApprovalCollector()
        let events = transport.events()
        Task { for await event in events { await collector.add(event) } }

        try await Self.startHandshake(transport: transport, wallet: wallet)
        let session = await collector.waitForApproval()
        await wallet.sendSessionUpdate(accounts: [])
        let deleted = await collector.waitForDeletion()

        #expect(deleted == session.id)
        #expect(try await transport.sessions().isEmpty)
    }

    @Test("A settle missing a required namespace method is rejected")
    func settleMissingRequiredMethodIsRejected() async throws {
        let wallet = ScriptableWalletRelay(account: Self.account)
        let transport = try await Self.makeTransport(wallet: wallet)
        let collector = ApprovalCollector()
        let events = transport.events()
        Task { for await event in events { await collector.add(event) } }

        let required = WalletNamespaceProposalSet(proposals: [
            "eip155": WalletNamespaceProposal(
                chains: [WalletBlockchain(namespace: "eip155", reference: "1")],
                methods: ["personal_sign", "eth_sendTransaction"],
                events: ["chainChanged"]
            ),
        ])
        let pairing = try await transport.createPairing(
            request: WalletPairingRequest(
                providerID: "mock",
                supportedChains: [.ethereum],
                metadata: WalletConnectionMetadata(
                    appName: "AuraPlay",
                    appDescription: "test",
                    appURL: URL(string: "https://auraplay.app")!
                ),
                requiredNamespaces: required,
                optionalNamespaces: .empty
            )
        )
        let uri = try #require(pairing.uri.flatMap(WalletConnectURI.init(absoluteString:)))
        let symKey = try #require(WalletConnectV2Crypto.data(hexEncoded: uri.symKey))
        await wallet.setPairing(topic: uri.topic, symKey: symKey)

        try await Task.sleep(for: .milliseconds(300))
        #expect(await collector.approvalCount() == 0)
        #expect(await collector.rejectionCount() == 1)
        #expect(try await transport.sessions().isEmpty)
    }

    @Test("A session update missing a required method deletes the session")
    func updateMissingRequiredMethodDeletesSession() async throws {
        let wallet = ScriptableWalletRelay(account: Self.account)
        let transport = try await Self.makeTransport(wallet: wallet)
        let collector = ApprovalCollector()
        let events = transport.events()
        Task { for await event in events { await collector.add(event) } }

        let required = WalletNamespaceProposalSet(proposals: [
            "eip155": WalletNamespaceProposal(
                chains: [WalletBlockchain(namespace: "eip155", reference: "1")],
                methods: ["personal_sign"],
                events: ["chainChanged"]
            ),
        ])
        let pairing = try await transport.createPairing(
            request: WalletPairingRequest(
                providerID: "mock",
                supportedChains: [.ethereum],
                metadata: WalletConnectionMetadata(
                    appName: "AuraPlay",
                    appDescription: "test",
                    appURL: URL(string: "https://auraplay.app")!
                ),
                requiredNamespaces: required,
                optionalNamespaces: .empty
            )
        )
        let uri = try #require(pairing.uri.flatMap(WalletConnectURI.init(absoluteString:)))
        let symKey = try #require(WalletConnectV2Crypto.data(hexEncoded: uri.symKey))
        await wallet.setPairing(topic: uri.topic, symKey: symKey)
        let session = await collector.waitForApproval()

        await wallet.sendSessionUpdate(accounts: [Self.account], methods: [], events: ["chainChanged"])
        let deleted = await collector.waitForDeletion()

        #expect(deleted == session.id)
        #expect(try await transport.sessions().isEmpty)
    }

    @Test("Session request relay TTL follows the request expiry")
    func sessionRequestRelayTTLUsesRequestExpiry() async throws {
        let wallet = ScriptableWalletRelay(account: Self.account)
        let transport = try await Self.makeTransport(wallet: wallet)
        let collector = ApprovalCollector()
        let events = transport.events()
        Task { for await event in events { await collector.add(event) } }

        try await Self.startHandshake(transport: transport, wallet: wallet)
        let session = await collector.waitForApproval()
        let request = WalletRequestBuilder.personalSignText(
            id: WalletSignRequestID(rawValue: "ttl-request"),
            address: Self.walletAddress,
            text: "hello",
            expiryDate: Date().addingTimeInterval(900)
        )
        let response = try await transport.request(request, topic: session.topic)
        let ttl = try #require(await wallet.latestTTL(for: WalletConnectSignTag.sessionRequest))

        #expect(response.id == "ttl-request")
        #expect((895...905).contains(ttl))
    }

    @Test("A request with invalid expiry is rejected before publish")
    func requestRejectsInvalidExpiryBeforePublish() async throws {
        let (transport, session) = try await Self.settledTransportAndSession()
        let request = WalletRequestBuilder.personalSignText(
            id: WalletSignRequestID(rawValue: "too-short-expiry"),
            address: Self.walletAddress,
            text: "hello",
            expiryDate: Date().addingTimeInterval(60)
        )

        await #expect(throws: WalletConnectionError.requestTimedOut("too-short-expiry")) {
            _ = try await transport.request(request, topic: session.topic)
        }
    }

    @Test("A request using an ungranted method is rejected before publish")
    func requestRejectsUngrantedMethod() async throws {
        let (transport, session) = try await Self.settledTransportAndSession()
        let request = WalletRequestBuilder.sendTransaction(
            id: WalletSignRequestID(rawValue: "ungranted-method"),
            transaction: WalletTransactionRequest(
                from: Self.walletAddress,
                to: "0xDef0000000000000000000000000000000000002",
                value: "0x0",
                data: "0x",
                chainId: "0x1"
            ),
            expiryDate: Date().addingTimeInterval(300)
        )

        await #expect(throws: WalletConnectionError.self) {
            _ = try await transport.request(request, topic: session.topic)
        }
    }

    @Test("A request using an ungranted chain is rejected before publish")
    func requestRejectsUngrantedChain() async throws {
        let (transport, session) = try await Self.settledTransportAndSession()
        let request = WalletRequestBuilder.personalSignText(
            id: WalletSignRequestID(rawValue: "ungranted-chain"),
            address: Self.walletAddress,
            text: "hello",
            chain: .polygon,
            expiryDate: Date().addingTimeInterval(300)
        )

        await #expect(throws: WalletConnectionError.self) {
            _ = try await transport.request(request, topic: session.topic)
        }
    }

    @Test("A chain switch to an ungranted target chain is rejected before publish")
    func requestRejectsUngrantedSwitchTargetChain() async throws {
        let wallet = ScriptableWalletRelay(
            account: Self.account,
            settleMethods: [WalletRequestMethod.ethPersonalSign.rawValue, WalletRequestMethod.walletSwitchEthereumChain.rawValue]
        )
        let transport = try await Self.makeTransport(wallet: wallet)
        let collector = ApprovalCollector()
        let events = transport.events()
        Task { for await event in events { await collector.add(event) } }

        try await Self.startHandshake(transport: transport, wallet: wallet)
        let session = await collector.waitForApproval()
        let request = WalletRequestBuilder.switchEthereumChain(
            id: WalletSignRequestID(rawValue: "ungranted-switch-target"),
            chainId: "0x89",
            chain: .ethereum,
            expiryDate: Date().addingTimeInterval(300)
        )

        await #expect(throws: WalletConnectionError.self) {
            _ = try await transport.request(request, topic: session.topic)
        }
    }

    @Test("A request using an ungranted signer account is rejected before publish")
    func requestRejectsUngrantedSignerAccount() async throws {
        let (transport, session) = try await Self.settledTransportAndSession()
        let request = WalletRequestBuilder.personalSignText(
            id: WalletSignRequestID(rawValue: "ungranted-account"),
            address: "0xDef0000000000000000000000000000000000002",
            text: "hello",
            expiryDate: Date().addingTimeInterval(300)
        )

        await #expect(throws: WalletConnectionError.self) {
            _ = try await transport.request(request, topic: session.topic)
        }
    }

    // MARK: - Relay TLS enforcement

    @Test("A non-wss relay URL is rejected at connect")
    func insecureRelayURLIsRejected() async throws {
        let config = WalletConnectRelayConfiguration(
            projectID: "p",
            relayURL: try #require(URL(string: "ws://relay.example"))
        )
        #expect(config.isSecure == false)
        #expect(config.isUsable == false)

        let relay = WalletConnectIRNRelayClient(
            configuration: config,
            taskFactory: MockTaskFactory(task: ScriptableWalletRelay(account: Self.account)),
            authProvider: nil
        )
        await #expect(throws: WalletConnectRelayConfigurationError.insecureRelayURL) {
            try await relay.connect()
        }
    }

    // MARK: - Peer ACK diagnostics

    @Test("Peer ACK publish failures surface diagnostics without rolling back state")
    func peerAcknowledgementFailureSurfacesDiagnostic() async throws {
        let wallet = ScriptableWalletRelay(
            account: Self.account,
            rejectedPublishTags: [WalletConnectSignTag.sessionSettleResponse]
        )
        let transport = try await Self.makeTransport(wallet: wallet)
        let collector = ApprovalCollector()
        let events = transport.events()
        Task { for await event in events { await collector.add(event) } }

        try await Self.startHandshake(transport: transport, wallet: wallet)
        let session = await collector.waitForApproval()
        let failure = await collector.waitForAcknowledgementFailure()

        #expect(failure.topic == session.topic)
        #expect(failure.tag == WalletConnectSignTag.sessionSettleResponse)
        #expect(failure.error == .relayAcknowledgementFailed("rejected"))
        #expect(try await transport.sessions().contains { $0.topic == session.topic })
    }

    // MARK: - Ownership verification tracking

    @Test("markOwnershipVerified propagates persistence failure")
    func markOwnershipVerifiedPropagatesPersistenceFailure() async throws {
        let store = FailingAfterFirstSaveStateStore()
        let wallet = ScriptableWalletRelay(account: Self.account)
        let transport = try await Self.makeTransport(wallet: wallet, stateStore: store)
        let collector = ApprovalCollector()
        let events = transport.events()
        Task { for await event in events { await collector.add(event) } }

        try await Self.startHandshake(transport: transport, wallet: wallet)
        let settled = await collector.waitForApproval()

        await store.failFutureSaves()
        await #expect(throws: WalletConnectionError.internalFailure("save failed")) {
            try await transport.markOwnershipVerified(topic: settled.topic)
        }
        let restored = try #require(try await transport.sessions().first)
        #expect(restored.addressVerified == false)
    }

    @Test("disconnect surfaces a persisted delete failure but still tears down locally")
    func disconnectSurfacesPersistedDeleteFailureButTearsDown() async throws {
        let store = FailingAfterFirstSaveStateStore()
        let wallet = ScriptableWalletRelay(account: Self.account)
        let transport = try await Self.makeTransport(wallet: wallet, stateStore: store)
        let collector = ApprovalCollector()
        let events = transport.events()
        Task { for await event in events { await collector.add(event) } }

        try await Self.startHandshake(transport: transport, wallet: wallet)
        let settled = await collector.waitForApproval()
        await store.failFutureDeletes()

        // A persistence-delete failure must not block the user's disconnect: it is
        // surfaced as an event (not thrown), and local state is torn down so it
        // cannot diverge from the user's intent.
        try await transport.disconnect(topic: settled.topic)
        #expect(try await transport.sessions().contains { $0.topic == settled.topic } == false)

        // The remote `wc_sessionDelete` is best-effort and fired off the caller's
        // path (so a dead relay cannot stall disconnect), so poll for it.
        var published = false
        for _ in 0..<50 where !published {
            if await wallet.publishedCount(for: WalletConnectSignTag.sessionDelete) == 1 {
                published = true
            } else {
                try await Task.sleep(for: .milliseconds(20))
            }
        }
        #expect(published)
    }

    @Test("A settled session is unverified until markOwnershipVerified flips it")
    func ownershipVerificationFlagIsTracked() async throws {
        let wallet = ScriptableWalletRelay(account: Self.account)
        let transport = try await Self.makeTransport(wallet: wallet)

        let collector = ApprovalCollector()
        let events = transport.events()
        Task { for await event in events { await collector.add(event) } }

        try await Self.startHandshake(transport: transport, wallet: wallet)
        _ = await collector.waitForApproval()

        let settled = try #require(try await transport.sessions().first)
        #expect(settled.addressVerified == false)

        try await transport.markOwnershipVerified(topic: settled.topic)
        let verified = try #require(try await transport.sessions().first)
        #expect(verified.addressVerified == true)
    }

    // MARK: - Envelope-type / topic-phase validation

    @Test("A settle forged on the pairing topic is rejected")
    func settleOnPairingTopicIsRejected() async throws {
        let wallet = ScriptableWalletRelay(account: Self.account, settleOnPairingTopic: true)
        let transport = try await Self.makeTransport(wallet: wallet)

        let collector = ApprovalCollector()
        let events = transport.events()
        Task { for await event in events { await collector.add(event) } }

        try await Self.startHandshake(transport: transport, wallet: wallet)

        // Allow the forged settle to arrive and be evaluated.
        try await Task.sleep(for: .milliseconds(300))
        #expect(await collector.approvalCount() == 0)
        #expect(try await transport.sessions().isEmpty)
    }

    // MARK: - Expired live-session pruning

    @Test("A session past its expiry is pruned from sessions() and rejected by request()")
    func expiredLiveSessionIsPruned() async throws {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let clock = ClockBox(base)
        let wallet = ScriptableWalletRelay(account: Self.account, settleExpiry: base.addingTimeInterval(50))
        let transport = try await Self.makeTransport(wallet: wallet, now: { clock.now })

        let collector = ApprovalCollector()
        let events = transport.events()
        Task { for await event in events { await collector.add(event) } }

        try await Self.startHandshake(transport: transport, wallet: wallet)
        _ = await collector.waitForApproval()

        let live = try await transport.sessions()
        #expect(live.count == 1)
        let sessionTopic = try #require(live.first).topic

        // Advance past the session's expiry; it is only pruned lazily on use.
        clock.now = base.addingTimeInterval(100)
        #expect(try await transport.sessions().isEmpty)
        await #expect(throws: WalletConnectionError.self) {
            _ = try await transport.request(
                WalletRequestBuilder.personalSignText(
                    id: WalletSignRequestID(rawValue: "expired"),
                    address: Self.walletAddress,
                    text: "hi",
                    chain: .ethereum,
                    expiryDate: base.addingTimeInterval(200)
                ),
                topic: sessionTopic
            )
        }
    }

    // MARK: - #5 nextID uniqueness

    @Test("Relay client request ids use WalletConnect 19-digit shape")
    func relayRequestIDsUseWalletConnectShape() async throws {
        let relay = WalletConnectIRNRelayClient(
            configuration: WalletConnectRelayConfiguration(projectID: "test-project"),
            taskFactory: MockTaskFactory(task: ScriptableWalletRelay(account: Self.account)),
            authProvider: nil
        )

        var ids = Set<Int64>()
        for _ in 0..<5000 {
            let id = await relay.nextRequestID()
            ids.insert(id)
            #expect(String(id).count == 19)
            #expect(id > 0)
        }
        #expect(ids.count == 5000)
    }

    @Test("Generating >1000 ids at a fixed timestamp yields all-distinct values")
    func nextIDsAreDistinctWithinSameMillisecond() async throws {
        let fixed = Date(timeIntervalSince1970: 1_800_000_000)
        let relay = WalletConnectIRNRelayClient(
            configuration: WalletConnectRelayConfiguration(projectID: "test-project"),
            taskFactory: MockTaskFactory(task: ScriptableWalletRelay(account: Self.account)),
            authProvider: nil
        )
        let transport = WalletConnectIRNTransportClient(relayClient: relay, stateStore: InMemoryWalletConnectSessionStateStore(), now: { fixed })

        var ids = Set<Int64>()
        for _ in 0..<5000 {
            let id = await transport.nextID()
            ids.insert(id)
            #expect(id > 0)
        }
        #expect(ids.count == 5000)
    }

    // Regression (AUD-036): wallet-facing Sign RPC ids must stay under JavaScript's
    // `Number.MAX_SAFE_INTEGER` (2^53). A JS/React-Native wallet stores JSON numbers
    // as IEEE-754 doubles; an id above 2^53 is rounded and the wallet echoes a
    // different id, so `handleRequestResponse`'s topic/id binding never matches and
    // every signing request hangs to expiry. `nextID` must mirror reown's Sign tier
    // (`ms * 1_000`), NOT the relay tier (`ms * 1_000_000`).
    @Test("Wallet-facing nextID stays under JS 2^53 safe-integer ceiling")
    func nextIDStaysUnderJavaScriptSafeInteger() async throws {
        let maxSafeInteger: Int64 = 9_007_199_254_740_992 // 2^53
        // A far-future clock (year ~2065) still must not breach the ceiling.
        let fixed = Date(timeIntervalSince1970: 3_000_000_000)
        let relay = WalletConnectIRNRelayClient(
            configuration: WalletConnectRelayConfiguration(projectID: "test-project"),
            taskFactory: MockTaskFactory(task: ScriptableWalletRelay(account: Self.account)),
            authProvider: nil
        )
        let transport = WalletConnectIRNTransportClient(relayClient: relay, stateStore: InMemoryWalletConnectSessionStateStore(), now: { fixed })

        for _ in 0..<5000 {
            let id = await transport.nextID()
            #expect(id > 0)
            #expect(id < maxSafeInteger)
        }
    }

    // MARK: - Helpers

    private static func makeTransport(
        wallet: ScriptableWalletRelay,
        stateStore: any WalletConnectSessionStatePersisting = InMemoryWalletConnectSessionStateStore(),
        now: @escaping @Sendable () -> Date = Date.init
    ) async throws -> WalletConnectIRNTransportClient {
        let relay = WalletConnectIRNRelayClient(
            configuration: WalletConnectRelayConfiguration(projectID: "test-project"),
            taskFactory: MockTaskFactory(task: wallet),
            authProvider: nil
        )
        return WalletConnectIRNTransportClient(relayClient: relay, stateStore: stateStore, now: now)
    }

    private static func settledTransportAndSession() async throws -> (WalletConnectIRNTransportClient, WalletSession) {
        let wallet = ScriptableWalletRelay(account: Self.account)
        let transport = try await Self.makeTransport(wallet: wallet)
        let collector = ApprovalCollector()
        let events = transport.events()
        Task { for await event in events { await collector.add(event) } }

        try await Self.startHandshake(transport: transport, wallet: wallet)
        let session = await collector.waitForApproval()
        return (transport, session)
    }

    private static func startHandshake(transport: WalletConnectIRNTransportClient, wallet: ScriptableWalletRelay) async throws {
        let pairing = try await transport.createPairing(
            request: WalletPairingRequest(
                providerID: "mock",
                supportedChains: [.ethereum],
                metadata: WalletConnectionMetadata(
                    appName: "AuraPlay",
                    appDescription: "test",
                    appURL: URL(string: "https://auraplay.app")!
                )
            )
        )
        let uri = try #require(pairing.uri.flatMap(WalletConnectURI.init(absoluteString:)))
        let symKey = try #require(WalletConnectV2Crypto.data(hexEncoded: uri.symKey))
        await wallet.setPairing(topic: uri.topic, symKey: symKey)
    }
}

private actor FailingAfterFirstSaveStateStore: WalletConnectSessionStatePersisting {
    private var sessions: [WalletConnectPersistedSession] = []
    private var shouldFailSaves = false
    private var shouldFailDeletes = false

    func failFutureSaves() {
        shouldFailSaves = true
    }

    func failFutureDeletes() {
        shouldFailDeletes = true
    }

    func save(_ session: WalletConnectPersistedSession) throws {
        if shouldFailSaves {
            throw WalletConnectionError.internalFailure("save failed")
        }
        sessions.removeAll { $0.sessionTopic == session.sessionTopic }
        sessions.append(session)
    }

    func loadAll() throws -> [WalletConnectPersistedSession] {
        sessions
    }

    func delete(sessionTopic: String) throws {
        if shouldFailDeletes {
            throw WalletConnectionError.internalFailure("delete failed")
        }
        sessions.removeAll { $0.sessionTopic == sessionTopic }
    }
}

private actor ApprovalCollector {
    private var approvals: [WalletSession] = []
    private var rejections: [WalletConnectionError] = []
    private var acknowledgementFailures: [WalletPeerAcknowledgementFailure] = []
    private var waiter: CheckedContinuation<WalletSession, Never>?

    func add(_ event: WalletTransportEvent) {
        switch event {
        case .sessionApproved(let session):
            approvals.append(session)
            waiter?.resume(returning: session)
            waiter = nil
        case .sessionRejected(_, let error):
            rejections.append(error)
        case .sessionDeleted(let sessionID):
            deletions.append(sessionID)
            deletionWaiter?.resume(returning: sessionID)
            deletionWaiter = nil
        case .peerAcknowledgementFailed(let failure):
            acknowledgementFailures.append(failure)
            acknowledgementFailureWaiter?.resume(returning: failure)
            acknowledgementFailureWaiter = nil
        default:
            break
        }
    }

    func waitForApproval() async -> WalletSession {
        if let first = approvals.first { return first }
        return await withCheckedContinuation { waiter = $0 }
    }

    private var deletions: [WalletSessionID] = []
    private var deletionWaiter: CheckedContinuation<WalletSessionID, Never>?

    func waitForDeletion() async -> WalletSessionID {
        if let first = deletions.first { return first }
        return await withCheckedContinuation { deletionWaiter = $0 }
    }

    private var acknowledgementFailureWaiter: CheckedContinuation<WalletPeerAcknowledgementFailure, Never>?

    func waitForAcknowledgementFailure() async -> WalletPeerAcknowledgementFailure {
        if let first = acknowledgementFailures.first { return first }
        return await withCheckedContinuation { acknowledgementFailureWaiter = $0 }
    }

    func approvalCount() -> Int { approvals.count }
    func rejectionCount() -> Int { rejections.count }
}

/// A thread-safe mutable clock for driving the injectable `now` closure across
/// the transport's actor and the test.
private final class ClockBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Date
    init(_ now: Date) { _now = now }
    var now: Date {
        get { lock.lock(); defer { lock.unlock() }; return _now }
        set { lock.lock(); defer { lock.unlock() }; _now = newValue }
    }
}

private struct MockTaskFactory: WalletConnectRelayTaskFactory {
    let task: ScriptableWalletRelay
    func makeTask(url: URL) async throws -> any WalletConnectRelayTask { task }
}

/// Single-socket mock behaving as both relay and wallet, with knobs for the
/// settle expiry and for redelivering the settle message.
private actor ScriptableWalletRelay: WalletConnectRelayTask {
    private let account: String
    private let extraAccounts: [String]
    private let settleExpiry: Date
    private let settleMethods: [String]
    private let settleEvents: [String]
    private let redeliverSettle: Bool
    private let settleOnPairingTopic: Bool
    private let rejectedPublishTags: Set<Int>
    private let walletKey = WalletConnectV2Crypto.generateKeyPair()

    private var outbox: [String] = []
    private var waiters: [CheckedContinuation<String, Error>] = []

    private var pairingTopic: String?
    private var pairingSymKey: Data?
    private var bufferedPropose: String?
    private var sessionSymKey: Data?
    private var sessionTopic: String?
    private var pendingSettle: (topic: String, message: String)?
    private var publishedTTLsByTag: [Int: [Int]] = [:]
    private var publishedCountsByTag: [Int: Int] = [:]

    init(
        account: String,
        extraAccounts: [String] = [],
        settleExpiry: Date = Date().addingTimeInterval(3600),
        settleMethods: [String] = ["personal_sign"],
        settleEvents: [String] = ["chainChanged"],
        redeliverSettle: Bool = false,
        settleOnPairingTopic: Bool = false,
        rejectedPublishTags: Set<Int> = []
    ) {
        self.account = account
        self.extraAccounts = extraAccounts
        self.settleExpiry = settleExpiry
        self.settleMethods = settleMethods
        self.settleEvents = settleEvents
        self.redeliverSettle = redeliverSettle
        self.settleOnPairingTopic = settleOnPairingTopic
        self.rejectedPublishTags = rejectedPublishTags
    }

    func setPairing(topic: String, symKey: Data) {
        pairingTopic = topic
        pairingSymKey = symKey
        if let message = bufferedPropose {
            bufferedPropose = nil
            processPropose(message)
        }
    }

    func sendSessionUpdate(accounts: [String], methods: [String] = ["personal_sign"], events: [String] = ["chainChanged"]) {
        guard let sessionTopic, let sessionSymKey else { return }
        let update: [String: Any] = [
            "id": Int(Date().timeIntervalSince1970 * 1000),
            "jsonrpc": "2.0",
            "method": "wc_sessionUpdate",
            "params": [
                "namespaces": ["eip155": ["accounts": accounts, "methods": methods, "events": events]],
            ],
        ]
        if let push = encryptedPush(json: update, topic: sessionTopic, tag: WalletConnectSignTag.sessionUpdate, symKey: sessionSymKey) {
            enqueue(push)
        }
    }

    func latestTTL(for tag: Int) -> Int? {
        publishedTTLsByTag[tag]?.last
    }

    func publishedCount(for tag: Int) -> Int {
        publishedCountsByTag[tag] ?? 0
    }

    // MARK: WalletConnectRelayTask

    func send(_ string: String) async throws {
        guard let data = string.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        guard let method = json["method"] as? String else { return }
        let id = json["id"] as? Int ?? 0
        let params = json["params"] as? [String: Any] ?? [:]

        switch method {
        case "irn_subscribe":
            enqueueAck(id: id, result: "subscription-\(params["topic"] as? String ?? "unknown")")
            if let topic = params["topic"] as? String, topic == sessionTopic, let settle = pendingSettle {
                pendingSettle = nil
                enqueue(settle.message)
                if redeliverSettle {
                    // Simulate relay redelivery of the identical encrypted settle.
                    enqueue(settle.message)
                }
            }
        case "irn_publish":
            if let tag = params["tag"] as? Int, rejectedPublishTags.contains(tag) {
                enqueueAckError(id: id, message: "rejected")
                return
            }
            enqueueAck(id: id)
            handlePublished(params: params)
        case "irn_fetchMessages":
            enqueueAck(id: id, result: ["messages": [], "hasMore": false])
        default:
            enqueueAck(id: id)
        }
    }

    func receive() async throws -> String {
        if !outbox.isEmpty { return outbox.removeFirst() }
        return try await withCheckedThrowingContinuation { waiters.append($0) }
    }

    func close() async {}

    // MARK: Wallet behaviour

    private func handlePublished(params: [String: Any]) {
        guard let message = params["message"] as? String, let tag = params["tag"] as? Int else { return }
        publishedCountsByTag[tag, default: 0] += 1
        if let ttl = params["ttl"] as? Int {
            publishedTTLsByTag[tag, default: []].append(ttl)
        }
        switch tag {
        case WalletConnectSignTag.sessionPropose:
            if pairingSymKey == nil {
                bufferedPropose = message
            } else {
                processPropose(message)
            }
        case WalletConnectSignTag.sessionRequest:
            processRequest(message)
        default:
            break
        }
    }

    private func processPropose(_ message: String) {
        guard let pairingSymKey, let pairingTopic,
              let envelope = try? WalletConnectEnvelope(base64Encoded: message),
              let plaintext = try? WalletConnectV2Crypto.open(sealbox: envelope.sealbox, symKey: pairingSymKey),
              let rpc = try? JSONSerialization.jsonObject(with: plaintext) as? [String: Any],
              let proposeID = rpc["id"] as? Int,
              let params = rpc["params"] as? [String: Any],
              let proposer = params["proposer"] as? [String: Any],
              let proposerPub = proposer["publicKey"] as? String,
              let sessionSymKey = try? WalletConnectV2Crypto.deriveSymmetricKey(
                  privateKey: walletKey.privateKey, peerPublicKeyHex: proposerPub
              ) else { return }

        self.sessionSymKey = sessionSymKey
        let sessionTopic = WalletConnectV2Crypto.topic(forSymmetricKey: sessionSymKey)
        self.sessionTopic = sessionTopic

        let response: [String: Any] = [
            "id": proposeID,
            "jsonrpc": "2.0",
            "result": ["relay": ["protocol": "irn"], "responderPublicKey": walletKey.publicKeyHex],
        ]
        if let push = encryptedPush(json: response, topic: pairingTopic, tag: WalletConnectSignTag.sessionProposeResponseApprove, symKey: pairingSymKey) {
            enqueue(push)
        }

        let settle: [String: Any] = [
            "id": Int(Date().timeIntervalSince1970 * 1000),
            "jsonrpc": "2.0",
            "method": "wc_sessionSettle",
            "params": [
                "relay": ["protocol": "irn"],
                "controller": ["publicKey": walletKey.publicKeyHex, "metadata": ["name": "MockWallet", "description": "m", "url": "https://mock", "icons": []]],
                "namespaces": ["eip155": ["accounts": [account] + extraAccounts, "methods": settleMethods, "events": settleEvents]],
                "expiry": Int(settleExpiry.timeIntervalSince1970),
            ],
        ]
        if settleOnPairingTopic {
            // Forge a settle on the pairing topic — whose topic and symKey are both
            // in the URI in cleartext. A compliant dapp binds settle to the derived
            // session topic and must reject this.
            if let push = encryptedPush(json: settle, topic: pairingTopic, tag: WalletConnectSignTag.sessionSettle, symKey: pairingSymKey) {
                enqueue(push)
            }
        } else if let push = encryptedPush(json: settle, topic: sessionTopic, tag: WalletConnectSignTag.sessionSettle, symKey: sessionSymKey) {
            pendingSettle = (sessionTopic, push)
        }
    }

    private func processRequest(_ message: String) {
        guard let sessionSymKey, let sessionTopic,
              let envelope = try? WalletConnectEnvelope(base64Encoded: message),
              let plaintext = try? WalletConnectV2Crypto.open(sealbox: envelope.sealbox, symKey: sessionSymKey),
              let rpc = try? JSONSerialization.jsonObject(with: plaintext) as? [String: Any],
              let requestID = rpc["id"] as? Int else { return }

        let response: [String: Any] = ["id": requestID, "jsonrpc": "2.0", "result": "0xsignature"]
        if let push = encryptedPush(json: response, topic: sessionTopic, tag: WalletConnectSignTag.sessionRequestResponse, symKey: sessionSymKey) {
            enqueue(push)
        }
    }

    // MARK: Framing

    private func encryptedPush(json: [String: Any], topic: String, tag: Int, symKey: Data) -> String? {
        guard let plaintext = try? JSONSerialization.data(withJSONObject: json),
              let sealbox = try? WalletConnectV2Crypto.seal(plaintext: plaintext, symKey: symKey) else { return nil }
        let message = WalletConnectEnvelope(type: .type0, sealbox: sealbox).base64EncodedString()
        let push: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "irn_subscription",
            "params": ["data": ["topic": topic, "message": message, "tag": tag]],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: push) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func enqueueAck(id: Int, result: Any = true) {
        let ack: [String: Any] = ["id": id, "jsonrpc": "2.0", "result": result]
        if let data = try? JSONSerialization.data(withJSONObject: ack), let string = String(data: data, encoding: .utf8) {
            enqueue(string)
        }
    }

    private func enqueueAckError(id: Int, message: String) {
        let ack: [String: Any] = ["id": id, "jsonrpc": "2.0", "error": ["code": -32_000, "message": message]]
        if let data = try? JSONSerialization.data(withJSONObject: ack), let string = String(data: data, encoding: .utf8) {
            enqueue(string)
        }
    }

    private func enqueue(_ string: String) {
        if !waiters.isEmpty {
            waiters.removeFirst().resume(returning: string)
        } else {
            outbox.append(string)
        }
    }
}
