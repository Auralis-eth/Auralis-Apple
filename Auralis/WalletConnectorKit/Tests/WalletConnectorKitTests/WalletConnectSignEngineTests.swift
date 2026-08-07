import CryptoKit
import Foundation
import Testing
@testable import WalletConnectorKit

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
        let transport = WalletConnectIRNTransportClient(relayClient: relay)

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
}

private actor EventCollector {
    private var events: [WalletTransportEvent] = []
    private var settledWaiter: CheckedContinuation<WalletSession, Error>?

    func add(_ event: WalletTransportEvent) {
        events.append(event)
        if case .sessionApproved(let session) = event, let waiter = settledWaiter {
            settledWaiter = nil
            waiter.resume(returning: session)
        }
    }

    func waitForSettled(timeout: Duration = .seconds(5)) async throws -> WalletSession {
        for event in events {
            if case .sessionApproved(let session) = event { return session }
        }
        return try await withThrowingTaskGroup(of: WalletSession.self) { group in
            group.addTask { try await self.awaitSettled() }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw WalletConnectionError.requestTimedOut("settle")
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private func awaitSettled() async throws -> WalletSession {
        try await withCheckedThrowingContinuation { settledWaiter = $0 }
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

    init(address: String) { self.account = address }

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
            enqueueAck(id: id)
            if let topic = params["topic"] as? String, topic == sessionTopic, let settle = pendingSettle {
                pendingSettle = nil
                enqueue(settle.message)
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
                "namespaces": ["eip155": ["accounts": [account], "methods": ["personal_sign"], "events": ["chainChanged"]]],
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
