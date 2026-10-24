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

    /// - Parameters:
    ///   - actorDetail: Who acted (P0.5-602). Required, with no default, so a receipt cannot be
    ///     written without stating its actor — this logger is the app's shared receipt writer, and
    ///     while it had no such parameter the majority of receipts by volume persisted no attribution
    ///     at all. Callers holding a `RuntimeCore.ActorRef` pass `ref.receiptActorDetail`.
    ///   - authorityDetail: The authority the action proceeded under. Required, with no default, for
    ///     the same reason as `actorDetail`: while it was defaulted only 2 of 18 writers ever set it.
    ///     Most app-level events (launch, cache refresh, a copy action) resolve no capability lease,
    ///     but "standing policy allowed this" is a real answer and the one they should record —
    ///     `.policyDefault(capability:reason:)`. Pass `nil` only when the action genuinely never
    ///     reached a point where authority was decided.
    public func append(
        trigger: String,
        scope: String,
        summary: String,
        provenance: String,
        timelineAccountAddress: String? = nil,
        timelineChainRawValue: String? = nil,
        rawPayload: RawReceiptPayload,
        correlationID: String? = nil,
        actorDetail: ReceiptActorDetail,
        authorityDetail: ReceiptAuthorityDetail?,
        mode: ReceiptMode = .observe,
        isSuccess: Bool = true
    ) async throws -> ReceiptRecord {
        let payload = payloadSanitizer.sanitize(rawPayload)

        do {
            return try await receiptStore.append(
                ReceiptDraft(
                    // The coarse `actor` filter column is no longer passed here. It used to be
                    // hand-derived as `actorDetail.coarseActor` with a comment asserting the two
                    // "can never disagree" — an invariant the type did not hold, since `actor:` was
                    // defaulted and independently settable. `ReceiptDraft` derives it now, so the
                    // assertion is the compiler's rather than this call site's.
                    actorDetail: actorDetail,
                    authorityDetail: authorityDetail,
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
