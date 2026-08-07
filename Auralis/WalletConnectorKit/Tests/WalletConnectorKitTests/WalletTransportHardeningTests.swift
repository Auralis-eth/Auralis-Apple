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

    // MARK: - #5 nextID uniqueness

    @Test("Generating >1000 ids at a fixed timestamp yields all-distinct values")
    func nextIDsAreDistinctWithinSameMillisecond() async throws {
        let fixed = Date(timeIntervalSince1970: 1_800_000_000)
        let relay = WalletConnectIRNRelayClient(
            configuration: WalletConnectRelayConfiguration(projectID: "test-project"),
            taskFactory: MockTaskFactory(task: ScriptableWalletRelay(account: Self.account)),
            authProvider: nil
        )
        let transport = WalletConnectIRNTransportClient(relayClient: relay, now: { fixed })

        var ids = Set<Int64>()
        for _ in 0..<5000 {
            let id = await transport.nextID()
            ids.insert(id)
            #expect(id > 0)
        }
        #expect(ids.count == 5000)
    }

    // MARK: - Helpers

    private static func makeTransport(wallet: ScriptableWalletRelay) async throws -> WalletConnectIRNTransportClient {
        let relay = WalletConnectIRNRelayClient(
            configuration: WalletConnectRelayConfiguration(projectID: "test-project"),
            taskFactory: MockTaskFactory(task: wallet),
            authProvider: nil
        )
        return WalletConnectIRNTransportClient(relayClient: relay)
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

private actor ApprovalCollector {
    private var approvals: [WalletSession] = []
    private var rejections: [WalletConnectionError] = []
    private var waiter: CheckedContinuation<WalletSession, Never>?

    func add(_ event: WalletTransportEvent) {
        switch event {
        case .sessionApproved(let session):
            approvals.append(session)
            waiter?.resume(returning: session)
            waiter = nil
        case .sessionRejected(_, let error):
            rejections.append(error)
        default:
            break
        }
    }

    func waitForApproval() async -> WalletSession {
        if let first = approvals.first { return first }
        return await withCheckedContinuation { waiter = $0 }
    }

    func approvalCount() -> Int { approvals.count }
    func rejectionCount() -> Int { rejections.count }
}

private struct MockTaskFactory: WalletConnectRelayTaskFactory {
    let task: ScriptableWalletRelay
    func makeTask(url: URL) async throws -> any WalletConnectRelayTask { task }
}

/// Single-socket mock behaving as both relay and wallet, with knobs for the
/// settle expiry and for redelivering the settle message.
private actor ScriptableWalletRelay: WalletConnectRelayTask {
    private let account: String
    private let settleExpiry: Date
    private let redeliverSettle: Bool
    private let walletKey = WalletConnectV2Crypto.generateKeyPair()

    private var outbox: [String] = []
    private var waiters: [CheckedContinuation<String, Error>] = []

    private var pairingTopic: String?
    private var pairingSymKey: Data?
    private var bufferedPropose: String?
    private var sessionSymKey: Data?
    private var sessionTopic: String?
    private var pendingSettle: (topic: String, message: String)?

    init(account: String, settleExpiry: Date = Date().addingTimeInterval(3600), redeliverSettle: Bool = false) {
        self.account = account
        self.settleExpiry = settleExpiry
        self.redeliverSettle = redeliverSettle
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
        guard let method = json["method"] as? String else { return }
        let id = json["id"] as? Int ?? 0
        let params = json["params"] as? [String: Any] ?? [:]

        switch method {
        case "irn_subscribe":
            enqueueAck(id: id)
            if let topic = params["topic"] as? String, topic == sessionTopic, let settle = pendingSettle {
                pendingSettle = nil
                enqueue(settle.message)
                if redeliverSettle {
                    // Simulate relay redelivery of the identical encrypted settle.
                    enqueue(settle.message)
                }
            }
        case "irn_publish":
            enqueueAck(id: id)
            handlePublished(params: params)
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
                "namespaces": ["eip155": ["accounts": [account], "methods": ["personal_sign"], "events": ["chainChanged"]]],
                "expiry": Int(settleExpiry.timeIntervalSince1970),
            ],
        ]
        if let push = encryptedPush(json: settle, topic: sessionTopic, tag: WalletConnectSignTag.sessionSettle, symKey: sessionSymKey) {
            pendingSettle = (sessionTopic, push)
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

    private func enqueueAck(id: Int) {
        let ack: [String: Any] = ["id": id, "jsonrpc": "2.0", "result": true]
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
