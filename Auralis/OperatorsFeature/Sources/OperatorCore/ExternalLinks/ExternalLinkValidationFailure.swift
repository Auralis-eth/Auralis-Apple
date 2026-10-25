public enum ExternalLinkValidationFailure: Error, Equatable, Sendable {
    case invalidScheme(String?)
    case missingHost

    /// The URL carried userinfo (`https://evil.example@etherscan.io/…`).
    ///
    /// Distinct from ``unsupportedHost`` because the host here *is* on the allowlist and the request
    /// really does go to it — what fails is the confirmation sheet, which shows the host on its own
    /// line and so reads as a bare, approved host while the address the person is agreeing to leads
    /// with something else entirely.
    case embeddedCredentials(host: String)

    /// The URL named an explicit port. Rejected for the same reason as ``embeddedCredentials``: the
    /// host line on the confirmation sheet does not carry the port, so the route shown is not the
    /// route that loads.
    case unsupportedPort(host: String, port: Int)

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
        case .embeddedCredentials(let host):
            return "Auralis blocked this destination because the web address carried sign-in details ahead of \(host), which can disguise where a link really goes."
        case .unsupportedPort(let host, let port):
            return "Auralis blocked this destination because it reached \(host) over port \(port) instead of the standard HTTPS port."
        case .unsupportedHost(let host):
            return "Auralis blocked this destination because \(host) is not on the approved link allowlist."
        case .unsupportedPath(let host, let path):
            return "Auralis blocked this destination because \(host)\(path) is not an approved route."
        }
    }
}
