import Foundation

struct ExternalLinkCandidateDestination: Equatable, Sendable {
    let label: String
    let url: URL
}

struct ExternalLinkConfirmationDestination: Identifiable, Equatable, Sendable {
    let label: String
    let url: URL
    let hostDisplay: String
    let pathDisplay: String
    let fullURLDisplay: String

    var id: String {
        fullURLDisplay
    }
}

enum ExternalLinkValidationFailure: Error, Equatable, Sendable {
    case invalidScheme(String?)
    case missingHost
    case unsupportedHost(String)

    var title: String {
        "Couldn’t Open Link"
    }

    var message: String {
        switch self {
        case .invalidScheme:
            return "Auralis blocked this destination because it did not use a secure HTTPS link."
        case .missingHost:
            return "Auralis blocked this destination because the web address was incomplete."
        case .unsupportedHost(let host):
            return "Auralis blocked this destination because \(host) is not on the approved link allowlist."
        }
    }
}

struct ExternalLinkPolicy {
    private let allowedHosts: Set<String>

    init(allowedHosts: Set<String> = Self.defaultAllowedHosts) {
        self.allowedHosts = allowedHosts
    }

    func validate(_ candidate: ExternalLinkCandidateDestination) -> Result<ExternalLinkConfirmationDestination, ExternalLinkValidationFailure> {
        guard let components = URLComponents(url: candidate.url, resolvingAgainstBaseURL: false) else {
            return .failure(.invalidScheme(nil))
        }

        guard components.scheme?.lowercased() == "https" else {
            return .failure(.invalidScheme(components.scheme))
        }

        guard let host = components.host?.lowercased(), !host.isEmpty else {
            return .failure(.missingHost)
        }

        guard allowedHosts.contains(host) else {
            return .failure(.unsupportedHost(host))
        }

        let pathDisplay = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
        return .success(
            ExternalLinkConfirmationDestination(
                label: candidate.label,
                url: candidate.url,
                hostDisplay: host,
                pathDisplay: pathDisplay,
                fullURLDisplay: components.string ?? candidate.url.absoluteString
            )
        )
    }
}

private extension ExternalLinkPolicy {
    static let defaultAllowedHosts: Set<String> = [
        "opensea.io",
        "etherscan.io",
        "sepolia.etherscan.io",
        "basescan.org",
        "sepolia.basescan.org",
        "arbiscan.io",
        "sepolia.arbiscan.io",
        "nova.arbiscan.io",
        "optimistic.etherscan.io",
        "sepolia-optimism.etherscan.io",
        "polygonscan.com",
        "amoy.polygonscan.com",
        "ipfs.io",
        "cloudflare-ipfs.com",
        "gateway.pinata.cloud",
        "arweave.net"
    ]
}

enum ExternalLinkOpenProvenance: String, Equatable, Sendable {
    case userConfirmedTap = "user_confirmed_tap"
    case operatorConfirmed = "operator_confirmed"
    case pluginConfirmed = "plugin_confirmed"

    var receiptActor: ReceiptActor {
        switch self {
        case .userConfirmedTap:
            return .user
        case .operatorConfirmed, .pluginConfirmed:
            return .system
        }
    }
}

struct ExternalLinkOpenRequest: Equatable, Sendable {
    let label: String
    let url: URL
    let surface: String
    let accountAddress: String?
    let chain: Chain?
    let provenance: ExternalLinkOpenProvenance

    init(
        label: String,
        url: URL,
        surface: String,
        accountAddress: String? = nil,
        chain: Chain? = nil,
        provenance: ExternalLinkOpenProvenance = .userConfirmedTap
    ) {
        self.label = label
        self.url = url
        self.surface = surface
        self.accountAddress = accountAddress
        self.chain = chain
        self.provenance = provenance
    }
}

@MainActor
protocol ExternalLinkEventLogging {
    func recordConfirmedOpen(_ request: ExternalLinkOpenRequest) async throws -> ReceiptRecord
}

extension ReceiptEventLogger: ExternalLinkEventLogging {
    func recordConfirmedOpen(_ request: ExternalLinkOpenRequest) async throws -> ReceiptRecord {
        try await recordExternalLinkOpened(
            label: request.label,
            url: request.url,
            surface: request.surface,
            accountAddress: request.accountAddress,
            chain: request.chain,
            provenance: request.provenance
        )
    }
}

@MainActor
struct ExternalLinkOpenFlow {
    let eventLogger: any ExternalLinkEventLogging
    let openURL: (URL) -> Void

    func confirm(_ request: ExternalLinkOpenRequest) async {
        do {
            _ = try await eventLogger.recordConfirmedOpen(request)
        } catch {
            // User confirmation is the security gate. Receipt logging is best-effort
            // and must not block the confirmed handoff to Safari.
        }
        openURL(request.url)
    }
}
