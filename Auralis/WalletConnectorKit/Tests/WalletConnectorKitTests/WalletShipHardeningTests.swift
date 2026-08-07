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
}
