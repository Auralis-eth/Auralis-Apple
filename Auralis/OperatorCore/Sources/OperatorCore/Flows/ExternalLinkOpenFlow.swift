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

    public func confirm(_ request: ExternalLinkOpenRequest) async {
        do {
            _ = try await eventLogger.recordConfirmedOpen(request)
        } catch {
            // User confirmation is the security gate. Receipt logging is best-effort
            // and must not block the confirmed handoff to Safari.
        }
        openURL(request.url)
    }
}
