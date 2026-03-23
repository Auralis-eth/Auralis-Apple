import Foundation

@MainActor
struct ReceiptEventLogger {
    private let receiptStore: any ReceiptStore
    private let payloadSanitizer: any ReceiptPayloadSanitizing

    init(
        receiptStore: any ReceiptStore,
        payloadSanitizer: any ReceiptPayloadSanitizing = DefaultReceiptPayloadSanitizer()
    ) {
        self.receiptStore = receiptStore
        self.payloadSanitizer = payloadSanitizer
    }

    func recordAppLaunch(
        accountAddress: String,
        chain: Chain,
        correlationID: String
    ) {
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

    func recordContextBuilt(
        snapshot: ContextSnapshot,
        correlationID: String?
    ) {
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

    func recordExternalLinkOpened(
        label: String,
        url: URL,
        surface: String,
        correlationID: String? = nil
    ) {
        append(
            trigger: "external_link.opened",
            scope: "navigation.external",
            summary: "Opened external link",
            provenance: "user_provided",
            rawPayload: RawReceiptPayload(values: [
                "label": .string(label),
                "surface": .string(surface),
                "url": .string(url.absoluteString)
            ]),
            correlationID: correlationID,
            actor: .user,
            isSuccess: true
        )
    }

    func recordCopyAction(
        subject: String,
        value: String,
        surface: String,
        correlationID: String? = nil
    ) {
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
    ) {
        let payload = payloadSanitizer.sanitize(rawPayload)

        do {
            _ = try receiptStore.append(
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
        } catch {
            assertionFailure("Failed to append receipt event: \(error.localizedDescription)")
        }
    }
}
