@testable import Auralis
import AuralisPrimaryModels
import AuralisPrimaryPersistence
import Foundation
import SwiftData
import Testing
import WalletConnectorKit

/// P4-007 interaction coverage for the wallet picker.
///
/// The picker (`WalletPickerSheet`) drives every user action through
/// `AuralisWalletConnectionService`, so these tests exercise that service at its
/// public seam — the same calls the SwiftUI buttons make: "Connect" ->
/// `connect(with:)`, an approved session -> persistence, and swipe-to-remove ->
/// `remove(account:)`. They use an in-memory SwiftData store plus the kit's
/// in-memory session/active stores and a recording connector, so no relay,
/// Keychain, or `UserDefaults` is touched. Image snapshot coverage lives with
/// the app target's rendering host, not here.
@MainActor
struct WalletConnectionInteractionTests {
    private static let addressA = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    private static let addressB = "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

    // MARK: Connect

    @Test("Tapping Connect calls the connector once and surfaces the pairing payload")
    func connectInvokesConnectorAndSurfacesPairing() async throws {
        let harness = try makeHarness()

        await harness.service.connect(with: WalletConnectorCatalog.metamask)

        #expect(harness.connector.connectCount == 1)
        #expect(harness.connector.lastProviderID == "metamask")
        #expect(harness.service.latestPairingPayload != nil)
        #expect(isAwaitingApproval(harness.service))
    }

    // MARK: Approval persistence (Scenario A)

    @Test("An approved EVM session persists one wallet account and marks it active")
    func settledSessionPersistsWalletAndSetsActive() async throws {
        let harness = try makeHarness()

        harness.connector.settle(session(topic: "topic-A", accounts: [caip10(Self.addressA)]))
        await waitUntil { await harness.topics.load(walletAddress: Self.addressA) != nil }

        let accounts = try harness.context.fetch(FetchDescriptor<EOAccount>())
        #expect(accounts.count == 1)
        let account = try #require(accounts.first)
        #expect(account.address == Self.addressA)
        #expect(account.access == .wallet)
        #expect(account.source == .walletConnect)
        #expect(await harness.topics.load(walletAddress: Self.addressA)?.rawValue == "topic-A")
        #expect(harness.active.get() == Self.addressA)
        #expect(isConnected(harness.service))
    }

    // MARK: Add another wallet (Scenario G)

    @Test("Adding a second wallet keeps both and makes the newest one active")
    func addingSecondWalletSwitchesActive() async throws {
        let harness = try makeHarness()

        harness.connector.settle(session(topic: "topic-A", accounts: [caip10(Self.addressA)]))
        await waitUntil { harness.active.get() == Self.addressA }

        harness.connector.settle(session(id: "session-B", topic: "topic-B", accounts: [caip10(Self.addressB)]))
        await waitUntil { harness.active.get() == Self.addressB }

        let accounts = try harness.context.fetch(FetchDescriptor<EOAccount>())
        #expect(Set(accounts.map(\.address)) == [Self.addressA, Self.addressB])
        #expect(harness.active.get() == Self.addressB)
    }

    // MARK: Duplicate connect (Scenario I)

    @Test("Reconnecting the same address updates the topic without duplicating the row")
    func duplicateConnectDoesNotDuplicateRow() async throws {
        let harness = try makeHarness()

        harness.connector.settle(session(id: "session-A1", topic: "topic-A1", accounts: [caip10(Self.addressA)]))
        await waitUntil { await harness.topics.load(walletAddress: Self.addressA)?.rawValue == "topic-A1" }

        harness.connector.settle(session(id: "session-A2", topic: "topic-A2", accounts: [caip10(Self.addressA)]))
        await waitUntil { await harness.topics.load(walletAddress: Self.addressA)?.rawValue == "topic-A2" }

        let accounts = try harness.context.fetch(FetchDescriptor<EOAccount>())
        #expect(accounts.count == 1)
    }

    // MARK: Swipe-to-remove (Scenario H)

    @Test("Removing the active wallet disconnects it and falls back to the remaining wallet")
    func removeActiveWalletFallsBackToRemaining() async throws {
        let harness = try makeHarness()

        harness.connector.settle(session(topic: "topic-A", accounts: [caip10(Self.addressA)]))
        await waitUntil { harness.active.get() == Self.addressA }
        harness.connector.settle(session(id: "session-B", topic: "topic-B", accounts: [caip10(Self.addressB)]))
        await waitUntil { harness.active.get() == Self.addressB }

        harness.service.setActive(account: try account(for: Self.addressA, in: harness.context))
        #expect(harness.active.get() == Self.addressA)

        await harness.service.remove(account: try account(for: Self.addressA, in: harness.context))

        #expect(harness.connector.disconnectedTopics.contains("topic-A"))
        #expect(await harness.topics.load(walletAddress: Self.addressA) == nil)
        #expect(try account(for: Self.addressA, in: harness.context).access == .readonly)
        #expect(try account(for: Self.addressB, in: harness.context).access == .wallet)
        #expect(harness.active.get() == Self.addressB)
    }

    @Test("Removing the last wallet clears the active address")
    func removeLastWalletClearsActive() async throws {
        let harness = try makeHarness()

        harness.connector.settle(session(topic: "topic-A", accounts: [caip10(Self.addressA)]))
        await waitUntil { harness.active.get() == Self.addressA }

        await harness.service.remove(account: try account(for: Self.addressA, in: harness.context))

        #expect(harness.connector.disconnectedTopics.contains("topic-A"))
        #expect(await harness.topics.load(walletAddress: Self.addressA) == nil)
        #expect(try account(for: Self.addressA, in: harness.context).access == .readonly)
        #expect(harness.active.get() == nil)
    }

    // MARK: - Harness

    @MainActor
    private struct Harness {
        let container: ModelContainer
        let context: ModelContext
        let connector: RecordingWalletConnector
        let topics: InMemoryWalletSessionTopicStore
        let active: InMemoryActiveWalletStore
        let service: AuralisWalletConnectionService
    }

    private func makeHarness() throws -> Harness {
        let container = try TestModelContainers.primary()
        let context = container.mainContext
        let connector = RecordingWalletConnector(connectStart: Self.makeStart())
        let topics = InMemoryWalletSessionTopicStore()
        let active = InMemoryActiveWalletStore()
        let service = AuralisWalletConnectionService(
            connector: connector,
            accountAdapter: AuralisWalletAccountAdapter(modelContext: context),
            topicStore: topics,
            activeWalletStore: active
        )
        return Harness(
            container: container,
            context: context,
            connector: connector,
            topics: topics,
            active: active,
            service: service
        )
    }

    // MARK: - Fixtures

    private func caip10(_ address: String) -> String {
        "eip155:1:\(address)"
    }

    private func session(
        id: String = "session-A",
        topic: String,
        accounts: [String],
        providerID: String = "metamask",
        providerName: String = "MetaMask"
    ) -> WalletConnectorSession {
        WalletConnectorSession(
            id: WalletSessionID(rawValue: id),
            topic: WalletPairingTopic(rawValue: topic),
            providerID: providerID,
            providerName: providerName,
            accounts: accounts.map { WalletAccount(caip10: $0) },
            namespaces: [],
            expiryDate: Date().addingTimeInterval(3600)
        )
    }

    private func account(for address: String, in context: ModelContext) throws -> EOAccount {
        let matches = try context.fetch(
            FetchDescriptor<EOAccount>(predicate: #Predicate { $0.address == address })
        )
        return try #require(matches.first)
    }

    private static func makeStart() -> WalletConnectionStart {
        let uri = WalletConnectURI(
            topic: "pairing-topic",
            symKey: String(repeating: "a", count: 64),
            expiryTimestamp: Int64(Date().addingTimeInterval(300).timeIntervalSince1970)
        )
        return WalletConnectionStart(pairingURI: uri, walletOpenURL: nil, qrPayload: uri.absoluteString)
    }

    // MARK: - Async helpers

    private func isConnected(_ service: AuralisWalletConnectionService) -> Bool {
        if case .connected = service.phase { return true }
        return false
    }

    private func isAwaitingApproval(_ service: AuralisWalletConnectionService) -> Bool {
        if case .awaitingApproval = service.phase { return true }
        return false
    }

    /// Polls `condition` until it holds or the timeout elapses. The wallet flow
    /// settles asynchronously (event stream -> `@Observable` mutation), so the
    /// tests wait on a deterministic signal rather than a fixed sleep.
    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: @MainActor () async -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}

// MARK: - Recording connector

/// A `WalletConnector` that records `connect`/`disconnect` calls and lets a test
/// emit `sessionSettled` on demand, standing in for a live WalletConnect relay.
private final class RecordingWalletConnector: WalletConnector, @unchecked Sendable {
    let runtimeFamily: WalletConnectorRuntimeFamily = .customWalletConnectIRN

    private let lock = NSLock()
    private var _connectCount = 0
    private var _lastProviderID: String?
    private var _disconnectedTopics: [String] = []

    private let stream: AsyncStream<WalletConnectorEvent>
    private let continuation: AsyncStream<WalletConnectorEvent>.Continuation
    private let connectStart: WalletConnectionStart

    init(connectStart: WalletConnectionStart) {
        let made = AsyncStream<WalletConnectorEvent>.makeStream()
        self.stream = made.stream
        self.continuation = made.continuation
        self.connectStart = connectStart
    }

    var events: AsyncStream<WalletConnectorEvent> { stream }

    func connect(
        proposal: WalletNamespaceProposalSet,
        wallet: ThirdPartyWalletProvider?
    ) async throws -> WalletConnectionStart {
        lock.withLock {
            _connectCount += 1
            _lastProviderID = wallet?.id.rawValue
        }
        return connectStart
    }

    func handleCallback(url: URL) async throws {}

    func sessions() async throws -> [WalletConnectorSession] { [] }

    func disconnect(sessionId: WalletSessionID) async throws {
        lock.withLock { _disconnectedTopics.append(sessionId.rawValue) }
    }

    func request(_ request: WalletRequest, in sessionId: WalletSessionID) async throws -> WalletResponse {
        throw WalletConnectionError.unavailable("RecordingWalletConnector does not service requests.")
    }

    // Test controls

    func settle(_ session: WalletConnectorSession) {
        continuation.yield(.sessionSettled(session))
    }

    var connectCount: Int { lock.withLock { _connectCount } }
    var lastProviderID: String? { lock.withLock { _lastProviderID } }
    var disconnectedTopics: [String] { lock.withLock { _disconnectedTopics } }
}
