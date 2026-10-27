import Foundation

public enum WalletReturnPayload: Hashable, Sendable {
    case foreground
    case linkModeEnvelope(String)
}

/// Classifies inbound wallet-callback URLs (foreground return vs Link Mode
/// envelope).
///
/// - Important: A `nil` allow-list means "accept any scheme/host". The default
///   initializer leaves both `nil`, so callers that hand this handler
///   *untrusted* inbound URLs should pass their own app scheme and universal-link
///   host to `allowedSchemes`/`allowedHosts`. Duplicate-suppression and
///   operation-ID gating in `WalletInboundURLCoordinator` are the second line of
///   defense, not a substitute for scoping the allow-lists.
public struct WalletReturnURLHandler: Sendable {
    private let allowedSchemes: Set<String>?
    private let allowedHosts: Set<String>?

    public init(allowedSchemes: Set<String>? = nil, allowedHosts: Set<String>? = nil) {
        self.allowedSchemes = allowedSchemes?.map(Self.normalizedURLPart).reduce(into: Set<String>()) { $0.insert($1) }
        self.allowedHosts = allowedHosts?.map(Self.normalizedURLPart).reduce(into: Set<String>()) { $0.insert($1) }
    }

    public func handle(_ url: URL) -> WalletReturnPayload? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false), isAllowed(components) else {
            return nil
        }
        if let envelope = components.queryItems?.first(where: { $0.name == "wc_ev" })?.value {
            return .linkModeEnvelope(envelope)
        }
        if components.host == "wc" || components.path.split(separator: "/").contains("wc") {
            return .foreground
        }
        return nil
    }

    private func isAllowed(_ components: URLComponents) -> Bool {
        if let allowedSchemes {
            guard let scheme = components.scheme.map(Self.normalizedURLPart), allowedSchemes.contains(scheme) else {
                return false
            }
        }
        if let allowedHosts {
            guard let host = components.host.map(Self.normalizedURLPart), allowedHosts.contains(host) else {
                return false
            }
        }
        return true
    }

    private static func normalizedURLPart(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

