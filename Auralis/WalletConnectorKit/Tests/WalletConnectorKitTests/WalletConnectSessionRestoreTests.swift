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

        let loaded = try await store.loadAll()
        #expect(loaded == [record])

        try await store.delete(sessionTopic: "session-topic-1")
        #expect(try await store.loadAll().isEmpty)
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

        // The restored topic must be re-subscribed so inbound requests arrive.
        #expect(await relayTask.subscribedTopics.contains(sessionTopic))
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
        #expect(try await store.loadAll().isEmpty)
    }

    // MARK: - Helpers

    private static func makeRecord(topic: String, expiry: Date) -> WalletConnectPersistedSession {
        let selfKey = Curve25519.KeyAgreement.PrivateKey()
        let symKey = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })
        return WalletConnectPersistedSession(
            sessionTopic: topic,
            pairingTopic: "pairing-\(topic)",
            sessionSymmetricKeyHex: WalletConnectV2Crypto.hexString(symKey),
            selfPrivateKeyHex: WalletConnectV2Crypto.hexString(selfKey.rawRepresentation),
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

private struct SingleRelayTaskFactory: WalletConnectRelayTaskFactory {
    let task: AckingRelayTask
    func makeTask(url: URL) async throws -> any WalletConnectRelayTask { task }
}

/// A relay stand-in that acknowledges every JSON-RPC request and records the
/// topics it was asked to subscribe to.
private actor AckingRelayTask: WalletConnectRelayTask {
    private(set) var subscribedTopics: Set<String> = []
    private var outbox: [String] = []
    private var waiters: [CheckedContinuation<String, Error>] = []

    func send(_ string: String) async throws {
        guard let data = string.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let method = json["method"] as? String else { return }
        let id = json["id"] as? Int ?? 0
        if method == "irn_subscribe", let topic = (json["params"] as? [String: Any])?["topic"] as? String {
            subscribedTopics.insert(topic)
        }
        let ack: [String: Any] = ["id": id, "jsonrpc": "2.0", "result": true]
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
