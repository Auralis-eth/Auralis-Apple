import Foundation
import Security
import Testing
@testable import WalletConnectorKit

@Suite("Wallet account parsing")
struct WalletAccountParsingTests {
    @Test(
        "Parses supported CAIP-10 accounts",
        arguments: [
            ("eip155:1:0x0000000000000000000000000000000000000000", "eip155:1", "0x0000000000000000000000000000000000000000", WalletChain.ethereum),
            ("eip155:137:0x1111111111111111111111111111111111111111", "eip155:137", "0x1111111111111111111111111111111111111111", WalletChain.polygon),
            ("eip155:8453:0x2222222222222222222222222222222222222222", "eip155:8453", "0x2222222222222222222222222222222222222222", WalletChain.base),
            ("solana:mainnet:11111111111111111111111111111111", "solana:mainnet", "11111111111111111111111111111111", WalletChain.solana),
        ]
    )
    func parsesSupportedAccounts(caip10: String, caip2: String, address: String, chain: WalletChain) throws {
        let account = try #require(WalletAccountParser.parse(caip10))
        #expect(account.blockchain.caip2 == caip2)
        #expect(account.address == address)
        #expect(account.blockchain.knownChain == chain)
        #expect(account.caip10 == caip10)
    }

    @Test(
        "Rejects unsupported or malformed CAIP-10 accounts",
        arguments: [
            "",
            ":1:0x0000000000000000000000000000000000000000",
            "eip155::0x0000000000000000000000000000000000000000",
            "eip155:1:",
            "eip155:1",
            "eip155:1:not-an-address",
            "eip155:1:0x000000000000000000000000000000000000000",
            "eip155:1:0x000000000000000000000000000000000000000g",
            "eip155:999:0x0000000000000000000000000000000000000000",
            "solana:mainnet:0x0000000000000000000000000000000000000000",
            "solana:mainnet:0OIl1111111111111111111111111111",
            "cosmos:cosmoshub-4:cosmos1address",
        ]
    )
    func rejectsMalformedAccounts(caip10: String) {
        #expect(WalletAccountParser.parse(caip10) == nil)
    }
}

@Suite("Wallet namespaces and requests")
struct WalletNamespaceAndRequestTests {
    @Test("Default namespace proposal matches V1 EVM and Solana scope")
    func defaultNamespaceProposalMatchesV1Scope() {
        let proposal = WalletNamespaceProposalSet.defaultV1

        #expect(proposal.proposals["eip155"]?.chains.map(\.caip2) == ["eip155:1", "eip155:137", "eip155:8453", "eip155:10", "eip155:42161"])
        #expect(proposal.proposals["eip155"]?.methods == WalletConnectionNamespaces.evmMethods)
        #expect(proposal.proposals["eip155"]?.events == WalletConnectionNamespaces.evmEvents)
        #expect(proposal.proposals["solana"]?.chains.map(\.caip2) == ["solana:mainnet"])
        #expect(proposal.proposals["solana"]?.methods == WalletConnectionNamespaces.solanaMethods)
        #expect(proposal.proposals["solana"]?.events == [])
    }

    @Test("Request builders create deterministic request payloads")
    func requestBuildersCreateDeterministicPayloads() throws {
        let evm = WalletRequestBuilder.personalSign(
            id: "request-1",
            address: "0x0000000000000000000000000000000000000000",
            message: "Hello",
            chain: .base,
            expiryDate: .sampleDate
        )
        let solana = WalletRequestBuilder.solanaSignMessage(
            id: "request-2",
            address: "11111111111111111111111111111111",
            message: "Hello",
            expiryDate: .sampleDate
        )

        #expect(evm.chain.caip2 == "eip155:8453")
        #expect(evm.method == .ethPersonalSign)
        #expect(evm.params == ["Hello", "0x0000000000000000000000000000000000000000"])
        #expect(solana.chain.caip2 == "solana:mainnet")
        #expect(solana.method == .solanaSignMessage)
        #expect(solana.params == ["Hello", "11111111111111111111111111111111"])
        try assertRoundTrip(evm)
        try assertRoundTrip(solana)
    }
}

@Suite("WalletConnect deep links")
struct WalletConnectDeepLinkTests {
    @Test("WalletConnect URI formats and parses canonical v2 pairing URI")
    func walletConnectURIFormatsAndParses() throws {
        let uri = WalletConnectURI(
            topic: "topic-1",
            symKey: "abc123",
            expiryTimestamp: 1_800_000_000,
            methods: ["wc_sessionPropose"]
        )
        let parsed = try #require(WalletConnectURI(absoluteString: uri.absoluteString))

        #expect(uri.absoluteString == "wc:topic-1@2?symKey=abc123&relay-protocol=irn&expiryTimestamp=1800000000&methods=wc_sessionPropose")
        #expect(uri.deeplinkURIValue == "wc%3Atopic-1%402%3FsymKey%3Dabc123%26relay-protocol%3Dirn%26expiryTimestamp%3D1800000000%26methods%3Dwc_sessionPropose")
        #expect(parsed == uri)
    }

    @Test("Provider deep link encodes nested WalletConnect URI once")
    func providerDeepLinkEncodesNestedURIOnce() throws {
        let uri = WalletConnectURI(topic: "topic-1", symKey: "abc123", expiryTimestamp: 1_800_000_000)
        let link = WalletProviderDeepLink(providerID: "metamask", scheme: "metamask://")
        let url = try #require(link.url(pairingURI: uri))

        #expect(url.absoluteString == "metamask://wc?uri=wc%3Atopic-1%402%3FsymKey%3Dabc123%26relay-protocol%3Dirn%26expiryTimestamp%3D1800000000")
    }

    @Test("Return URL handler separates foreground and future Link Mode callbacks")
    func returnURLHandlerSeparatesCallbackKinds() throws {
        let handler = WalletReturnURLHandler()

        #expect(handler.handle(try #require(URL(string: "auralis-wcdemo://wc"))) == .foreground)
        #expect(handler.handle(try #require(URL(string: "auralis-wcdemo://callback?wc_ev=envelope"))) == .linkModeEnvelope("envelope"))
        #expect(handler.handle(try #require(URL(string: "auralis-wcdemo://unrelated"))) == nil)
    }
}

@Suite("Wallet connection core")
struct WalletConnectionCoreTests {
    @Test("Deep-link launcher opens installed wallet")
    func deepLinkLauncherOpensInstalledWallet() async throws {
        let opener = RecordingWalletOpener(canOpen: true, openResult: true)
        let launcher = DeepLinkWalletLauncher(opener: opener)
        let uri = WalletConnectURI(topic: "topic-1", symKey: "abc123", expiryTimestamp: 1_800_000_000)

        try await launcher.launch(provider: WalletConnectorCatalog.metamask, pairingURI: uri)

        #expect(await opener.openedURLs().map(\.absoluteString) == [
            "metamask://wc?uri=wc%3Atopic-1%402%3FsymKey%3Dabc123%26relay-protocol%3Dirn%26expiryTimestamp%3D1800000000",
        ])
    }

    @Test("Deep-link launcher reports wallet not installed")
    func deepLinkLauncherReportsMissingWallet() async {
        let opener = RecordingWalletOpener(canOpen: false, openResult: false)
        let launcher = DeepLinkWalletLauncher(opener: opener)
        let uri = WalletConnectURI(topic: "topic-1", symKey: "abc123", expiryTimestamp: 1_800_000_000)

        await #expect(throws: WalletConnectionError.walletNotInstalled("metamask")) {
            try await launcher.launch(provider: WalletConnectorCatalog.metamask, pairingURI: uri)
        }
    }

    @Test("DApp connector creates pairing and opens selected wallet through injected boundary")
    func dAppConnectorCreatesPairingAndOpensWallet() async throws {
        let opener = RecordingWalletOpener(canOpen: true, openResult: true)
        let transport = FakeWalletTransport()
        let connector = WalletConnectDAppConnector(
            transport: transport,
            launcher: DeepLinkWalletLauncher(opener: opener),
            metadata: .testValue,
            callbackURL: URL(string: "auralis-wcdemo://wc")
        )

        let start = try await connector.connect(
            proposal: .defaultV1,
            wallet: WalletConnectorCatalog.rainbow
        )

        #expect(start.qrPayload == start.pairingURI.absoluteString)
        #expect(start.walletOpenURL?.scheme == "rainbow")
        #expect(await transport.pairingRequests().first?.providerID == "rainbow")
        #expect(await opener.openedURLs().first?.scheme == "rainbow")
    }

    @Test("In-memory session store saves loads lists and deletes sessions")
    func inMemorySessionStoreRoundTrips() async throws {
        let store = InMemoryWalletSessionStore()
        let record = WalletSessionRecord(session: .sampleSession, savedAt: .sampleDate)

        await store.save(record)

        #expect(await store.load(sessionID: "topic-1") == record)
        #expect(await store.loadAll() == [record])

        await store.delete(sessionID: "topic-1")
        #expect(await store.loadAll().isEmpty)
    }

    @Test("Session address extractor filters unsupported accounts and deduplicates by chain and address")
    func sessionAddressExtractorFiltersAndDeduplicates() throws {
        let session = WalletConnectorSession(
            id: "topic-1",
            topic: "topic-1",
            providerID: "generic",
            providerName: "Generic Wallet",
            accounts: [
                WalletAccount(caip10: "eip155:1:0x0000000000000000000000000000000000000000"),
                WalletAccount(caip10: "eip155:1:0x0000000000000000000000000000000000000000"),
                WalletAccount(caip10: "eip155:999:0x1111111111111111111111111111111111111111"),
                WalletAccount(caip10: "solana:mainnet:11111111111111111111111111111111"),
            ],
            namespaces: [],
            expiryDate: .sampleDate
        )

        let addresses = WalletSessionAddressExtractor.extract(from: session)

        #expect(addresses.map(\.chain) == [.ethereum, .solana])
        #expect(addresses.map(\.account.caip10) == [
            "eip155:1:0x0000000000000000000000000000000000000000",
            "solana:mainnet:11111111111111111111111111111111",
        ])
    }

    @Test("In-memory active wallet store round-trips selection")
    func inMemoryActiveWalletStoreRoundTrips() {
        let store = InMemoryActiveWalletStore()

        #expect(store.get() == nil)
        store.set("0x0000000000000000000000000000000000000000")
        #expect(store.get() == "0x0000000000000000000000000000000000000000")
        store.clear()
        #expect(store.get() == nil)
    }

    @Test("Keychain query factory uses device-only unlocked storage and disables synchronization")
    func keychainQueryFactoryUsesRequiredSecurityAttributes() {
        let factory = KeychainSessionTopicQueryFactory(service: "test.service")
        let query = factory.addQuery(
            walletAddress: "0x0000000000000000000000000000000000000000",
            topicData: Data("topic-1".utf8)
        )

        #expect(query[kSecClass as String] as? String == kSecClassGenericPassword as String)
        #expect(query[kSecAttrService as String] as? String == "test.service")
        #expect(query[kSecAttrAccount as String] as? String == "0x0000000000000000000000000000000000000000")
        #expect(query[kSecAttrAccessible as String] as? String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        #expect(query[kSecAttrSynchronizable as String] as? Bool == false)
    }

    @Test("Relay configuration appends project ID query item")
    func relayConfigurationAppendsProjectID() throws {
        let configuration = WalletConnectRelayConfiguration(
            projectID: "project-1",
            relayURL: try #require(URL(string: "wss://relay.walletconnect.com"))
        )

        #expect(configuration.websocketURL.absoluteString == "wss://relay.walletconnect.com?projectId=project-1")
    }

    @Test("IRN relay client sends subscribe and publish JSON-RPC messages")
    func irnRelayClientSendsSubscribeAndPublish() async throws {
        let task = RecordingRelayTask()
        let client = WalletConnectIRNRelayClient(
            configuration: WalletConnectRelayConfiguration(projectID: "project-1"),
            taskFactory: FixedRelayTaskFactory(task: task)
        )

        try await client.subscribe(topic: "topic-1")
        try await client.publish(
            WalletConnectRelayPublish(
                topic: "topic-1",
                message: "encrypted-message",
                tag: 1100,
                ttl: 300
            )
        )

        let sent = await task.sentMessages()
        #expect(sent.count == 2)
        #expect(sent[0].contains(#""method":"irn_subscribe""#))
        #expect(sent[0].contains(#""topic":"topic-1""#))
        #expect(sent[1].contains(#""method":"irn_publish""#))
        #expect(sent[1].contains(#""message":"encrypted-message""#))
        #expect(sent[1].contains(#""tag":1100"#))
    }

    @Test("IRN relay client surfaces subscription events")
    func irnRelayClientSurfacesSubscriptionEvents() async throws {
        let task = RecordingRelayTask(receiveMessages: [
            #"{"id":99,"jsonrpc":"2.0","method":"irn_subscription","params":{"data":{"topic":"topic-1","message":"payload","tag":1101}}}"#,
        ])
        let client = WalletConnectIRNRelayClient(
            configuration: WalletConnectRelayConfiguration(projectID: "project-1"),
            taskFactory: FixedRelayTaskFactory(task: task)
        )

        var iterator = client.events.makeAsyncIterator()
        try await client.subscribe(topic: "topic-1")

        var observedSubscription: WalletConnectRelayEvent?
        for _ in 0..<4 {
            guard let event = await iterator.next() else { break }
            if case .subscription = event {
                observedSubscription = event
                break
            }
        }

        #expect(observedSubscription == .subscription(topic: "topic-1", message: "payload", tag: 1101))
    }

    @Test("Lifecycle service persists settled sessions and selects the newest address")
    func lifecyclePersistsSettledSession() async throws {
        let accountStore = RecordingWalletAccountStore()
        let topicStore = InMemoryWalletSessionTopicStore()
        let activeStore = InMemoryActiveWalletStore()
        let metadataResolver = RecordingWalletMetadataResolver()
        let service = WalletConnectionLifecycleService(
            connector: FakeSessionWalletConnector(sessions: []),
            accountStore: accountStore,
            topicStore: topicStore,
            activeWalletStore: activeStore,
            metadataResolver: metadataResolver,
            now: { .sampleDate }
        )

        let result = try await service.persistApprovedSession(.multiAccountSession)

        #expect(result.persistedAddresses.map(\.account.address) == [
            "0x0000000000000000000000000000000000000000",
            "11111111111111111111111111111111",
        ])
        #expect(activeStore.get() == "11111111111111111111111111111111")
        #expect(await topicStore.load(walletAddress: "0x0000000000000000000000000000000000000000") == "topic-1")
        #expect(await accountStore.upserted().count == 2)
        #expect(await metadataResolver.refreshed().count == 2)
    }

    @Test("Lifecycle service restores live sessions and removes expired saved topics")
    func lifecycleRestoresLiveSessionsAndDeletesExpiredTopics() async throws {
        let accountStore = RecordingWalletAccountStore(fallbackAddress: nil)
        let topicStore = InMemoryWalletSessionTopicStore(records: [
            WalletSessionTopicRecord(address: "0x0000000000000000000000000000000000000000", topic: "topic-1"),
            WalletSessionTopicRecord(address: "0xffffffffffffffffffffffffffffffffffffffff", topic: "expired-topic"),
        ])
        let activeStore = InMemoryActiveWalletStore()
        let service = WalletConnectionLifecycleService(
            connector: FakeSessionWalletConnector(sessions: [.sampleSession]),
            accountStore: accountStore,
            topicStore: topicStore,
            activeWalletStore: activeStore,
            now: { .sampleDate }
        )

        let result = try await service.restoreSavedSessions()

        #expect(result.persistedAddresses.map(\.account.address) == ["0x0000000000000000000000000000000000000000"])
        #expect(activeStore.get() == "0x0000000000000000000000000000000000000000")
        #expect(await topicStore.load(walletAddress: "0xffffffffffffffffffffffffffffffffffffffff") == nil)
        #expect(await accountStore.deactivated().map(\.address) == ["0xffffffffffffffffffffffffffffffffffffffff"])
    }

    @Test("Lifecycle service removes wallet sessions and falls back active selection")
    func lifecycleRemovesWalletAndFallsBackActiveSelection() async throws {
        let accountStore = RecordingWalletAccountStore(fallbackAddress: "0x1111111111111111111111111111111111111111")
        let topicStore = InMemoryWalletSessionTopicStore(records: [
            WalletSessionTopicRecord(address: "0x0000000000000000000000000000000000000000", topic: "topic-1"),
        ])
        let activeStore = InMemoryActiveWalletStore(address: "0x0000000000000000000000000000000000000000")
        let cleaner = RecordingWalletRemovalCleaner()
        let connector = FakeSessionWalletConnector(sessions: [.sampleSession])
        let service = WalletConnectionLifecycleService(
            connector: connector,
            accountStore: accountStore,
            topicStore: topicStore,
            activeWalletStore: activeStore,
            removalCleaner: cleaner,
            now: { .sampleDate }
        )

        try await service.remove(address: "0x0000000000000000000000000000000000000000", chain: .ethereum)

        #expect(await connector.disconnectedSessionIDs() == ["topic-1"])
        #expect(await topicStore.load(walletAddress: "0x0000000000000000000000000000000000000000") == nil)
        #expect(await accountStore.deactivated().map(\.address) == ["0x0000000000000000000000000000000000000000"])
        #expect(await cleaner.cleanedAddresses() == ["0x0000000000000000000000000000000000000000"])
        #expect(activeStore.get() == "0x1111111111111111111111111111111111111111")
    }
}

@Suite("Wallet crypto provider")
struct WalletCryptoProviderTests {
    @Test("Keccak-256 matches known Ethereum vectors", arguments: [
        (Data(), "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470"),
        (Data("abc".utf8), "4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45"),
    ])
    func keccakMatchesKnownVectors(input: Data, expectedHex: String) {
        let digest = DefaultWalletConnectorCryptoProvider().keccak256(input)
        #expect(digest.hexString == expectedHex)
    }

    @Test("Default public key recovery fails with actionable error")
    func defaultPublicKeyRecoveryFailsWithActionableError() throws {
        let signature = WalletEthereumSignature(v: 27, r: Array(repeating: 1, count: 32), s: Array(repeating: 2, count: 32))

        do {
            _ = try DefaultWalletConnectorCryptoProvider().recoverPublicKey(signature: signature, message: Data("message".utf8))
            Issue.record("Expected public key recovery to throw")
        } catch let error as WalletConnectionError {
            #expect(error.errorDescription?.contains("Ethereum public key recovery is not configured") == true)
        }
    }
}

private actor RecordingWalletOpener: WalletApplicationOpening {
    private let canOpen: Bool
    private let openResult: Bool
    private var opened: [URL] = []

    init(canOpen: Bool, openResult: Bool) {
        self.canOpen = canOpen
        self.openResult = openResult
    }

    func canOpenURL(_ url: URL) -> Bool {
        canOpen
    }

    func open(_ url: URL) -> Bool {
        opened.append(url)
        return openResult
    }

    func openedURLs() -> [URL] {
        opened
    }
}

private actor FakeWalletTransport: WalletTransportClient {
    private var requests: [WalletPairingRequest] = []

    func createPairing(request: WalletPairingRequest) throws -> WalletPairing {
        requests.append(request)
        let uri = WalletConnectURI(topic: "topic-1", symKey: "abc123", expiryTimestamp: 1_800_000_000)
        return WalletPairing(
            topic: "topic-1",
            providerID: request.providerID,
            uri: uri.absoluteString,
            expiryDate: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    func disconnect(topic: WalletPairingTopic) throws {}
    func publish(_ request: WalletRequest, topic: WalletPairingTopic) throws {}
    func sessions() throws -> [WalletSession] { [] }
    nonisolated func events() -> AsyncStream<WalletTransportEvent> { AsyncStream { $0.finish() } }

    func pairingRequests() -> [WalletPairingRequest] {
        requests
    }
}

private actor RecordingRelayTask: WalletConnectRelayTask {
    private var sent: [String] = []
    private var receiveMessages: [String]

    init(receiveMessages: [String] = []) {
        self.receiveMessages = receiveMessages
    }

    func send(_ string: String) {
        sent.append(string)
    }

    func receive() throws -> String {
        guard !receiveMessages.isEmpty else {
            throw WalletConnectionError.relayDisconnected
        }
        return receiveMessages.removeFirst()
    }

    func close() {}

    func sentMessages() -> [String] {
        sent
    }
}

private struct FixedRelayTaskFactory: WalletConnectRelayTaskFactory {
    let task: RecordingRelayTask

    func makeTask(url: URL) async throws -> any WalletConnectRelayTask {
        task
    }
}

private actor FakeSessionWalletConnector: WalletConnector {
    private let storedSessions: [WalletConnectorSession]
    private var disconnected: [WalletSessionID] = []

    init(sessions: [WalletConnectorSession]) {
        self.storedSessions = sessions
    }

    nonisolated var events: AsyncStream<WalletConnectorEvent> {
        AsyncStream { $0.finish() }
    }

    func connect(proposal: WalletNamespaceProposalSet, wallet: ThirdPartyWalletProvider?) throws -> WalletConnectionStart {
        WalletConnectionStart(
            pairingURI: WalletConnectURI(topic: "topic-1", symKey: "abc123", expiryTimestamp: 1_800_000_000),
            qrPayload: "wc:topic-1@2"
        )
    }

    func handleCallback(url: URL) {}

    func sessions() -> [WalletConnectorSession] {
        storedSessions
    }

    func disconnect(sessionId: WalletSessionID) {
        disconnected.append(sessionId)
    }

    func request(_ request: WalletRequest, in sessionId: WalletSessionID) throws -> WalletResponse {
        throw WalletConnectionError.requestTimedOut(request.id)
    }

    func disconnectedSessionIDs() -> [WalletSessionID] {
        disconnected
    }
}

private actor RecordingWalletAccountStore: WalletAccountPersisting {
    private let fallbackAddress: String?
    private var upsertedAddresses: [WalletSessionAddress] = []
    private var deactivatedAddresses: [(address: String, chain: WalletChain)] = []

    init(fallbackAddress: String? = nil) {
        self.fallbackAddress = fallbackAddress
    }

    func upsert(_ walletAddress: WalletSessionAddress, selectedAt: Date) {
        upsertedAddresses.append(walletAddress)
    }

    func deactivate(address: String, chain: WalletChain, at date: Date) {
        deactivatedAddresses.append((address, chain))
    }

    func mostRecentlyUsedActiveAddress(excluding address: String?) -> String? {
        fallbackAddress
    }

    func upserted() -> [WalletSessionAddress] {
        upsertedAddresses
    }

    func deactivated() -> [(address: String, chain: WalletChain)] {
        deactivatedAddresses
    }
}

private actor RecordingWalletMetadataResolver: WalletPostConnectionResolving {
    private var addresses: [WalletSessionAddress] = []

    func refreshMetadata(for walletAddress: WalletSessionAddress) {
        addresses.append(walletAddress)
    }

    func refreshed() -> [WalletSessionAddress] {
        addresses
    }
}

private actor RecordingWalletRemovalCleaner: WalletRemovalCleaning {
    private var addresses: [String] = []

    func cleanLocalData(for address: String) {
        addresses.append(address)
    }

    func cleanedAddresses() -> [String] {
        addresses
    }
}

private func assertRoundTrip<Value: Codable & Equatable>(_ value: Value) throws {
    let data = try JSONEncoder.walletConnectorTest.encode(value)
    let decoded = try JSONDecoder.walletConnectorTest.decode(Value.self, from: data)
    #expect(decoded == value)
}

private extension JSONEncoder {
    static var walletConnectorTest: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var walletConnectorTest: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension Date {
    static let sampleDate = Date(timeIntervalSince1970: 1_800_000_000)
}

private extension WalletConnectorSession {
    static let sampleSession = WalletConnectorSession(
        id: "topic-1",
        topic: "topic-1",
        providerID: "metamask",
        providerName: "MetaMask",
        accounts: [WalletAccount(caip10: "eip155:1:0x0000000000000000000000000000000000000000")],
        namespaces: [
            WalletSessionNamespace(
                name: "eip155",
                accounts: [WalletAccount(caip10: "eip155:1:0x0000000000000000000000000000000000000000")],
                methods: ["personal_sign"],
                events: ["accountsChanged"]
            ),
        ],
        expiryDate: .sampleDate
    )

    static let multiAccountSession = WalletConnectorSession(
        id: "topic-1",
        topic: "topic-1",
        providerID: "generic",
        providerName: "Generic Wallet",
        accounts: [
            WalletAccount(caip10: "eip155:1:0x0000000000000000000000000000000000000000"),
            WalletAccount(caip10: "solana:mainnet:11111111111111111111111111111111"),
        ],
        namespaces: [],
        expiryDate: .sampleDate
    )
}

private extension WalletConnectionMetadata {
    static let testValue = WalletConnectionMetadata(
        appName: "Auralis",
        appDescription: "Auralis wallet connection",
        appURL: URL(string: "https://auralis.example")!,
        redirect: WalletConnectionRedirect(native: "auralis-wcdemo://")
    )
}

private extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
