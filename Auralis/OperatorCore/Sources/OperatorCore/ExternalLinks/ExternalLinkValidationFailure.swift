public enum ExternalLinkValidationFailure: Error, Equatable, Sendable {
    case invalidScheme(String?)
    case missingHost
    case unsupportedHost(String)
    case unsupportedPath(host: String, path: String)

    public var title: String {
        "Couldn’t Open Link"
    }

    public var message: String {
        switch self {
        case .invalidScheme:
            return "Auralis blocked this destination because it did not use a secure HTTPS link."
        case .missingHost:
            return "Auralis blocked this destination because the web address was incomplete."
        case .unsupportedHost(let host):
            return "Auralis blocked this destination because \(host) is not on the approved link allowlist."
        case .unsupportedPath(let host, let path):
            return "Auralis blocked this destination because \(host)\(path) is not an approved route."
        }
    }
}
