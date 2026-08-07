import Foundation

public actor WalletInboundURLCoordinator {
    private let handler: WalletReturnURLHandler
    private var handledSignatures: Set<String> = []
    private var queuedPayloads: [WalletReturnPayload] = []

    public init(handler: WalletReturnURLHandler = WalletReturnURLHandler()) {
        self.handler = handler
    }

    public func capture(_ url: URL, isReady: Bool) -> WalletReturnPayload? {
        guard let payload = handler.handle(url), handledSignatures.insert(Self.signature(for: url)).inserted else {
            return nil
        }

        if isReady {
            return payload
        }
        queuedPayloads.append(payload)
        return nil
    }

    public func drainQueuedPayloads() -> [WalletReturnPayload] {
        let payloads = queuedPayloads
        queuedPayloads.removeAll()
        return payloads
    }

    public func reset() {
        handledSignatures.removeAll()
        queuedPayloads.removeAll()
    }

    private static func signature(for url: URL) -> String {
        url.absoluteString
    }
}
