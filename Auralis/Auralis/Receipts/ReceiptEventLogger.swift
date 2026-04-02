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
        accountAddress: String? = nil,
        chain: Chain? = nil,
        correlationID: String? = nil
    ) -> Result<ReceiptRecord, Error> {
        var payloadValues: [String: ReceiptJSONValue] = [
            "label": .string(label),
            "surface": .string(surface),
            "url": .string(url.absoluteString),
            "chain": chain.map { .string($0.rawValue) } ?? .null
        ]

        if let accountAddress {
            payloadValues["accountAddress"] = .string(accountAddress)
        }

        return append(
            trigger: "external_link.opened",
            scope: "navigation.external",
            summary: "Opened external link",
            provenance: "user_provided",
            rawPayload: RawReceiptPayload(values: payloadValues),
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
        accountAddress: String? = nil,
        chain: Chain? = nil,
        correlationID: String? = nil
    ) -> Result<ReceiptRecord, Error> {
        var payloadValues: [String: ReceiptJSONValue] = [
            "subject": .string(subject),
            "value": .string(value),
            "surface": .string(surface)
        ]

        if let accountAddress {
            payloadValues["accountAddress"] = .string(accountAddress)
        }

        if let chain {
            payloadValues["chain"] = .string(chain.rawValue)
        }

        return append(
            trigger: "copy.performed",
            scope: "clipboard",
            summary: "Copied value",
            provenance: "user_provided",
            rawPayload: RawReceiptPayload(values: payloadValues),
            correlationID: correlationID,
            actor: .user,
            isSuccess: true
        )
    }

    @discardableResult
    func recordMusicLibraryIndexStarted(
        accountAddress: String,
        chain: Chain,
        correlationID: String?
    ) -> Result<ReceiptRecord, Error> {
        append(
            trigger: "music.library_index.started",
            scope: "music.library",
            summary: "Started music library index rebuild",
            provenance: "local_cache",
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
    func recordMusicLibraryIndexCompleted(
        accountAddress: String,
        chain: Chain,
        correlationID: String?,
        scannedCount: Int,
        writtenCount: Int,
        removedCount: Int
    ) -> Result<ReceiptRecord, Error> {
        append(
            trigger: "music.library_index.completed",
            scope: "music.library",
            summary: "Rebuilt music library index",
            provenance: "local_cache",
            rawPayload: RawReceiptPayload(values: [
                "accountAddress": .string(accountAddress),
                "chain": .string(chain.rawValue),
                "scannedCount": .number(Double(scannedCount)),
                "writtenCount": .number(Double(writtenCount)),
                "removedCount": .number(Double(removedCount))
            ]),
            correlationID: correlationID,
            actor: .system,
            isSuccess: true
        )
    }

    @discardableResult
    func recordMusicLibraryIndexFailed(
        accountAddress: String,
        chain: Chain,
        correlationID: String?,
        error: Error
    ) -> Result<ReceiptRecord, Error> {
        append(
            trigger: "music.library_index.failed",
            scope: "music.library",
            summary: "Music library index rebuild failed",
            provenance: "local_cache",
            rawPayload: RawReceiptPayload(values: [
                "accountAddress": .string(accountAddress),
                "chain": .string(chain.rawValue),
                "error": .string(String(describing: error))
            ]),
            correlationID: correlationID,
            actor: .system,
            isSuccess: false
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
            return .failure(error)
        }
    }
}
