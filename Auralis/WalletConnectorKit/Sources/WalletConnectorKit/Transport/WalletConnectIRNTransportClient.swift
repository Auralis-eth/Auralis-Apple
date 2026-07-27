import CryptoKit
import Foundation
import Security

public actor WalletConnectIRNTransportClient: WalletTransportClient {
    private let relayClient: WalletConnectIRNRelayClient
    private let now: @Sendable () -> Date
    private let eventsStream: AsyncStream<WalletTransportEvent>
    private let eventsContinuation: AsyncStream<WalletTransportEvent>.Continuation
    private var sessionsByID: [WalletSessionID: WalletSession] = [:]

    public init(
        relayClient: WalletConnectIRNRelayClient,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.relayClient = relayClient
        self.now = now
        let stream = AsyncStream<WalletTransportEvent>.makeStream()
        self.eventsStream = stream.stream
        self.eventsContinuation = stream.continuation
        Task { [weak self] in
            await self?.bridgeRelayEvents()
        }
    }

    public nonisolated func events() -> AsyncStream<WalletTransportEvent> {
        eventsStream
    }

    public func createPairing(request: WalletPairingRequest) async throws -> WalletPairing {
        let symKey = Self.randomHex(byteCount: 32)
        let topic = try Self.topic(forSymKeyHex: symKey)
        let expiryDate = now().addingTimeInterval(300)
        let uri = WalletConnectURI(
            topic: topic,
            symKey: symKey,
            expiryTimestamp: Int64(expiryDate.timeIntervalSince1970),
            methods: ["wc_sessionPropose"]
        )

        try await relayClient.subscribe(topic: topic)

        let pairing = WalletPairing(
            topic: WalletPairingTopic(rawValue: topic),
            providerID: request.providerID,
            uri: uri.absoluteString,
            expiryDate: expiryDate
        )
        eventsContinuation.yield(.pairingCreated(pairing))
        return pairing
    }

    public func disconnect(topic: WalletPairingTopic) async throws {
        sessionsByID.removeValue(forKey: WalletSessionID(rawValue: topic.rawValue))
    }

    public func publish(_ request: WalletRequest, topic: WalletPairingTopic) async throws {
        throw WalletConnectionError.unavailable("Live WalletConnect request publishing is not available until session settlement is complete.")
    }

    public func sessions() async throws -> [WalletSession] {
        Array(sessionsByID.values)
    }

    private func bridgeRelayEvents() async {
        for await event in relayClient.events {
            switch event {
            case .socketStatusChanged(let status):
                eventsContinuation.yield(.socketStatusChanged(status))
            case .subscription:
                break
            }
        }
    }

    private static func randomHex(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func topic(forSymKeyHex symKeyHex: String) throws -> String {
        guard let keyData = Data(hexEncoded: symKeyHex) else {
            throw WalletConnectionError.cryptographyFailure
        }
        let digest = SHA256.hash(data: keyData)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private extension Data {
    init?(hexEncoded string: String) {
        guard string.count.isMultiple(of: 2) else { return nil }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(string.count / 2)

        var index = string.startIndex
        while index < string.endIndex {
            let nextIndex = string.index(index, offsetBy: 2)
            guard let byte = UInt8(string[index..<nextIndex], radix: 16) else {
                return nil
            }
            bytes.append(byte)
            index = nextIndex
        }

        self.init(bytes)
    }
}
