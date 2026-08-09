import CryptoKit
import Foundation
import Testing
@testable import WalletConnectorKit

/// Regression coverage for the response-correlation hardening: a `wc_sessionRequest`
/// response is accepted only on the topic the request was published on, so a
/// response forged on another decryptable topic (e.g. the pairing topic, or a
/// second connected wallet's session) cannot resolve the request with an
/// attacker-controlled value. See `handleRequestResponse` topic binding.
@Suite("WalletConnect cross-session response injection")
struct WalletCrossSessionResponseTests {
    static let walletAddress = "0xAbc0000000000000000000000000000000000001"
    static let account = "eip155:1:\(walletAddress)"
    static let legitResult = "0xLEGIT"
    static let forgedResult = "0xFORGED"

    @Test("A response forged on a different topic is ignored; the legit response resolves")
    func forgedResponseOnOtherTopicIsRejected() async throws {
        let wallet = InjectingWalletRelay(account: Self.account)
        let relay = WalletConnectIRNRelayClient(
            configuration: WalletConnectRelayConfiguration(projectID: "test-project"),
            taskFactory: SingleTaskFactory(task: wallet),
            authProvider: nil
        )
        let transport = WalletConnectIRNTransportClient(relayClient: relay, stateStore: InMemoryWalletConnectSessionStateStore())

        let collector = ReSettleApprovalCollector()
        let events = transport.events()
        Task { for await event in events { await collector.add(event) } }

        // Settle a session.
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

        // Only issue the request once the session has actually settled (symmetric
        // key installed), then send it on the settled session's topic.
        let session = await collector.waitForApproval()
        let request = WalletRequest(
            id: WalletSignRequestID(rawValue: "req-1"),
            chain: WalletBlockchain(namespace: "eip155", reference: "1"),
            method: .ethPersonalSign,
            params: [.string("0xdeadbeef"), .string(Self.walletAddress)]
        )

        let response = try await transport.request(request, topic: session.topic)

        // The forged response (pushed first, on the pairing topic) must have been
        // dropped; only the legit response on the session topic resolves.
        #expect(response.result == Self.legitResult)
    }

    @Test("A second settle for an already-live session does not swap its accounts")
    func reSettleDoesNotOverwriteAccounts() async throws {
        let otherAccount = "eip155:1:0xBad0000000000000000000000000000000000002"
        let wallet = InjectingWalletRelay(account: Self.account, reSettleAccount: otherAccount)
        let relay = WalletConnectIRNRelayClient(
            configuration: WalletConnectRelayConfiguration(projectID: "test-project"),
            taskFactory: SingleTaskFactory(task: wallet),
            authProvider: nil
        )
        let transport = WalletConnectIRNTransportClient(relayClient: relay, stateStore: InMemoryWalletConnectSessionStateStore())

        let collector = ReSettleApprovalCollector()
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

        _ = await collector.waitForApproval()
        // Give the second settle time to be received and (correctly) ignored.
        try await Task.sleep(for: .milliseconds(250))

        #expect(await collector.approvalCount() == 1)
        let sessions = try await transport.sessions()
        #expect(sessions.count == 1)
        let addresses = sessions.first?.accounts.map(\.caip10) ?? []
        #expect(addresses == [Self.account])
        #expect(!addresses.contains(otherAccount))
    }
}

private actor ReSettleApprovalCollector {
    private var approvals: [WalletSession] = []
    private var waiter: CheckedContinuation<WalletSession, Never>?

    func add(_ event: WalletTransportEvent) {
        if case .sessionApproved(let session) = event {
            approvals.append(session)
            waiter?.resume(returning: session)
            waiter = nil
        }
    }

    func waitForApproval() async -> WalletSession {
        if let first = approvals.first { return first }
        return await withCheckedContinuation { waiter = $0 }
    }

    func approvalCount() -> Int { approvals.count }
}

private struct SingleTaskFactory: WalletConnectRelayTaskFactory {
    let task: InjectingWalletRelay
    func makeTask(url: URL) async throws -> any WalletConnectRelayTask { task }
}

/// Mock relay+wallet that settles a session and, on the first `wc_sessionRequest`,
/// first pushes a FORGED response on the pairing topic (a topic the transport can
/// still decrypt) and then the genuine response on the session topic.
private actor InjectingWalletRelay: WalletConnectRelayTask {
    private let account: String
    private let reSettleAccount: String?
    private let walletKey = WalletConnectV2Crypto.generateKeyPair()

    private var outbox: [String] = []
    private var waiters: [CheckedContinuation<String, Error>] = []

    private var pairingTopic: String?
    private var pairingSymKey: Data?
    private var bufferedPropose: String?
    private var sessionSymKey: Data?
    private var sessionTopic: String?
    private var pendingSettle: (topic: String, message: String)?
    private var pendingReSettle: (topic: String, message: String)?

    init(account: String, reSettleAccount: String? = nil) {
        self.account = account
        self.reSettleAccount = reSettleAccount
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
            enqueueAck(id: id, result: "subscription-\(params["topic"] as? String ?? "unknown")")
            if let topic = params["topic"] as? String, topic == sessionTopic, let settle = pendingSettle {
                pendingSettle = nil
                enqueue(settle.message)
                if let reSettle = pendingReSettle {
                    pendingReSettle = nil
                    enqueue(reSettle.message)
                }
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
            handleSessionRequest(message)
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

        if let push = settlePush(account: account, id: Int(Date().timeIntervalSince1970 * 1000), topic: sessionTopic, symKey: sessionSymKey) {
            pendingSettle = (sessionTopic, push)
        }
        if let reSettleAccount,
           let push = settlePush(account: reSettleAccount, id: Int(Date().timeIntervalSince1970 * 1000) + 1, topic: sessionTopic, symKey: sessionSymKey) {
            pendingReSettle = (sessionTopic, push)
        }
    }

    private func settlePush(account: String, id: Int, topic: String, symKey: Data) -> String? {
        let settle: [String: Any] = [
            "id": id,
            "jsonrpc": "2.0",
            "method": "wc_sessionSettle",
            "params": [
                "relay": ["protocol": "irn"],
                "controller": ["publicKey": walletKey.publicKeyHex, "metadata": ["name": "MockWallet", "description": "m", "url": "https://mock", "icons": []]],
                "namespaces": ["eip155": ["accounts": [account], "methods": ["personal_sign"], "events": ["chainChanged"]]],
                "expiry": Int(Date().addingTimeInterval(3600).timeIntervalSince1970),
            ],
        ]
        return encryptedPush(json: settle, topic: topic, tag: WalletConnectSignTag.sessionSettle, symKey: symKey)
    }

    private func handleSessionRequest(_ message: String) {
        guard let sessionSymKey, let sessionTopic, let pairingSymKey, let pairingTopic,
              let envelope = try? WalletConnectEnvelope(base64Encoded: message),
              let plaintext = try? WalletConnectV2Crypto.open(sealbox: envelope.sealbox, symKey: sessionSymKey),
              let rpc = try? JSONSerialization.jsonObject(with: plaintext) as? [String: Any],
              let requestID = rpc["id"] as? Int else { return }

        // Attacker-controlled response forged on the pairing topic (which the
        // transport can still decrypt) — must be ignored.
        let forged: [String: Any] = ["id": requestID, "jsonrpc": "2.0", "result": WalletCrossSessionResponseTests.forgedResult]
        if let push = encryptedPush(json: forged, topic: pairingTopic, tag: WalletConnectSignTag.sessionRequestResponse, symKey: pairingSymKey) {
            enqueue(push)
        }
        // Genuine response on the session topic — must resolve the request.
        let legit: [String: Any] = ["id": requestID, "jsonrpc": "2.0", "result": WalletCrossSessionResponseTests.legitResult]
        if let push = encryptedPush(json: legit, topic: sessionTopic, tag: WalletConnectSignTag.sessionRequestResponse, symKey: sessionSymKey) {
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
