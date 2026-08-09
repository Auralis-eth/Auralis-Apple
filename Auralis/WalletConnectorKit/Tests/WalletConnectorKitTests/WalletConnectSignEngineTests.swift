import CryptoKit
import Foundation
import Testing
@testable import WalletConnectorKit
import WalletConnectorKitCoinbaseAdapter
import WalletConnectorKitDynamicAdapter
import WalletConnectorKitMetaMaskAdapter
import WalletConnectorKitPrivyAdapter
import WalletConnectorKitReownAdapter
import WalletConnectorKitSolanaAdapter

@Suite("Stub adapter readiness")
struct StubAdapterReadinessTests {
    @Test("Configured Solana adapter is request-only experimental")
    func configuredSolanaAdapterIsRequestOnlyExperimental() {
        let connector = SolanaWalletConnector(client: ConfiguredSolanaClient())
        #expect(connector.readiness.allowsProductionUse == false)
        guard case .experimental = connector.readiness else {
            Issue.record("expected .experimental, got \(connector.readiness)")
            return
        }
    }

    @Test("Unconfigured stub adapters report readiness .unavailable")
    func unconfiguredStubsAreUnavailable() {
        let readinessValues: [WalletConnectorReadiness] = [
            MetaMaskWalletConnector(client: UnconfiguredMetaMaskSDKClient()).readiness,
            PrivyWalletConnector(client: UnconfiguredPrivySDKClient()).readiness,
            DynamicWalletConnector(client: UnconfiguredDynamicSDKClient()).readiness,
            SolanaWalletConnector(client: UnconfiguredSolanaSDKClient()).readiness,
            ReownWalletConnector(client: UnconfiguredReownAppKitClient()).readiness,
            CoinbaseWalletConnector(client: UnconfiguredCoinbaseWalletSDKClient()).readiness,
        ]

        for readiness in readinessValues {
            #expect(readiness.allowsProductionUse == false)
            guard case .unavailable = readiness else {
                Issue.record("expected .unavailable, got \(readiness)")
                continue
            }
        }
    }

    @Test("Configured partial provider adapters remain experimental")
    func configuredPartialProviderAdaptersRemainExperimental() {
        // MetaMask stays a request-only stub (route MetaMask through
        // WalletConnect/Reown instead). Privy/Dynamic delegate the full lifecycle
        // but stay experimental until ownership dependencies are injected.
        let readinessValues: [WalletConnectorReadiness] = [
            MetaMaskWalletConnector(client: ConfiguredStubClient()).readiness,
            PrivyWalletConnector(client: ConfiguredPrivyClient()).readiness,
            DynamicWalletConnector(client: ConfiguredDynamicClient()).readiness,
        ]

        for readiness in readinessValues {
            #expect(readiness.allowsProductionUse == false)
            guard case .experimental = readiness else {
                Issue.record("expected .experimental, got \(readiness)")
                continue
            }
        }
    }

    @Test("Embedded adapter capabilities match their EVM-only live clients")
    func embeddedAdapterCapabilitiesMatchEVMOnlyLiveClients() {
        let privy = PrivyWalletConnector(client: ConfiguredPrivyClient())
        let dynamic = DynamicWalletConnector(client: ConfiguredDynamicClient())

        for capabilities in [privy.capabilities, dynamic.capabilities] {
            #expect(capabilities.contains(.embeddedWallet))
            #expect(capabilities.contains(.evm))
            #expect(capabilities.contains(.messageSigning))
            #expect(!capabilities.contains(.solana))
            #expect(!capabilities.contains(.batchTransactionSigning))
            #expect(!capabilities.contains(.signAndSend))
        }
        #expect(!privy.capabilities.contains(.transactionSigning))
        #expect(dynamic.capabilities.contains(.transactionSigning))
    }

    @Test("Configured Privy/Dynamic reach production readiness with a recovery provider and real metadata")
    func configuredEmbeddedAdaptersReachProductionWithOwnershipDependencies() {
        let recovery = StubRecoveryCryptoProvider()

        // Recovery provider but no explicit production metadata → still experimental.
        #expect(PrivyWalletConnector(client: ConfiguredPrivyClient(), cryptoProvider: recovery).readiness.allowsProductionUse == false)
        #expect(DynamicWalletConnector(client: ConfiguredDynamicClient(), cryptoProvider: recovery).readiness.allowsProductionUse == false)

        // Recovery provider + real metadata → production ready.
        let privyReady = PrivyWalletConnector(client: ConfiguredPrivyClient(), cryptoProvider: recovery, metadata: Self.metadata)
        let dynamicReady = DynamicWalletConnector(client: ConfiguredDynamicClient(), cryptoProvider: recovery, metadata: Self.metadata)
        #expect(privyReady.readiness.allowsProductionUse == true)
        #expect(dynamicReady.readiness.allowsProductionUse == true)
    }

    private static let metadata = WalletConnectionMetadata(
        appName: "Auralis",
        appDescription: "Auralis wallet connection",
        appURL: URL(string: "https://auralis.example")!
    )

    private static func stubEmbeddedSession(topic: String) -> WalletConnectorSession {
        WalletConnectorSession(
            id: WalletSessionID(rawValue: topic),
            topic: WalletPairingTopic(rawValue: topic),
            providerID: "embedded",
            providerName: "Embedded",
            accounts: [WalletAccount(caip10: "eip155:1:0x0000000000000000000000000000000000000000")],
            namespaces: [],
            expiryDate: Date().addingTimeInterval(3600)
        )
    }

    private struct StubRecoveryCryptoProvider: WalletConnectorCryptoProvider {
        var supportsRecovery: Bool { true }
        func recoverPublicKey(signature: WalletEthereumSignature, message: Data) throws -> Data {
            Data(repeating: 1, count: 64)
        }
        func keccak256(_ data: Data) -> Data { Data(repeating: 0, count: 32) }
    }

    private struct ConfiguredSolanaClient: SolanaSDKClient {
        var isConfigured: Bool { true }
        func request(_ request: WalletRequest, in sessionId: WalletSessionID) async throws -> WalletResponse {
            WalletResponse(id: request.id, result: "")
        }
    }

    private struct ConfiguredStubClient: MetaMaskSDKClient {
        var isConfigured: Bool { true }
        func connect(wallet: ThirdPartyWalletProvider?) async throws -> WalletConnectionStart {
            WalletConnectionStart(pairingURI: nil, qrPayload: "")
        }
        func request(_ request: WalletRequest, in sessionId: WalletSessionID) async throws -> WalletResponse {
            WalletResponse(id: request.id, result: "")
        }
        func disconnect(sessionId: WalletSessionID) async throws {}
    }

    private struct ConfiguredPrivyClient: PrivySDKClient {
        var isConfigured: Bool { true }
        func connect(wallet: ThirdPartyWalletProvider?) async throws -> WalletConnectorSession {
            StubAdapterReadinessTests.stubEmbeddedSession(topic: "privy-session")
        }
        func request(_ request: WalletRequest, in sessionId: WalletSessionID) async throws -> WalletResponse {
            WalletResponse(id: request.id, result: "")
        }
        func disconnect(sessionId: WalletSessionID) async throws {}
    }

    private struct ConfiguredDynamicClient: DynamicSDKClient {
        var isConfigured: Bool { true }
        func connect(wallet: ThirdPartyWalletProvider?) async throws -> WalletConnectorSession {
            StubAdapterReadinessTests.stubEmbeddedSession(topic: "dynamic-session")
        }
        func request(_ request: WalletRequest, in sessionId: WalletSessionID) async throws -> WalletResponse {
            WalletResponse(id: request.id, result: "")
        }
        func disconnect(sessionId: WalletSessionID) async throws {}
    }
}

/// End-to-end exercise of the custom WalletConnect v2 Sign transport against a
/// scripted mock relay that plays the wallet role: it decrypts our
/// `wc_sessionPropose`, derives the session key, settles, and answers a request.
/// This proves the full propose → derive → settle → request loop and the
/// ChaCha20-Poly1305 relay envelopes interoperate.
@Suite("WalletConnect v2 Sign engine")
struct WalletConnectSignEngineTests {
    static let walletAddress = "0xAbc0000000000000000000000000000000000001"
    static let account = "eip155:1:\(walletAddress)"

    @Test("Full handshake settles a session and answers a request")
    func fullHandshake() async throws {
        let wallet = MockWalletRelay(address: Self.account)
        let relay = WalletConnectIRNRelayClient(
            configuration: WalletConnectRelayConfiguration(projectID: "test-project"),
            taskFactory: MockWalletRelayFactory(task: wallet),
            authProvider: nil
        )
        let transport = WalletConnectIRNTransportClient(relayClient: relay, stateStore: InMemoryWalletConnectSessionStateStore())

        let collector = EventCollector()
        let events = transport.events()
        Task { for await event in events { await collector.add(event) } }

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

        // The wallet learns the pairing key out-of-band (QR/URI in production).
        let uri = try #require(pairing.uri.flatMap(WalletConnectURI.init(absoluteString:)))
        let symKey = try #require(WalletConnectV2Crypto.data(hexEncoded: uri.symKey))
        await wallet.setPairing(topic: uri.topic, symKey: symKey)

        // Wait for the session to settle.
        let session = try await collector.waitForSettled()
        #expect(session.accounts.first?.caip10 == Self.account)
        #expect(session.providerName == "MockWallet")

        // Round-trip a personal_sign request.
        let response = try await transport.request(
            WalletRequestBuilder.personalSign(
                id: "req-1",
                address: Self.walletAddress,
                message: "0x68656c6c6f"
            ),
            topic: session.topic
        )
        #expect(response.id == "req-1")
        #expect(response.result == MockWalletRelay.signature)
    }

    /// A `wc_sessionDelete` injected on the pairing topic — whose symKey is a
    /// bearer secret carried in the pairing URI and which older builds left
    /// subscribed and decryptable for the client's lifetime — must not tear down a
    /// settled session or emit a spurious `.sessionDeleted`. Proves both the
    /// delete-path live-session guard and the post-settle pairing-topic teardown.
    @Test("A wc_sessionDelete on the pairing topic cannot tear down a settled session")
    func pairingTopicDeleteIsIgnored() async throws {
        let wallet = MockWalletRelay(address: Self.account)
        let relay = WalletConnectIRNRelayClient(
            configuration: WalletConnectRelayConfiguration(projectID: "test-project"),
            taskFactory: MockWalletRelayFactory(task: wallet),
            authProvider: nil
        )
        let transport = WalletConnectIRNTransportClient(relayClient: relay, stateStore: InMemoryWalletConnectSessionStateStore())

        let collector = EventCollector()
        let events = transport.events()
        Task { for await event in events { await collector.add(event) } }

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
        let session = try await collector.waitForSettled()

        // Inject a delete on the pairing topic using the pairing bearer secret.
        await wallet.pushDeleteOnPairing()
        try await Task.sleep(for: .milliseconds(200))

        // The settled session survives and no `.sessionDeleted` fired.
        let live = try await transport.sessions()
        #expect(live.contains { $0.topic == session.topic })
        #expect(await collector.deletedCount() == 0)

        // The session key still round-trips a request end to end.
        let response = try await transport.request(
            WalletRequestBuilder.personalSign(id: "req-after-delete", address: Self.walletAddress, message: "0x68656c6c6f"),
            topic: session.topic
        )
        #expect(response.result == MockWalletRelay.signature)
    }

    /// A message the relay queued while we were not subscribed is only recovered
    /// by an explicit `irn_fetchMessages`; the relay does not replay its mailbox
    /// on subscribe. Proves the messages carried in a fetch acknowledgement are
    /// replayed onto the subscription event stream (the drain the reconnect and
    /// cold-launch-restore paths rely on).
    @Test("Messages in an irn_fetchMessages ack are replayed as subscription events")
    func fetchDrainRecoversQueuedMessages() async throws {
        let task = FetchReplayRelayTask(queued: [(topic: "topic-a", message: "queued-payload", tag: 1108)])
        let relay = WalletConnectIRNRelayClient(
            configuration: WalletConnectRelayConfiguration(projectID: "test-project"),
            taskFactory: SingleRelayTaskFactory(task: task),
            authProvider: nil
        )

        let collector = RelayEventCollector()
        let stream = relay.events
        Task { for await event in stream { await collector.add(event) } }

        // fetchMessages → irn_fetchMessages → ack carrying queued messages →
        // replayed onto the event stream.
        try await relay.fetchMessages(topic: "topic-a")

        try await Task.sleep(for: .milliseconds(100))
        #expect(await collector.eventsSnapshot().contains(.subscription(topic: "topic-a", message: "queued-payload", tag: 1108)))
    }

    /// A request awaiting a response must fail promptly when the session is torn
    /// down, instead of hanging until its (up to 5-minute) expiry.
    @Test("An in-flight request fails fast when the session is disconnected")
    func requestFailsFastOnDisconnect() async throws {
        let wallet = MockWalletRelay(address: Self.account)
        await wallet.stopAnsweringRequests()
        let relay = WalletConnectIRNRelayClient(
            configuration: WalletConnectRelayConfiguration(projectID: "test-project"),
            taskFactory: MockWalletRelayFactory(task: wallet),
            authProvider: nil
        )
        let transport = WalletConnectIRNTransportClient(relayClient: relay, stateStore: InMemoryWalletConnectSessionStateStore())

        let collector = EventCollector()
        let events = transport.events()
        Task { for await event in events { await collector.add(event) } }

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
        let session = try await collector.waitForSettled()

        // Launch a request the wallet will never answer, then tear the session
        // down and assert the request throws instead of waiting out its expiry.
        let requestTask = Task {
            try await transport.request(
                WalletRequestBuilder.personalSign(id: "req-hang", address: Self.walletAddress, message: "0x68656c6c6f"),
                topic: session.topic
            )
        }
        // Give the request time to publish and register its topic binding.
        try await Task.sleep(for: .milliseconds(200))
        try await transport.disconnect(topic: session.topic)

        await #expect(throws: WalletConnectionError.self) {
            _ = try await requestTask.value
        }
    }

    /// Two concurrent first-use callers must both observe the fully restored
    /// session. Before restoration was coalesced, the second caller returned from
    /// `ensureRestored()` while the first was still awaiting `loadAll()`, seeing
    /// an empty session set.
    @Test("Concurrent first-use restoration never observes a half-restored state")
    func restorationCoalescesAcrossConcurrentCallers() async throws {
        let symKeyData = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        let sessionTopic = WalletConnectV2Crypto.topic(forSymmetricKey: symKeyData)
        let persisted = WalletConnectPersistedSession(
            sessionTopic: sessionTopic,
            pairingTopic: sessionTopic,
            sessionSymmetricKeyHex: WalletConnectV2Crypto.hexString(symKeyData),
            selfPrivateKeyHex: nil,
            providerID: "mock",
            providerName: "MockWallet",
            accounts: [WalletAccount(caip10: Self.account)],
            namespaces: [],
            connectedAt: Date(),
            expiryDate: Date().addingTimeInterval(3600)
        )
        let store = DelayingSessionStateStore(sessions: [persisted], delay: .milliseconds(80))

        let wallet = MockWalletRelay(address: Self.account)
        let relay = WalletConnectIRNRelayClient(
            configuration: WalletConnectRelayConfiguration(projectID: "test-project"),
            taskFactory: MockWalletRelayFactory(task: wallet),
            authProvider: nil
        )
        let transport = WalletConnectIRNTransportClient(relayClient: relay, stateStore: store)

        async let first = transport.sessions()
        async let second = transport.sessions()
        let (a, b) = try await (first, second)

        #expect(a.count == 1)
        #expect(b.count == 1)
        #expect(a.first?.topic.rawValue == sessionTopic)
    }

    // MARK: - P2: session update / extend / event

    @Test("A wallet wc_sessionEvent surfaces to the host as a session event")
    func sessionEventSurfaces() async throws {
        let ctx = try await Self.settledSession()
        await ctx.wallet.pushEvent(name: "accountsChanged", chainId: "eip155:1", data: [Self.walletAddress])
        let event = try await ctx.collector.waitForSessionEvent()
        #expect(event.name == "accountsChanged")
        #expect(event.topic == ctx.session.topic)
        #expect(event.chain?.caip2 == "eip155:1")
    }

    @Test("A wallet wc_sessionExtend moves the session expiry forward")
    func sessionExtendUpdatesExpiry() async throws {
        let ctx = try await Self.settledSession()
        // Settle expiry is +1h; extend to +3d (valid: later than current, within 7-day cap).
        let newExpiry = Int(Date().addingTimeInterval(60 * 60 * 24 * 3).timeIntervalSince1970)
        await ctx.wallet.pushExtend(expiry: newExpiry)
        let updated = try await ctx.collector.waitForUpdated()
        #expect(updated.expiryDate > ctx.session.expiryDate)
        let live = try await ctx.transport.sessions()
        #expect(live.first?.expiryDate == updated.expiryDate)
    }

    @Test("A wc_sessionExtend beyond the 7-day cap is ignored")
    func sessionExtendBeyondCapIsIgnored() async throws {
        let ctx = try await Self.settledSession()
        let tooFar = Int(Date().addingTimeInterval(60 * 60 * 24 * 30).timeIntervalSince1970) // +30 days
        await ctx.wallet.pushExtend(expiry: tooFar)
        // No .sessionUpdated should arrive; the live expiry stays at the settle value.
        try await Task.sleep(for: .milliseconds(300))
        let live = try await ctx.transport.sessions()
        #expect(live.first?.expiryDate == ctx.session.expiryDate)
    }

    @Test("A wallet wc_sessionUpdate replaces the session accounts")
    func sessionUpdateReplacesAccounts() async throws {
        let ctx = try await Self.settledSession()
        let newAccount = "eip155:1:0xBbb0000000000000000000000000000000000002"
        await ctx.wallet.pushUpdate(accounts: [newAccount])
        let updated = try await ctx.collector.waitForUpdated()
        #expect(updated.accounts.map(\.caip10) == [newAccount])
    }

    @Test("A wc_sessionUpdate granting only an unproposed chain deletes the session")
    func sessionUpdateDropsUnproposedChain() async throws {
        let ctx = try await Self.settledSession()
        // eip155:999 was never proposed. Filtering leaves no approved accounts,
        // so the hardened transport tears the session down instead of surfacing an
        // empty-account live session.
        await ctx.wallet.pushUpdate(accounts: ["eip155:999:0xCcc0000000000000000000000000000000000003"])
        let deleted = try await ctx.collector.waitForDeleted()
        #expect(deleted == ctx.session.id)
    }

    // MARK: - P3: SIWE ownership challenge

    @Test("verifyOwnership issues a canonical EIP-4361 SIWE challenge bound to the app")
    func ownershipChallengeIsSIWE() async throws {
        // 65-byte signature with a valid v (0x1b/27) so parsing succeeds and we
        // reach recovery; the stub provider can't recover to the address, so
        // verification returns false — but the challenge message is captured.
        let response = "0x" + String(repeating: "ab", count: 64) + "1b"
        let transport = RecordingTransport(response: response)
        let connector = WalletConnectDAppConnector(
            transport: transport,
            metadata: WalletConnectionMetadata(
                appName: "AuraPlay",
                appDescription: "d",
                appURL: URL(string: "https://auraplay.app")!
            ),
            cryptoProvider: StubCryptoProvider()
        )
        let verified = try await connector.verifyOwnership(of: Self.walletAddress, in: WalletSessionID(rawValue: "topic"))
        #expect(verified == false)

        let request = try #require(await transport.lastRequest)
        #expect(request.method == .ethPersonalSign)
        let hex = try #require(request.params.first?.stringValue)
        let messageData = try #require(WalletConnectV2Crypto.data(hexEncoded: String(hex.dropFirst(2))))
        let message = try #require(String(data: messageData, encoding: .utf8))
        #expect(message.contains("auraplay.app wants you to sign in with your Ethereum account:"))
        #expect(message.contains(Self.walletAddress))
        #expect(message.contains("URI: https://auraplay.app"))
        #expect(message.contains("Chain ID: 1"))
        #expect(message.contains("Nonce: "))
        #expect(message.contains("Issued At: "))
        #expect(message.contains("Expiration Time: "))
    }

    @Test("A chain-indexed settle (eip155:1) normalizes to a signable session")
    func chainIndexedSettleIsSignable() async throws {
        let (_, _, _, session) = try await Self.settledSession(
            wallet: MockWalletRelay(address: Self.account, chainIndexedNamespaces: true)
        )
        // Normalization collapses the wallet's chain-scoped "eip155:1" key to the
        // bare "eip155" namespace, so grant validation (which matches on namespace)
        // accepts a personal_sign instead of rejecting an unsignable session.
        #expect(session.namespaces.contains { $0.name == "eip155" })
        #expect(session.accounts.contains { $0.caip10 == Self.account })
        let request = WalletRequestBuilder.personalSign(id: "req-1", address: Self.walletAddress, message: "0xdeadbeef")
        try WalletSessionGrantValidator.validate(request, in: session)
    }

    @Test("ping resolves when the wallet pongs")
    func pingResolvesOnPong() async throws {
        let (transport, _, _, session) = try await Self.settledSession()
        try await transport.ping(topic: session.topic)
    }

    @Test("ping surfaces a dead peer that never pongs")
    func pingTimesOutWithoutPong() async throws {
        let wallet = MockWalletRelay(address: Self.account)
        await wallet.stopAnsweringPings()
        let (transport, _, _, session) = try await Self.settledSession(wallet: wallet, pongTimeout: .milliseconds(200))
        await #expect(throws: WalletConnectionError.self) {
            try await transport.ping(topic: session.topic)
        }
    }

    @Test("extend moves the session expiry and re-persists")
    func extendMovesExpiry() async throws {
        let (transport, _, _, session) = try await Self.settledSession()
        let newExpiry = Date().addingTimeInterval(3 * 86_400)
        let moved = try await transport.extend(topic: session.topic, to: newExpiry)
        #expect(moved)
        let updated = try #require(try await transport.sessions().first { $0.topic == session.topic })
        #expect(updated.expiryDate > session.expiryDate)
    }

    /// Drives the propose → settle handshake and returns the live transport, the
    /// mock wallet (for pushing peer requests), the event collector, and the
    /// settled session.
    fileprivate static func settledSession(
        wallet: MockWalletRelay = MockWalletRelay(address: account),
        pongTimeout: Duration = .seconds(15)
    ) async throws -> (
        transport: WalletConnectIRNTransportClient,
        wallet: MockWalletRelay,
        collector: EventCollector,
        session: WalletSession
    ) {
        let relay = WalletConnectIRNRelayClient(
            configuration: WalletConnectRelayConfiguration(projectID: "test-project"),
            taskFactory: MockWalletRelayFactory(task: wallet),
            authProvider: nil
        )
        let transport = WalletConnectIRNTransportClient(
            relayClient: relay,
            stateStore: InMemoryWalletConnectSessionStateStore(),
            keepAliveInterval: nil,
            pongTimeout: pongTimeout
        )
        let collector = EventCollector()
        let events = transport.events()
        Task { for await event in events { await collector.add(event) } }

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
        let session = try await collector.waitForSettled()
        return (transport, wallet, collector, session)
    }
}

private struct StubCryptoProvider: WalletConnectorCryptoProvider {
    func recoverPublicKey(signature: WalletEthereumSignature, message: Data) throws -> Data {
        // A key that cannot recover to any real address, so verification fails
        // closed while the challenge message is still captured for inspection.
        Data(repeating: 0, count: 64)
    }

    func keccak256(_ data: Data) -> Data { Data(repeating: 0, count: 32) }
}

private actor RecordingTransport: WalletTransportClient {
    private(set) var lastRequest: WalletRequest?
    private let response: String
    private let stream: AsyncStream<WalletTransportEvent>

    init(response: String) {
        self.response = response
        self.stream = AsyncStream { $0.finish() }
    }

    func createPairing(request: WalletPairingRequest) async throws -> WalletPairing {
        throw WalletConnectionError.unavailable("not used")
    }

    func disconnect(topic: WalletPairingTopic) async throws {}

    func request(_ request: WalletRequest, topic: WalletPairingTopic) async throws -> WalletResponse {
        lastRequest = request
        return WalletResponse(id: request.id, result: response)
    }

    func sessions() async throws -> [WalletSession] { [] }

    nonisolated func events() -> AsyncStream<WalletTransportEvent> { stream }
}

private actor EventCollector {
    private var events: [WalletTransportEvent] = []
    private var settledWaiter: CheckedContinuation<WalletSession, Error>?
    private var updatedWaiter: CheckedContinuation<WalletSession, Error>?
    private var deletedWaiter: CheckedContinuation<WalletSessionID, Error>?
    private var sessionEventWaiter: CheckedContinuation<WalletSessionEvent, Error>?

    func add(_ event: WalletTransportEvent) {
        events.append(event)
        switch event {
        case .sessionApproved(let session):
            settledWaiter?.resume(returning: session)
            settledWaiter = nil
        case .sessionUpdated(let session):
            updatedWaiter?.resume(returning: session)
            updatedWaiter = nil
        case .sessionDeleted(let sessionID):
            deletedWaiter?.resume(returning: sessionID)
            deletedWaiter = nil
        case .sessionEvent(let walletEvent):
            sessionEventWaiter?.resume(returning: walletEvent)
            sessionEventWaiter = nil
        default:
            break
        }
    }

    /// Number of `.sessionDeleted` events observed so far — lets a test assert a
    /// spurious teardown never fired.
    func deletedCount() -> Int {
        events.reduce(into: 0) { count, event in
            if case .sessionDeleted = event { count += 1 }
        }
    }

    func waitForSettled(timeout: Duration = .seconds(5)) async throws -> WalletSession {
        for event in events {
            if case .sessionApproved(let session) = event { return session }
        }
        return try await withTimeout(timeout) { try await self.awaitSettled() }
    }

    func waitForUpdated(timeout: Duration = .seconds(5)) async throws -> WalletSession {
        for event in events {
            if case .sessionUpdated(let session) = event { return session }
        }
        return try await withTimeout(timeout) { try await self.awaitUpdated() }
    }

    func waitForDeleted(timeout: Duration = .seconds(5)) async throws -> WalletSessionID {
        for event in events {
            if case .sessionDeleted(let sessionID) = event { return sessionID }
        }
        return try await withTimeout(timeout) { try await self.awaitDeleted() }
    }

    func waitForSessionEvent(timeout: Duration = .seconds(5)) async throws -> WalletSessionEvent {
        for event in events {
            if case .sessionEvent(let walletEvent) = event { return walletEvent }
        }
        return try await withTimeout(timeout) { try await self.awaitSessionEvent() }
    }

    private func awaitSettled() async throws -> WalletSession {
        try await withCheckedThrowingContinuation { settledWaiter = $0 }
    }

    private func awaitUpdated() async throws -> WalletSession {
        try await withCheckedThrowingContinuation { updatedWaiter = $0 }
    }

    private func awaitDeleted() async throws -> WalletSessionID {
        try await withCheckedThrowingContinuation { deletedWaiter = $0 }
    }

    private func awaitSessionEvent() async throws -> WalletSessionEvent {
        try await withCheckedThrowingContinuation { sessionEventWaiter = $0 }
    }

    private func withTimeout<T: Sendable>(
        _ timeout: Duration,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw WalletConnectionError.requestTimedOut("event")
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}

private struct MockWalletRelayFactory: WalletConnectRelayTaskFactory {
    let task: MockWalletRelay
    func makeTask(url: URL) async throws -> any WalletConnectRelayTask { task }
}

/// A single-socket mock that behaves as both relay and wallet. It acks
/// subscribe/publish, and on receiving our proposal it drives the wallet side
/// of the handshake back over the same socket.
private actor MockWalletRelay: WalletConnectRelayTask {
    static let signature = "0xdeadbeefsignature"

    private let account: String
    private let walletKey = WalletConnectV2Crypto.generateKeyPair()

    private var outbox: [String] = []
    private var waiters: [CheckedContinuation<String, Error>] = []

    private var pairingTopic: String?
    private var pairingSymKey: Data?
    private var bufferedPropose: String?
    private var sessionSymKey: Data?
    private var sessionTopic: String?
    private var pendingSettle: (topic: String, message: String)?
    private var answersRequests = true
    private var answersPings = true
    private let chainIndexedNamespaces: Bool

    init(address: String, chainIndexedNamespaces: Bool = false) {
        self.account = address
        self.chainIndexedNamespaces = chainIndexedNamespaces
    }

    /// Stops the mock wallet from answering `wc_sessionRequest`, so a dapp
    /// request stays in flight until the session is torn down — used to prove
    /// the transport fails pending requests on disconnect instead of hanging.
    func stopAnsweringRequests() { answersRequests = false }

    /// Stops the mock wallet from ponging `wc_sessionPing`, so a keepalive ping
    /// stays in flight — used to prove the transport surfaces a dead peer.
    func stopAnsweringPings() { answersPings = false }

    /// Pushes a `wc_sessionUpdate` re-granting the given accounts on eip155.
    func pushUpdate(accounts: [String], id: Int = 7001) {
        guard let sessionSymKey, let sessionTopic else { return }
        let params: [String: Any] = [
            "namespaces": ["eip155": ["accounts": accounts, "methods": ["personal_sign"], "events": ["chainChanged"]]],
        ]
        pushPeerRequest(method: "wc_sessionUpdate", params: params, id: id, tag: 1104, symKey: sessionSymKey, topic: sessionTopic)
    }

    /// Pushes a `wc_sessionExtend` to the given absolute expiry (Unix seconds).
    func pushExtend(expiry: Int, id: Int = 7002) {
        guard let sessionSymKey, let sessionTopic else { return }
        pushPeerRequest(method: "wc_sessionExtend", params: ["expiry": expiry], id: id, tag: 1106, symKey: sessionSymKey, topic: sessionTopic)
    }

    /// Pushes a `wc_sessionEvent` (e.g. `accountsChanged`).
    func pushEvent(name: String, chainId: String, data: Any, id: Int = 7003) {
        guard let sessionSymKey, let sessionTopic else { return }
        let params: [String: Any] = ["event": ["name": name, "data": data], "chainId": chainId]
        pushPeerRequest(method: "wc_sessionEvent", params: params, id: id, tag: 1110, symKey: sessionSymKey, topic: sessionTopic)
    }

    /// Pushes a `wc_sessionDelete` on the **pairing** topic (whose symKey the
    /// wallet still holds from the URI), simulating a party with the pairing bearer
    /// secret trying to drive a spurious teardown after the session settled.
    func pushDeleteOnPairing(id: Int = 7009) {
        guard let pairingSymKey, let pairingTopic else { return }
        let params: [String: Any] = ["code": 6000, "message": "User disconnected."]
        pushPeerRequest(method: "wc_sessionDelete", params: params, id: id, tag: 1112, symKey: pairingSymKey, topic: pairingTopic)
    }

    private func pushPeerRequest(method: String, params: [String: Any], id: Int, tag: Int, symKey: Data, topic: String) {
        let json: [String: Any] = ["id": id, "jsonrpc": "2.0", "method": method, "params": params]
        if let push = encryptedPush(json: json, topic: topic, tag: tag, symKey: symKey) {
            enqueue(push)
        }
    }

    func setPairing(topic: String, symKey: Data) {
        pairingTopic = topic
        pairingSymKey = symKey
        if let message = bufferedPropose {
            bufferedPropose = nil
            processPropose(message)
        }
    }

    // MARK: WalletConnectRelayTask

    func send(_ string: String) async throws {
        guard let data = string.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        guard let method = json["method"] as? String else { return } // ignore acks from the dapp
        let id = json["id"] as? Int ?? 0
        let params = json["params"] as? [String: Any] ?? [:]

        switch method {
        case "irn_subscribe":
            enqueueAck(id: id, result: "subscription-\(params["topic"] as? String ?? "unknown")")
            if let topic = params["topic"] as? String, topic == sessionTopic, let settle = pendingSettle {
                pendingSettle = nil
                enqueue(settle.message)
            }
        case "irn_publish":
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
        switch tag {
        case WalletConnectSignTag.sessionPropose:
            if pairingSymKey == nil {
                bufferedPropose = message
            } else {
                processPropose(message)
            }
        case WalletConnectSignTag.sessionRequest:
            guard answersRequests else { return }
            processRequest(message)
        case WalletConnectSignTag.sessionPing:
            guard answersPings else { return }
            answerAck(message)
        case WalletConnectSignTag.sessionExtend:
            answerAck(message)
        default:
            break
        }
    }

    /// Decrypts an inbound `wc_sessionPing`/`wc_sessionExtend` request and pushes
    /// the `{id, result: true}` ack the transport awaits on the session topic.
    private func answerAck(_ message: String) {
        guard let sessionSymKey, let sessionTopic,
              let envelope = try? WalletConnectEnvelope(base64Encoded: message),
              let plaintext = try? WalletConnectV2Crypto.open(sealbox: envelope.sealbox, symKey: sessionSymKey),
              let rpc = try? JSONSerialization.jsonObject(with: plaintext) as? [String: Any],
              let requestID = rpc["id"] as? Int else { return }
        let response: [String: Any] = ["id": requestID, "jsonrpc": "2.0", "result": true]
        if let push = encryptedPush(json: response, topic: sessionTopic, tag: WalletConnectSignTag.sessionPingResponse, symKey: sessionSymKey) {
            enqueue(push)
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

        // 1101 propose response on the pairing topic.
        let response: [String: Any] = [
            "id": proposeID,
            "jsonrpc": "2.0",
            "result": ["relay": ["protocol": "irn"], "responderPublicKey": walletKey.publicKeyHex],
        ]
        if let push = encryptedPush(json: response, topic: pairingTopic, tag: WalletConnectSignTag.sessionProposeResponseApprove, symKey: pairingSymKey) {
            enqueue(push)
        }

        // Prepare 1102 settle for when the dapp subscribes to the session topic.
        let settle: [String: Any] = [
            "id": Int(Date().timeIntervalSince1970 * 1000),
            "jsonrpc": "2.0",
            "method": "wc_sessionSettle",
            "params": [
                "relay": ["protocol": "irn"],
                "controller": ["publicKey": walletKey.publicKeyHex, "metadata": ["name": "MockWallet", "description": "m", "url": "https://mock", "icons": []]],
                "namespaces": [(chainIndexedNamespaces ? "eip155:1" : "eip155"): ["accounts": [account], "methods": ["personal_sign"], "events": ["chainChanged"]]],
                "expiry": Int(Date().addingTimeInterval(3600).timeIntervalSince1970),
            ],
        ]
        if let push = encryptedPush(json: settle, topic: sessionTopic, tag: WalletConnectSignTag.sessionSettle, symKey: sessionSymKey) {
            pendingSettle = (sessionTopic, push)
        }
    }

    private func processRequest(_ message: String) {
        guard let sessionSymKey, let sessionTopic,
              let envelope = try? WalletConnectEnvelope(base64Encoded: message),
              let plaintext = try? WalletConnectV2Crypto.open(sealbox: envelope.sealbox, symKey: sessionSymKey),
              let rpc = try? JSONSerialization.jsonObject(with: plaintext) as? [String: Any],
              let requestID = rpc["id"] as? Int else { return }

        let response: [String: Any] = ["id": requestID, "jsonrpc": "2.0", "result": Self.signature]
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

    private func enqueue(_ string: String) {
        if !waiters.isEmpty {
            waiters.removeFirst().resume(returning: string)
        } else {
            outbox.append(string)
        }
    }
}

private struct SingleRelayTaskFactory<Task: WalletConnectRelayTask>: WalletConnectRelayTaskFactory {
    let task: Task
    func makeTask(url: URL) async throws -> any WalletConnectRelayTask { task }
}

/// A relay stub that acks everything with `true`, except `irn_fetchMessages`,
/// which it answers with a `{ messages: [...] }` result carrying the queued
/// payloads — mirroring how the real relay replays a topic's mailbox only on an
/// explicit fetch (never on subscribe).
private actor FetchReplayRelayTask: WalletConnectRelayTask {
    private let queued: [(topic: String, message: String, tag: Int)]
    private var outbox: [String] = []
    private var waiters: [CheckedContinuation<String, Error>] = []

    init(queued: [(topic: String, message: String, tag: Int)]) { self.queued = queued }

    func send(_ string: String) async throws {
        guard let data = string.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let method = json["method"] as? String,
              let id = json["id"] as? Int else { return }
        switch method {
        case "irn_fetchMessages":
            let messages = queued.map { ["topic": $0.topic, "message": $0.message, "tag": $0.tag] as [String: Any] }
            enqueue(["id": id, "jsonrpc": "2.0", "result": ["messages": messages, "hasMore": false]])
        case "irn_subscribe":
            enqueue(["id": id, "jsonrpc": "2.0", "result": "subscription-id"])
        default:
            enqueue(["id": id, "jsonrpc": "2.0", "result": true])
        }
    }

    func receive() async throws -> String {
        if !outbox.isEmpty { return outbox.removeFirst() }
        return try await withCheckedThrowingContinuation { waiters.append($0) }
    }

    func close() async {}

    private func enqueue(_ json: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let string = String(data: data, encoding: .utf8) else { return }
        if !waiters.isEmpty {
            waiters.removeFirst().resume(returning: string)
        } else {
            outbox.append(string)
        }
    }
}

private actor RelayEventCollector {
    private var events: [WalletConnectRelayEvent] = []
    private var subscriptionWaiter: CheckedContinuation<(topic: String, message: String), Error>?

    func add(_ event: WalletConnectRelayEvent) {
        events.append(event)
        if case .subscription(let topic, let message, _) = event, let waiter = subscriptionWaiter {
            subscriptionWaiter = nil
            waiter.resume(returning: (topic, message))
        }
    }

    func eventsSnapshot() -> [WalletConnectRelayEvent] {
        events
    }

    func waitForSubscription(timeout: Duration = .seconds(5)) async throws -> (topic: String, message: String) {
        for event in events {
            if case .subscription(let topic, let message, _) = event { return (topic, message) }
        }
        return try await withThrowingTaskGroup(of: (topic: String, message: String).self) { group in
            group.addTask { try await self.awaitSubscription() }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw WalletConnectionError.requestTimedOut("subscription")
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private func awaitSubscription() async throws -> (topic: String, message: String) {
        try await withCheckedThrowingContinuation { subscriptionWaiter = $0 }
    }
}

/// In-memory session store whose `loadAll` is deliberately slow, so a second
/// `ensureRestored()` caller arrives while the first is still suspended in the
/// load — the exact window the restoration-coalescing fix closes.
private actor DelayingSessionStateStore: WalletConnectSessionStatePersisting {
    private var byTopic: [String: WalletConnectPersistedSession]
    private let delay: Duration

    init(sessions: [WalletConnectPersistedSession], delay: Duration) {
        self.byTopic = Dictionary(uniqueKeysWithValues: sessions.map { ($0.sessionTopic, $0) })
        self.delay = delay
    }

    func save(_ session: WalletConnectPersistedSession) { byTopic[session.sessionTopic] = session }

    func loadAll() async throws -> [WalletConnectPersistedSession] {
        try? await Task.sleep(for: delay)
        return byTopic.keys.sorted().compactMap { byTopic[$0] }
    }

    func delete(sessionTopic: String) { byTopic.removeValue(forKey: sessionTopic) }
}
