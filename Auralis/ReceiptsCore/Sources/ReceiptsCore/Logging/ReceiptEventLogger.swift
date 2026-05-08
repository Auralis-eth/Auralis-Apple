import AuralisPrimaryModels
import Foundation
import OSLog

@MainActor
public struct ReceiptEventLogger {
    private let receiptStore: any ReceiptStore
    private let payloadSanitizer: any ReceiptPayloadSanitizing
    private let logger = Logger(subsystem: "Auralis", category: "Receipts")

    public init(
        receiptStore: any ReceiptStore,
        payloadSanitizer: any ReceiptPayloadSanitizing = DefaultReceiptPayloadSanitizer()
    ) {
        self.receiptStore = receiptStore
        self.payloadSanitizer = payloadSanitizer
    }

    public func append(
        trigger: String,
        scope: String,
        summary: String,
        provenance: String,
        timelineAccountAddress: String? = nil,
        timelineChainRawValue: String? = nil,
        rawPayload: RawReceiptPayload,
        correlationID: String? = nil,
        actor: ReceiptActor = .system,
        mode: ReceiptMode = .observe,
        isSuccess: Bool = true
    ) async throws -> ReceiptRecord {
        let payload = payloadSanitizer.sanitize(rawPayload)

        do {
            return try await receiptStore.append(
                ReceiptDraft(
                    actor: actor,
                    mode: mode,
                    trigger: trigger,
                    scope: scope,
                    summary: summary,
                    provenance: provenance,
                    isSuccess: isSuccess,
                    correlationID: correlationID,
                    timelineAccountAddress: timelineAccountAddress,
                    timelineChainRawValue: timelineChainRawValue,
                    details: payload
                )
            )
        } catch {
            logger.error(
                "Failed to append receipt event trigger=\(trigger, privacy: .public) scope=\(scope, privacy: .public) correlationID=\(correlationID ?? "nil", privacy: .private(mask: .hash)) error=\(error.localizedDescription, privacy: .public)"
            )
            throw error
        }
    }
}
