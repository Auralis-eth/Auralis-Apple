import ReceiptsCore

@MainActor
public protocol ExternalLinkEventLogging {
    func recordConfirmedOpen(_ request: ExternalLinkOpenRequest) async throws -> ReceiptRecord
}
