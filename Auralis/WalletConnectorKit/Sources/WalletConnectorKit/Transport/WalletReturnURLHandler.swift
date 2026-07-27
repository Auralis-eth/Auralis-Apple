import Foundation

public enum WalletReturnPayload: Hashable, Sendable {
    case foreground
    case linkModeEnvelope(String)
}

public struct WalletReturnURLHandler: Sendable {
    public init() {}

    public func handle(_ url: URL) -> WalletReturnPayload? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        if let envelope = components.queryItems?.first(where: { $0.name == "wc_ev" })?.value {
            return .linkModeEnvelope(envelope)
        }
        if components.host == "wc" || components.path.contains("wc") {
            return .foreground
        }
        return nil
    }
}

