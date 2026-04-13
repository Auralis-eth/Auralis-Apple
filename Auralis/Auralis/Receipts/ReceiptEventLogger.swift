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
            rawPayload: AppLaunchReceiptPayload(
                accountAddress: accountAddress,
                chain: chain
            ).rawPayload,
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
            rawPayload: ContextBuiltReceiptPayload(snapshot: snapshot).rawPayload,
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
        return append(
            trigger: "external_link.opened",
            scope: "navigation.external",
            summary: "Opened external link",
            provenance: "user_provided",
            rawPayload: ExternalLinkOpenedReceiptPayload(
                label: label,
                url: url,
                surface: surface,
                accountAddress: accountAddress,
                chain: chain
            ).rawPayload,
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
        return append(
            trigger: "copy.performed",
            scope: "clipboard",
            summary: "Copied value",
            provenance: "user_provided",
            rawPayload: CopyActionReceiptPayload(
                subject: subject,
                value: value,
                surface: surface,
                accountAddress: accountAddress,
                chain: chain
            ).rawPayload,
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
            rawPayload: MusicLibraryIndexStartedReceiptPayload(
                accountAddress: accountAddress,
                chain: chain
            ).rawPayload,
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
            rawPayload: MusicLibraryIndexCompletedReceiptPayload(
                accountAddress: accountAddress,
                chain: chain,
                scannedCount: scannedCount,
                writtenCount: writtenCount,
                removedCount: removedCount
            ).rawPayload,
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
            rawPayload: MusicLibraryIndexFailedReceiptPayload(
                accountAddress: accountAddress,
                chain: chain,
                errorDescription: String(describing: error)
            ).rawPayload,
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

private struct AppLaunchReceiptPayload: TypedReceiptPayload {
    let accountAddress: String
    let chain: Chain

    var fields: [ReceiptPayloadField] {
        [
            .hashed("accountAddress", string: accountAddress, kind: .walletAddress),
            .public("chain", string: chain.rawValue, kind: .chain)
        ]
    }
}

private struct ContextBuiltReceiptPayload: TypedReceiptPayload {
    let snapshot: ContextSnapshot

    var fields: [ReceiptPayloadField] {
        [
            .public("schemaVersion", string: snapshot.version.rawValue, kind: .label),
            .hashed("accountAddress", string: snapshot.scope.accountAddress.value ?? "", kind: .walletAddress),
            .stringArray(
                "selectedChains",
                values: (snapshot.scope.selectedChains.value ?? []).map(\.rawValue),
                kind: .chain
            ),
            .public("refreshState", string: snapshot.freshness.refreshState.rawValue, kind: .label),
            .bool("isStale", snapshot.freshness.isStale),
            .public("mode", string: snapshot.modeDisplay, kind: .label)
        ]
    }
}

private struct ExternalLinkOpenedReceiptPayload: TypedReceiptPayload {
    let label: String
    let url: URL
    let surface: String
    let accountAddress: String?
    let chain: Chain?

    var fields: [ReceiptPayloadField] {
        var fields: [ReceiptPayloadField] = [
            .public("label", string: label, kind: .label),
            .public("surface", string: surface, kind: .label),
            .public("url", string: url.absoluteString, kind: .url)
        ]

        if let accountAddress {
            fields.append(.hashed("accountAddress", string: accountAddress, kind: .walletAddress))
        }

        if let chain {
            fields.append(.public("chain", string: chain.rawValue, kind: .chain))
        } else {
            fields.append(.null("chain"))
        }

        return fields
    }
}

private struct CopyActionReceiptPayload: TypedReceiptPayload {
    let subject: String
    let value: String
    let surface: String
    let accountAddress: String?
    let chain: Chain?

    var fields: [ReceiptPayloadField] {
        var fields: [ReceiptPayloadField] = [
            .public("subject", string: subject, kind: .label),
            .redacted("value", string: value, kind: .copiedText),
            .public("surface", string: surface, kind: .label)
        ]

        if let accountAddress {
            fields.append(.hashed("accountAddress", string: accountAddress, kind: .walletAddress))
        }

        if let chain {
            fields.append(.public("chain", string: chain.rawValue, kind: .chain))
        }

        return fields
    }
}

private struct MusicLibraryIndexStartedReceiptPayload: TypedReceiptPayload {
    let accountAddress: String
    let chain: Chain

    var fields: [ReceiptPayloadField] {
        [
            .hashed("accountAddress", string: accountAddress, kind: .walletAddress),
            .public("chain", string: chain.rawValue, kind: .chain)
        ]
    }
}

private struct MusicLibraryIndexCompletedReceiptPayload: TypedReceiptPayload {
    let accountAddress: String
    let chain: Chain
    let scannedCount: Int
    let writtenCount: Int
    let removedCount: Int

    var fields: [ReceiptPayloadField] {
        [
            .hashed("accountAddress", string: accountAddress, kind: .walletAddress),
            .public("chain", string: chain.rawValue, kind: .chain),
            .number("scannedCount", Double(scannedCount)),
            .number("writtenCount", Double(writtenCount)),
            .number("removedCount", Double(removedCount))
        ]
    }
}

private struct MusicLibraryIndexFailedReceiptPayload: TypedReceiptPayload {
    let accountAddress: String
    let chain: Chain
    let errorDescription: String

    var fields: [ReceiptPayloadField] {
        [
            .hashed("accountAddress", string: accountAddress, kind: .walletAddress),
            .public("chain", string: chain.rawValue, kind: .chain),
            .redacted("error", string: errorDescription, kind: .errorMessage)
        ]
    }
}
