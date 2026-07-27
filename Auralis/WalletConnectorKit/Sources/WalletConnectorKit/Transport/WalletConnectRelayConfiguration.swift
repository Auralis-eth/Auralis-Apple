import Foundation

public struct WalletConnectRelayConfiguration: Hashable, Sendable {
    public let projectID: String
    public let relayURL: URL

    public init(
        projectID: String,
        relayURL: URL = URL(string: "wss://relay.walletconnect.com")!
    ) {
        self.projectID = projectID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.relayURL = relayURL
    }

    public var isUsable: Bool {
        !projectID.isEmpty
    }

    public var websocketURL: URL {
        var components = URLComponents(url: relayURL, resolvingAgainstBaseURL: false)
        var items = components?.queryItems ?? []
        if !items.contains(where: { $0.name == "projectId" }) {
            items.append(URLQueryItem(name: "projectId", value: projectID))
        }
        components?.queryItems = items
        return components?.url ?? relayURL
    }
}

public enum WalletConnectRelayConfigurationError: Error, Hashable, Sendable {
    case missingProjectID
}
