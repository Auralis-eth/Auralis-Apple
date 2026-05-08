import OperatorCore
import ReceiptsCore

struct AppExternalLinkEventLogger: ExternalLinkEventLogging {
    private let receiptEventLogger: ReceiptEventLogger

    init(receiptEventLogger: ReceiptEventLogger) {
        self.receiptEventLogger = receiptEventLogger
    }

    func recordConfirmedOpen(_ request: ExternalLinkOpenRequest) async throws -> ReceiptRecord {
        try await receiptEventLogger.recordExternalLinkOpened(
            label: request.label,
            url: request.url,
            surface: request.surface,
            accountAddress: request.accountAddress,
            chain: request.chain,
            provenance: request.provenance
        )
    }
}
