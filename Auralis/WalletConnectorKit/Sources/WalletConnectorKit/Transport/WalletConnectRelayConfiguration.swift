import Foundation

public struct WalletConnectRelayConfiguration: Hashable, Sendable {
    public let projectID: String
    public let relayURL: URL

    public init(
        projectID: String,
        // Current WalletConnect/Reown relay host. The legacy `.com` host still
        // resolves but is deprecated in favor of `.org`.
        relayURL: URL = URL(string: "wss://relay.walletconnect.org")!
    ) {
        self.projectID = projectID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.relayURL = relayURL
    }

    public var isUsable: Bool {
        !projectID.isEmpty && isSecure
    }

    /// The relay must be reached over TLS (`wss`). Payloads are already E2E
    /// encrypted, but refusing a plaintext `ws://` relay closes a silent
    /// transport-downgrade misconfiguration.
    public var isSecure: Bool {
        relayURL.scheme?.lowercased() == "wss"
    }

    public var websocketURL: URL {
        websocketURL(authToken: nil)
    }

    /// Relay websocket URL with the required `projectId` and, when supplied, the
    /// Ed25519 DID-JWT `auth` token the relay demands to authorize the socket.
    public func websocketURL(authToken: String?) -> URL {
        var components = URLComponents(url: relayURL, resolvingAgainstBaseURL: false)
        var items = components?.queryItems ?? []
        if !items.contains(where: { $0.name == "projectId" }) {
            items.append(URLQueryItem(name: "projectId", value: projectID))
        }
        if let authToken, !items.contains(where: { $0.name == "auth" }) {
            items.append(URLQueryItem(name: "auth", value: authToken))
        }
        components?.queryItems = items
        return components?.url ?? relayURL
    }
}

public enum WalletConnectRelayConfigurationError: Error, Hashable, Sendable {
    case missingProjectID
    /// The configured relay URL does not use TLS (`wss`).
    case insecureRelayURL
}
