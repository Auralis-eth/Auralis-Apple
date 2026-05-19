import Foundation

@MainActor
public struct ExternalLinkOpenFlow {
    private let eventLogger: any ExternalLinkEventLogging
    private let openURL: (URL) -> Void

    public init(
        eventLogger: any ExternalLinkEventLogging,
        openURL: @escaping (URL) -> Void
    ) {
        self.eventLogger = eventLogger
        self.openURL = openURL
    }

    public func confirm(_ request: ExternalLinkOpenRequest) async -> ExternalLinkOpenOutcome {
        do {
            _ = try await eventLogger.recordConfirmedOpen(request)
            openURL(request.url)
            return .opened
        } catch where request.requiresDurableAudit {
            return .blockedMissingAudit
        } catch {
            openURL(request.url)
            return .openedWithAuditWarning
        }
    }
}
