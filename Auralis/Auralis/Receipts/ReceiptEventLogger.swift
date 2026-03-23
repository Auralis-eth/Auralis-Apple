import Foundation
import OSLog

@MainActor
struct ReceiptEventLogger {
    private let receiptStore: any ReceiptStore
    private let payloadSanitizer: any ReceiptPayloadSanitizing
    private let logger = Logger(subsystem: "Auralis", category: "Receipts")

    init(
        receiptStore: any ReceiptStore,
        payloadSanitizer: any ReceiptPayloadSanitizing = DefaultReceiptPayloadSanitizer()
    ) {
        self.receiptStore = receiptStore
        self.payloadSanitizer = payloadSanitizer
    }

    @discardableResult
    func recordAppLaunch(
        accountAddress: String,
        chain: Chain,
        correlationID: String
    ) -> Result<ReceiptRecord, Error> {
        append(
            trigger: "app.launch",
            scope: "app",
            summary: "Launched Auralis",
            provenance: "local",
            rawPayload: RawReceiptPayload(values: [
                "accountAddress": .string(accountAddress),
                "chain": .string(chain.rawValue)
            ]),
            correlationID: correlationID,
            actor: .system,
            isSuccess: true
        )
    }

    @discardableResult
    func recordContextBuilt(
        snapshot: ContextSnapshot,
        correlationID: String?
    ) -> Result<ReceiptRecord, Error> {
        append(
            trigger: "context.built",
            scope: "context",
            summary: "Built shell context snapshot",
            provenance: "local_cache",
            rawPayload: RawReceiptPayload(values: [
                "schemaVersion": .string(snapshot.version.rawValue),
                "accountAddress": .string(snapshot.scope.accountAddress.value ?? ""),
                "selectedChains": .array((snapshot.scope.selectedChains.value ?? []).map {
                    .string($0.rawValue)
                }),
                "refreshState": .string(snapshot.freshness.refreshState.rawValue),
                "isStale": .bool(snapshot.freshness.isStale),
                "mode": .string(snapshot.modeDisplay)
            ]),
            correlationID: correlationID,
            actor: .system,
            isSuccess: true
        )
    }

    @discardableResult
    func recordExternalLinkOpened(
        label: String,
        url: URL,
        surface: String,
        chain: Chain? = nil,
        correlationID: String? = nil
    ) -> Result<ReceiptRecord, Error> {
        append(
            trigger: "external_link.opened",
            scope: "navigation.external",
            summary: "Opened external link",
            provenance: "user_provided",
            rawPayload: RawReceiptPayload(values: [
                "label": .string(label),
                "surface": .string(surface),
                "url": .string(url.absoluteString),
                "chain": chain.map { .string($0.rawValue) } ?? .null
            ]),
            correlationID: correlationID,
            actor: .user,
            isSuccess: true
        )
    }

    @discardableResult
    func recordCopyAction(
        subject: String,
        value: String,
        surface: String,
        correlationID: String? = nil
    ) -> Result<ReceiptRecord, Error> {
        append(
            trigger: "copy.performed",
            scope: "clipboard",
            summary: "Copied value",
            provenance: "user_provided",
            rawPayload: RawReceiptPayload(values: [
                "subject": .string(subject),
                "value": .string(value),
                "surface": .string(surface)
            ]),
            correlationID: correlationID,
            actor: .user,
            isSuccess: true
        )
    }
}

@MainActor
private extension ReceiptEventLogger {
    func append(
        trigger: String,
        scope: String,
        summary: String,
        provenance: String,
        rawPayload: RawReceiptPayload,
        correlationID: String?,
        actor: ReceiptActor,
        isSuccess: Bool
    ) -> Result<ReceiptRecord, Error> {
        let payload = payloadSanitizer.sanitize(rawPayload)

        do {
            let record = try receiptStore.append(
                ReceiptDraft(
                    actor: actor,
                    mode: .observe,
                    trigger: trigger,
                    scope: scope,
                    summary: summary,
                    provenance: provenance,
                    isSuccess: isSuccess,
                    correlationID: correlationID,
                    details: payload
                )
            )
            return .success(record)
        } catch {
            logger.error(
                "Failed to append receipt event trigger=\(trigger, privacy: .public) scope=\(scope, privacy: .public) correlationID=\(correlationID ?? "nil", privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            assertionFailure("Failed to append receipt event: \(error.localizedDescription)")
            return .failure(error)
        }
    }
}
