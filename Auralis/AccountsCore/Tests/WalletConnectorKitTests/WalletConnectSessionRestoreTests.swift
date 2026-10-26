import CryptoKit
import Foundation
import Testing
@testable import WalletConnectorKit

/// Covers cross-launch restoration of the custom WalletConnect v2 transport:
/// persisted protocol state (session key, self key, metadata) is rehydrated and
/// re-subscribed on first use, and expired records are pruned instead of being
/// resurrected.
@Suite("WalletConnect session restoration")
struct WalletConnectSessionRestoreTests {
    // MARK: - Store round-trip

    @Test("In-memory session-state store round-trips and deletes")
    func inMemoryStoreRoundTrip() async throws {
        let store = InMemoryWalletConnectSessionStateStore()
        let record = Self.makeRecord(topic: "session-topic-1", expiry: Date().addingTimeInterval(3600))
        try await store.save(record)

        let loaded = await store.loadAll()
        #expect(loaded == [record])

        try await store.delete(sessionTopic: "session-topic-1")
        #expect(await store.loadAll().isEmpty)
    }

    // MARK: - Transport restore

    @Test("Transport restores a persisted session and re-subscribes its topic")
    func transportRestoresPersistedSession() async throws {
        let sessionTopic = "restored-session-topic"
        let record = Self.makeRecord(topic: sessionTopic, expiry: Date().addingTimeInterval(3600))
        let store = InMemoryWalletConnectSessionStateStore(sessions: [record])

        let relayTask = AckingRelayTask()
        let relay = WalletConnectIRNRelayClient(
            configuration: WalletConnectRelayConfiguration(projectID: "test-project"),
            taskFactory: SingleRelayTaskFactory(task: relayTask),
            authProvider: nil
        )
        let transport = WalletConnectIRNTransportClient(relayClient: relay, stateStore: store)

        let sessions = try await transport.sessions()
        #expect(sessions.count == 1)
        #expect(sessions.first?.topic.rawValue == sessionTopic)
        #expect(sessions.first?.accounts.first?.caip10 == "eip155:1:0xAbc0000000000000000000000000000000000001")

        // The restored topic is re-subscribed asynchronously (best-effort, so an
        // offline launch does not block enumeration); poll until it lands.
        var subscribed = false
        for _ in 0..<50 where !subscribed {
            if await relayTask.subscribedTopics.contains(sessionTopic) {
                subscribed = true
            } else {
                try await Task.sleep(for: .milliseconds(20))
            }
        }
        #expect(subscribed)
    }

    @Test("Transport propagates unreadable persisted state on first-use restore")
    func transportPropagatesUnreadablePersistedState() async throws {
        let store = ThrowingWalletConnectSessionStateStore(error: WalletConnectSessionStateStoreError.unreadable(errSecInteractionNotAllowed))
        let relay = WalletConnectIRNRelayClient(
            configuration: WalletConnectRelayConfiguration(projectID: "test-project"),
            taskFactory: SingleRelayTaskFactory(task: AckingRelayTask()),
            authProvider: nil
        )
        let transport = WalletConnectIRNTransportClient(relayClient: relay, stateStore: store)

        await #expect(throws: WalletConnectSessionStateStoreError.self) {
            _ = try await transport.sessions()
        }
        await #expect(throws: WalletConnectSessionStateStoreError.self) {
            _ = try await transport.createPairing(
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
        }
    }

    @Test("Transport still enumerates a persisted session when relay re-subscription fails")
    func transportEnumeratesSessionWhenRelayRecoveryFails() async throws {
        let sessionTopic = "restored-session-topic"
        let record = Self.makeRecord(topic: sessionTopic, expiry: Date().addingTimeInterval(3600))
        let store = InMemoryWalletConnectSessionStateStore(sessions: [record])
        let relay = WalletConnectIRNRelayClient(
            configuration: WalletConnectRelayConfiguration(projectID: "test-project"),
            taskFactory: SingleRelayTaskFactory(task: AckingRelayTask(rejectSubscribe: true)),
            authProvider: nil
        )
        let transport = WalletConnectIRNTransportClient(relayClient: relay, stateStore: store)

        // Rehydration is decoupled from re-subscription: even when the relay
        // rejects subscribe (offline / relay blip), the persisted session is still
        // enumerable and its record is retained rather than destructively pruned.
        let sessions = try await transport.sessions()
        #expect(sessions.count == 1)
        #expect(sessions.first?.topic.rawValue == sessionTopic)
        #expect(try await store.loadAll() == [record])
    }

    @Test("Transport fails restore closed for malformed persisted symmetric key")
    func transportFailsRestoreClosedForMalformedSymmetricKey() async throws {
        let record = Self.makeRecord(
            topic: "malformed-symkey-topic",
            expiry: Date().addingTimeInterval(3600),
            sessionSymmetricKeyHex: "0x1234"
        )
        let store = InMemoryWalletConnectSessionStateStore(sessions: [record])
        let relay = WalletConnectIRNRelayClient(
            configuration: WalletConnectRelayConfiguration(projectID: "test-project"),
            taskFactory: SingleRelayTaskFactory(task: AckingRelayTask()),
            authProvider: nil
        )
        let transport = WalletConnectIRNTransportClient(relayClient: relay, stateStore: store)

        await #expect(throws: WalletConnectionError.self) {
            _ = try await transport.sessions()
        }
        #expect(try await store.loadAll() == [record])
    }

    @Test("Transport fails restore closed for malformed persisted self key")
    func transportFailsRestoreClosedForMalformedSelfKey() async throws {
        let record = Self.makeRecord(
            topic: "malformed-selfkey-topic",
            expiry: Date().addingTimeInterval(3600),
            selfPrivateKeyHex: "not-hex"
        )
        let store = InMemoryWalletConnectSessionStateStore(sessions: [record])
        let relay = WalletConnectIRNRelayClient(
            configuration: WalletConnectRelayConfiguration(projectID: "test-project"),
            taskFactory: SingleRelayTaskFactory(task: AckingRelayTask()),
            authProvider: nil
        )
        let transport = WalletConnectIRNTransportClient(relayClient: relay, stateStore: store)

        await #expect(throws: WalletConnectionError.self) {
            _ = try await transport.sessions()
        }
        #expect(try await store.loadAll() == [record])
    }

    @Test("Transport prunes an expired persisted session on restore")
    func transportPrunesExpiredSession() async throws {
        let record = Self.makeRecord(topic: "expired-topic", expiry: Date().addingTimeInterval(-60))
        let store = InMemoryWalletConnectSessionStateStore(sessions: [record])

        let relay = WalletConnectIRNRelayClient(
            configuration: WalletConnectRelayConfiguration(projectID: "test-project"),
            taskFactory: SingleRelayTaskFactory(task: AckingRelayTask()),
            authProvider: nil
        )
        let transport = WalletConnectIRNTransportClient(relayClient: relay, stateStore: store)

        #expect(try await transport.sessions().isEmpty)
        // The expired record is removed from the store, not left to rot.
        #expect(await store.loadAll().isEmpty)
    }

    // MARK: - Helpers

    private static func makeRecord(
        topic: String,
        expiry: Date,
        sessionSymmetricKeyHex: String? = nil,
        selfPrivateKeyHex: String? = nil
    ) -> WalletConnectPersistedSession {
        let selfKey = Curve25519.KeyAgreement.PrivateKey()
        let symKey = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })
        return WalletConnectPersistedSession(
            sessionTopic: topic,
            pairingTopic: "pairing-\(topic)",
            sessionSymmetricKeyHex: sessionSymmetricKeyHex ?? WalletConnectV2Crypto.hexString(symKey),
            selfPrivateKeyHex: selfPrivateKeyHex ?? WalletConnectV2Crypto.hexString(selfKey.rawRepresentation),
            providerID: "mock",
            providerName: "MockWallet",
            accounts: [WalletAccount(caip10: "eip155:1:0xAbc0000000000000000000000000000000000001")],
            namespaces: [
                WalletSessionNamespace(
                    name: "eip155",
                    accounts: [WalletAccount(caip10: "eip155:1:0xAbc0000000000000000000000000000000000001")],
                    methods: ["personal_sign"],
                    events: ["chainChanged"]
                )
            ],
            connectedAt: Date().addingTimeInterval(-30),
            expiryDate: expiry
        )
    }
}

private actor ThrowingWalletConnectSessionStateStore: WalletConnectSessionStatePersisting {
    private let error: Error

    init(error: Error) {
        self.error = error
    }

    func save(_ session: WalletConnectPersistedSession) throws {}
    func loadAll() throws -> [WalletConnectPersistedSession] { throw error }
    func delete(sessionTopic: String) throws {}
}

private struct SingleRelayTaskFactory: WalletConnectRelayTaskFactory {
    let task: AckingRelayTask
    func makeTask(url: URL) async throws -> any WalletConnectRelayTask { task }
}

/// A relay stand-in that acknowledges every JSON-RPC request and records the
/// topics it was asked to subscribe to.
private actor AckingRelayTask: WalletConnectRelayTask {
    private(set) var subscribedTopics: Set<String> = []
    private let rejectSubscribe: Bool
    private var outbox: [String] = []
    private var waiters: [CheckedContinuation<String, Error>] = []

    init(rejectSubscribe: Bool = false) {
        self.rejectSubscribe = rejectSubscribe
    }

    func send(_ string: String) async throws {
        guard let data = string.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let method = json["method"] as? String else { return }
        let id = json["id"] as? Int ?? 0
        let result: Any
        if method == "irn_subscribe", let topic = (json["params"] as? [String: Any])?["topic"] as? String {
            if rejectSubscribe {
                let ack: [String: Any] = ["id": id, "jsonrpc": "2.0", "error": ["code": -32000, "message": "subscribe rejected"]]
                if let ackData = try? JSONSerialization.data(withJSONObject: ack),
                   let ackString = String(data: ackData, encoding: .utf8) {
                    enqueue(ackString)
                }
                return
            }
            subscribedTopics.insert(topic)
            result = "subscription-\(topic)"
        } else if method == "irn_fetchMessages" {
            result = ["messages": [], "hasMore": false]
        } else {
            result = true
        }
        let ack: [String: Any] = ["id": id, "jsonrpc": "2.0", "result": result]
        if let ackData = try? JSONSerialization.data(withJSONObject: ack),
           let ackString = String(data: ackData, encoding: .utf8) {
            enqueue(ackString)
        }
    }

    func receive() async throws -> String {
        if !outbox.isEmpty { return outbox.removeFirst() }
        return try await withCheckedThrowingContinuation { waiters.append($0) }
    }

    func close() async {}

    private func enqueue(_ string: String) {
        if !waiters.isEmpty {
            waiters.removeFirst().resume(returning: string)
        } else {
            outbox.append(string)
        }
    }
}
