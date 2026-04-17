import Foundation
import OSLog

@MainActor
final class ReceiptBackedENSEventRecorder: ENSEventRecording {
    private let receiptStore: any ReceiptStore
    private let payloadSanitizer: any ReceiptPayloadSanitizing
    private let logger = Logger(subsystem: "Auralis", category: "ENSReceipts")

    init(
        receiptStore: any ReceiptStore,
        payloadSanitizer: any ReceiptPayloadSanitizing = DefaultReceiptPayloadSanitizer()
    ) {
        self.receiptStore = receiptStore
        self.payloadSanitizer = payloadSanitizer
    }

    func recordCacheHit(
        kind: String,
        key: String,
        fetchedAt: Date,
        correlationID: String?
    ) async {
        append(
            trigger: "ens.\(kind).cache_hit",
            summary: "Used cached ENS resolution",
            correlationID: correlationID,
            isSuccess: true,
            rawPayload: ENSCacheHitReceiptPayload(
                kind: kind,
                key: key,
                fetchedAt: fetchedAt
            ).rawPayload
        )
    }

    func recordLookupStarted(
        kind: String,
        key: String,
        correlationID: String?
    ) async {
        append(
            trigger: "ens.\(kind).started",
            summary: "Started ENS lookup",
            correlationID: correlationID,
            isSuccess: true,
            rawPayload: ENSLookupStartedReceiptPayload(
                kind: kind,
                key: key
            ).rawPayload
        )
    }

    func recordLookupSucceeded(
        kind: String,
        key: String,
        value: String,
        verification: Bool?,
        correlationID: String?
    ) async {
        append(
            trigger: "ens.\(kind).succeeded",
            summary: "ENS lookup succeeded",
            correlationID: correlationID,
            isSuccess: true,
            rawPayload: ENSLookupSucceededReceiptPayload(
                kind: kind,
                key: key,
                value: value,
                verification: verification
            ).rawPayload
        )
    }

    func recordLookupFailed(
        kind: String,
        key: String,
        correlationID: String?,
        error: Error
    ) async {
        append(
            trigger: "ens.\(kind).failed",
            summary: "ENS lookup failed",
            correlationID: correlationID,
            isSuccess: false,
            rawPayload: ENSLookupFailedReceiptPayload(
                kind: kind,
                key: key,
                errorDescription: String(describing: error)
            ).rawPayload
        )
    }

    func recordMappingChanged(
        kind: String,
        key: String,
        oldValue: String,
        newValue: String,
        correlationID: String?
    ) async {
        append(
            trigger: "ens.\(kind).mapping_changed",
            summary: "ENS mapping changed",
            correlationID: correlationID,
            isSuccess: true,
            rawPayload: ENSMappingChangedReceiptPayload(
                kind: kind,
                key: key,
                oldValue: oldValue,
                newValue: newValue
            ).rawPayload
        )
    }
}

@MainActor
private extension ReceiptBackedENSEventRecorder {
    func append(
        trigger: String,
        summary: String,
        correlationID: String?,
        isSuccess: Bool,
        rawPayload: RawReceiptPayload
    ) {
        let payload = payloadSanitizer.sanitize(rawPayload)

        do {
            _ = try receiptStore.append(
                ReceiptDraft(
                    actor: .system,
                    mode: .observe,
                    trigger: trigger,
                    scope: "identity.ens",
                    summary: summary,
                    provenance: "network",
                    isSuccess: isSuccess,
                    correlationID: correlationID,
                    details: payload
                )
            )
        } catch {
            logger.error(
                "Failed to append ENS receipt trigger=\(trigger, privacy: .public) correlationID=\(correlationID ?? "nil", privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }
}

private struct ENSCacheHitReceiptPayload: TypedReceiptPayload {
    let kind: String
    let key: String
    let fetchedAt: Date

    var fields: [ReceiptPayloadField] {
        [
            .public("lookupKind", string: kind, kind: .label),
            .hashed("key", string: key, kind: .unknownString),
            .public(
                "fetchedAt",
                string: ISO8601DateFormatter().string(from: fetchedAt),
                kind: .timestamp
            )
        ]
    }
}

private struct ENSLookupStartedReceiptPayload: TypedReceiptPayload {
    let kind: String
    let key: String

    var fields: [ReceiptPayloadField] {
        [
            .public("lookupKind", string: kind, kind: .label),
            .hashed("key", string: key, kind: .unknownString)
        ]
    }
}

private struct ENSLookupSucceededReceiptPayload: TypedReceiptPayload {
    let kind: String
    let key: String
    let value: String
    let verification: Bool?

    var fields: [ReceiptPayloadField] {
        var fields: [ReceiptPayloadField] = [
            .public("lookupKind", string: kind, kind: .label),
            .hashed("key", string: key, kind: .unknownString),
            .hashed("value", string: value, kind: .unknownString)
        ]

        if let verification {
            fields.append(.bool("isForwardVerified", verification))
        }

        return fields
    }
}

private struct ENSLookupFailedReceiptPayload: TypedReceiptPayload {
    let kind: String
    let key: String
    let errorDescription: String

    var fields: [ReceiptPayloadField] {
        [
            .public("lookupKind", string: kind, kind: .label),
            .hashed("key", string: key, kind: .unknownString),
            .redacted("error", string: errorDescription, kind: .errorMessage)
        ]
    }
}

private struct ENSMappingChangedReceiptPayload: TypedReceiptPayload {
    let kind: String
    let key: String
    let oldValue: String
    let newValue: String

    var fields: [ReceiptPayloadField] {
        [
            .public("lookupKind", string: kind, kind: .label),
            .hashed("key", string: key, kind: .unknownString),
            .hashed("oldValue", string: oldValue, kind: .unknownString),
            .hashed("newValue", string: newValue, kind: .unknownString)
        ]
    }
}
