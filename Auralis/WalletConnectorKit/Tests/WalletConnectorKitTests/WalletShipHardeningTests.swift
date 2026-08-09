import Foundation
import Testing
@testable import WalletConnectorKit

@Suite("Ship hardening fixes")
struct WalletShipHardeningTests {
    // MARK: - H1: relay connect() coalescing

    private actor CallCounter {
        private(set) var count = 0
        func increment() { count += 1 }
    }

    private final class CountingRelayTaskFactory: WalletConnectRelayTaskFactory, @unchecked Sendable {
        let counter = CallCounter()

        func makeTask(url: URL) async throws -> any WalletConnectRelayTask {
            await counter.increment()
            // Hold the reentrancy window open so a second concurrent connect()
            // overlaps this one.
            try? await Task.sleep(for: .milliseconds(50))
            return BlockingRelayTask()
        }
    }

    private final class BlockingRelayTask: WalletConnectRelayTask, @unchecked Sendable {
        func send(_ string: String) async throws {}
        func receive() async throws -> String {
            try await Task.sleep(for: .seconds(30))
            throw WalletConnectionError.relayDisconnected
        }
        func close() async {}
    }

    @Test("Concurrent connect() calls open exactly one socket")
    func concurrentConnectOpensOneSocket() async throws {
        let factory = CountingRelayTaskFactory()
        let relay = WalletConnectIRNRelayClient(
            configuration: WalletConnectRelayConfiguration(projectID: "project"),
            taskFactory: factory,
            authProvider: nil
        )

        async let first: Void = relay.connect()
        async let second: Void = relay.connect()
        _ = try await (first, second)

        #expect(await factory.counter.count == 1)
        await relay.disconnect()
    }

    // MARK: - M1: personal_sign encoding

    @Test("personalSignText hex-encodes the UTF-8 message")
    func personalSignTextHexEncodes() {
        let request = WalletRequestBuilder.personalSignText(id: "1", address: "0xabc", text: "Hello")
        #expect(request.params.first == .string("0x48656c6c6f"))
        #expect(request.params.last == .string("0xabc"))
    }

    // MARK: - H2: signature parsing + ownership fail-closed

    @Test("WalletEthereumSignature parses r/s/v and normalizes v")
    func signatureParsesAndNormalizes() {
        let hex = "0x" + String(repeating: "11", count: 32) + String(repeating: "22", count: 32) + "00"
        let signature = WalletEthereumSignature(hexSignature: hex)
        #expect(signature?.r.count == 32)
        #expect(signature?.s.count == 32)
        #expect(signature?.v == 27) // 0 recovery id normalized to 27
        #expect(WalletEthereumSignature(hexSignature: "0x1234") == nil)
    }

    private final class NoopTransport: WalletTransportClient, @unchecked Sendable {
        func createPairing(request: WalletPairingRequest) async throws -> WalletPairing {
            throw WalletConnectionError.unavailable("noop")
        }
        func disconnect(topic: WalletPairingTopic) async throws {}
        func request(_ request: WalletRequest, topic: WalletPairingTopic) async throws -> WalletResponse {
            throw WalletConnectionError.unavailable("noop")
        }
        func sessions() async throws -> [WalletSession] { [] }
        func events() -> AsyncStream<WalletTransportEvent> { AsyncStream { _ in } }
    }

    private actor RecordingPairingTransport: WalletTransportClient {
        private var lastPairingRequest: WalletPairingRequest?

        func createPairing(request: WalletPairingRequest) async throws -> WalletPairing {
            lastPairingRequest = request
            return WalletPairing(
                topic: WalletPairingTopic(rawValue: String(repeating: "a", count: 64)),
                providerID: request.providerID,
                uri: "wc:\(String(repeating: "a", count: 64))@2?relay-protocol=irn&symKey=\(String(repeating: "b", count: 64))",
                expiryDate: Date().addingTimeInterval(300)
            )
        }

        func recordedPairingRequest() -> WalletPairingRequest? { lastPairingRequest }
        func disconnect(topic: WalletPairingTopic) async throws {}
        func request(_ request: WalletRequest, topic: WalletPairingTopic) async throws -> WalletResponse { WalletResponse(id: request.id, result: "ok") }
        func sessions() async throws -> [WalletSession] { [] }
        nonisolated func events() -> AsyncStream<WalletTransportEvent> { AsyncStream { $0.finish() } }
    }

    @Test("WalletConnectDAppConnector preserves required and optional namespaces")
    func dappConnectorPreservesRequiredAndOptionalNamespaces() async throws {
        let required = WalletNamespaceProposalSet(proposals: [
            "eip155": WalletNamespaceProposal(
                chains: [WalletBlockchain(namespace: "eip155", reference: "1")],
                methods: [WalletRequestMethod.ethPersonalSign.rawValue],
                events: ["chainChanged"]
            ),
        ])
        let optional = WalletNamespaceProposalSet(proposals: [
            "solana": WalletNamespaceProposal(
                chains: [WalletBlockchain(namespace: WalletChain.solana.namespace, reference: WalletChain.solana.chainReference)],
                methods: [WalletRequestMethod.solanaSignMessage.rawValue],
                events: []
            ),
        ])
        let transport = RecordingPairingTransport()
        let connector = WalletConnectDAppConnector(
            transport: transport,
            metadata: WalletConnectionMetadata(
                appName: "Auralis",
                appDescription: "Test",
                appURL: URL(string: "https://auralis.example")!
            )
        )

        _ = try await connector.connect(
            proposalRequest: WalletSessionProposalRequest(requiredNamespaces: required, optionalNamespaces: optional),
            wallet: nil
        )
        let recorded = try #require(await transport.recordedPairingRequest())
        #expect(recorded.requiredNamespaces == required)
        #expect(recorded.optionalNamespaces == optional)
    }

    @Test("verifyOwnership fails closed without a crypto provider")
    func verifyOwnershipFailsClosed() async {
        let connector = WalletConnectDAppConnector(
            transport: NoopTransport(),
            metadata: WalletConnectionMetadata(
                appName: "Auralis",
                appDescription: "Test",
                appURL: URL(string: "https://auralis.example")!
            ),
            cryptoProvider: nil
        )

        await #expect(throws: WalletConnectionError.self) {
            _ = try await connector.verifyOwnership(
                of: "0x0000000000000000000000000000000000000000",
                in: WalletSessionID(rawValue: "topic")
            )
        }
    }

    // MARK: - L4: signature v normalization is strict (fail closed)

    @Test("Signature v accepts only 0/1/27/28 and normalizes to 27/28")
    func signatureVNormalization() {
        func sig(_ vHex: String) -> WalletEthereumSignature? {
            WalletEthereumSignature(hexSignature: "0x" + String(repeating: "11", count: 32) + String(repeating: "22", count: 32) + vHex)
        }
        #expect(sig("00")?.v == 27)
        #expect(sig("01")?.v == 28)
        #expect(sig("1b")?.v == 27) // 27
        #expect(sig("1c")?.v == 28) // 28
        // Out-of-range recovery ids are rejected rather than passed through.
        #expect(sig("05") == nil)
        #expect(sig("ff") == nil)
    }

    // MARK: - L4: verifyPersonalSign public-key length handling

    private struct StubRecoveryProvider: WalletConnectorCryptoProvider {
        let publicKey: Data
        func recoverPublicKey(signature: WalletEthereumSignature, message: Data) throws -> Data { publicKey }
        func keccak256(_ data: Data) -> Data { EthereumKeccak256.hash(data) }
    }

    @Test("verifyPersonalSign accepts 64-byte and 0x04-prefixed 65-byte keys, rejects other lengths")
    func verifyPersonalSignKeyLengths() throws {
        let pub = Data((0..<64).map { UInt8($0 & 0xff) })
        let address = "0x" + EthereumKeccak256.hash(pub).suffix(20).map { String(format: "%02x", $0) }.joined()
        let signature = WalletEthereumSignature(v: 27, r: [UInt8](repeating: 1, count: 32), s: [UInt8](repeating: 2, count: 32))
        let message = Data("verify".utf8)

        // 64-byte uncompressed key recovers the expected address.
        #expect(try WalletOwnershipVerifier.verifyPersonalSign(
            expectedAddress: address, message: message, signature: signature,
            using: StubRecoveryProvider(publicKey: pub)))

        // 65-byte SEC1 form (0x04 ‖ X ‖ Y) is tolerated by stripping the prefix.
        #expect(try WalletOwnershipVerifier.verifyPersonalSign(
            expectedAddress: address, message: message, signature: signature,
            using: StubRecoveryProvider(publicKey: Data([0x04]) + pub)))

        // Any other length can never coincidentally match.
        #expect(try WalletOwnershipVerifier.verifyPersonalSign(
            expectedAddress: address, message: message, signature: signature,
            using: StubRecoveryProvider(publicKey: Data([1, 2, 3]))) == false)
    }

    // MARK: - M2: handleCallback is explicit for the IRN relay transport

    private func scopedConnector() -> WalletConnectDAppConnector {
        WalletConnectDAppConnector(
            transport: NoopTransport(),
            metadata: WalletConnectionMetadata(
                appName: "Auralis",
                appDescription: "Test",
                appURL: URL(string: "https://auralis.example")!
            ),
            callbackURL: URL(string: "auralis-wc://callback")!,
            cryptoProvider: nil
        )
    }

    @Test("handleCallback treats a foreground return as a no-op")
    func handleCallbackForegroundIsNoOp() async throws {
        try await scopedConnector().handleCallback(url: URL(string: "auralis-wc://wc")!)
    }

    @Test("handleCallback surfaces an unsupported Link Mode envelope instead of dropping it")
    func handleCallbackRejectsLinkMode() async {
        await #expect(throws: WalletConnectionError.self) {
            try await scopedConnector().handleCallback(url: URL(string: "auralis-wc://callback?wc_ev=envelope")!)
        }
    }
}
