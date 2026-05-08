import AuralisPrimaryModels
import Foundation

public enum ReceiptPayloadFieldSensitivity: Equatable, Sendable {
    case `public`
    case redact
    case hash
    case truncate(maxLength: Int)
}

public enum ReceiptPayloadValueKind: Equatable, Sendable {
    case chain
    case url
    case walletAddress
    case timestamp
    case label
    case errorMessage
    case copiedText
    case freeformText
    case opaqueToken
    case unknownString
    case number
    case bool
    case object
    case array
    case null
}

public struct ReceiptPayloadField: Equatable, Sendable {
    public let key: String
    public let value: ReceiptJSONValue
    public let sensitivity: ReceiptPayloadFieldSensitivity
    public let valueKind: ReceiptPayloadValueKind

    public init(
        key: String,
        value: ReceiptJSONValue,
        sensitivity: ReceiptPayloadFieldSensitivity,
        valueKind: ReceiptPayloadValueKind
    ) {
        self.key = key
        self.value = value
        self.sensitivity = sensitivity
        self.valueKind = valueKind
    }
}

/// Unsanitized input used at orchestration boundaries before persistence.
public struct RawReceiptPayload: Equatable, Sendable {
    public let fields: [ReceiptPayloadField]

    public init(fields: [ReceiptPayloadField]) {
        self.fields = fields
    }
}

public protocol TypedReceiptPayload {
    var fields: [ReceiptPayloadField] { get }
}

public extension TypedReceiptPayload {
    var rawPayload: RawReceiptPayload {
        RawReceiptPayload(fields: fields)
    }
}

public extension ReceiptPayloadField {
    static func `public`(_ key: String, string value: String, kind: ReceiptPayloadValueKind) -> ReceiptPayloadField {
        ReceiptPayloadField(
            key: key,
            value: .string(value),
            sensitivity: .public,
            valueKind: kind
        )
    }

    static func redacted(_ key: String, string value: String, kind: ReceiptPayloadValueKind) -> ReceiptPayloadField {
        ReceiptPayloadField(
            key: key,
            value: .string(value),
            sensitivity: .redact,
            valueKind: kind
        )
    }

    static func hashed(_ key: String, string value: String, kind: ReceiptPayloadValueKind) -> ReceiptPayloadField {
        ReceiptPayloadField(
            key: key,
            value: .string(value),
            sensitivity: .hash,
            valueKind: kind
        )
    }

    static func truncated(
        _ key: String,
        string value: String,
        kind: ReceiptPayloadValueKind,
        maxLength: Int
    ) -> ReceiptPayloadField {
        ReceiptPayloadField(
            key: key,
            value: .string(value),
            sensitivity: .truncate(maxLength: maxLength),
            valueKind: kind
        )
    }

    static func number(_ key: String, _ value: Double) -> ReceiptPayloadField {
        ReceiptPayloadField(
            key: key,
            value: .number(value),
            sensitivity: .public,
            valueKind: .number
        )
    }

    static func bool(_ key: String, _ value: Bool) -> ReceiptPayloadField {
        ReceiptPayloadField(
            key: key,
            value: .bool(value),
            sensitivity: .public,
            valueKind: .bool
        )
    }

    static func stringArray(
        _ key: String,
        values: [String],
        kind: ReceiptPayloadValueKind,
        sensitivity: ReceiptPayloadFieldSensitivity = .public
    ) -> ReceiptPayloadField {
        ReceiptPayloadField(
            key: key,
            value: .array(values.map(ReceiptJSONValue.string)),
            sensitivity: sensitivity,
            valueKind: .array
        )
    }

    static func null(_ key: String) -> ReceiptPayloadField {
        ReceiptPayloadField(
            key: key,
            value: .null,
            sensitivity: .public,
            valueKind: .null
        )
    }
}

/// Phase 0 append requests are immutable facts. The store adds identifiers and ordering metadata.
public struct ReceiptDraft: Equatable, Sendable {
    public let createdAt: Date
    public let actor: ReceiptActor
    public let mode: ReceiptMode
    public let trigger: String
    public let scope: String
    public let summary: String
    public let provenance: String
    public let isSuccess: Bool
    public let correlationID: String?
    public let timelineAccountAddress: String?
    public let timelineChainRawValue: String?
    public let details: ReceiptPayload

    public init(
        createdAt: Date = .now,
        actor: ReceiptActor = .system,
        mode: ReceiptMode = .observe,
        trigger: String,
        scope: String,
        summary: String,
        provenance: String,
        isSuccess: Bool,
        correlationID: String? = nil,
        timelineAccountAddress: String? = nil,
        timelineChainRawValue: String? = nil,
        details: ReceiptPayload
    ) {
        self.createdAt = createdAt
        self.actor = actor
        self.mode = mode
        self.trigger = trigger
        self.scope = scope
        self.summary = summary
        self.provenance = provenance
        self.isSuccess = isSuccess
        self.correlationID = correlationID
        self.timelineAccountAddress = timelineAccountAddress
        self.timelineChainRawValue = timelineChainRawValue
        self.details = details
    }

    public init(
        createdAt: Date = .now,
        category: String,
        kind: String,
        correlationID: String? = nil,
        payload: ReceiptPayload,
        actor: ReceiptActor = .system,
        mode: ReceiptMode = .observe,
        summary: String? = nil,
        provenance: String = "local",
        isSuccess: Bool = true,
        timelineAccountAddress: String? = nil,
        timelineChainRawValue: String? = nil
    ) {
        self.init(
            createdAt: createdAt,
            actor: actor,
            mode: mode,
            trigger: kind,
            scope: category,
            summary: summary ?? kind,
            provenance: provenance,
            isSuccess: isSuccess,
            correlationID: correlationID,
            timelineAccountAddress: timelineAccountAddress,
            timelineChainRawValue: timelineChainRawValue,
            details: payload
        )
    }
}

/// Receipt records are immutable historical facts. Append-only means stores may create and list them, export them, or reset the full collection.
public struct ReceiptRecord: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let sequenceID: Int
    public let createdAt: Date
    public let actor: ReceiptActor
    public let mode: ReceiptMode
    public let trigger: String
    public let scope: String
    public let summary: String
    public let provenance: String
    public let isSuccess: Bool
    public let correlationID: String?
    public let details: ReceiptPayload

    public init(
        id: UUID,
        sequenceID: Int,
        createdAt: Date,
        actor: ReceiptActor,
        mode: ReceiptMode,
        trigger: String,
        scope: String,
        summary: String,
        provenance: String,
        isSuccess: Bool,
        correlationID: String?,
        details: ReceiptPayload
    ) {
        self.id = id
        self.sequenceID = sequenceID
        self.createdAt = createdAt
        self.actor = actor
        self.mode = mode
        self.trigger = trigger
        self.scope = scope
        self.summary = summary
        self.provenance = provenance
        self.isSuccess = isSuccess
        self.correlationID = correlationID
        self.details = details
    }
}

public extension ReceiptDraft {
    public var category: String { scope }
    public var kind: String { trigger }
    public var payload: ReceiptPayload { details }
}

public extension ReceiptRecord {
    public var category: String { scope }
    public var kind: String { trigger }
    public var payload: ReceiptPayload { details }
}

/// Sanitization must happen before persistence so export can use persisted payloads directly.
public protocol ReceiptPayloadSanitizing {
    func sanitize(_ payload: RawReceiptPayload) -> ReceiptPayload
}

/// Append-only Phase 0 receipt storage surface.
///
/// Contract rules:
/// - `append` is the only write path for individual receipts
/// - normal reads must stay bounded
/// - `exportAll` is the only bulk-read path
/// - `resetAll` is a separate destructive operation, not a convenience delete helper
/// - stores must not invent correlation IDs
@MainActor
public protocol ReceiptStore {
    func append(_ receipt: ReceiptDraft) async throws -> ReceiptRecord
    func latest(limit: Int) throws -> [ReceiptRecord]
    func receipts(
        forCorrelationID correlationID: String,
        limit: Int
    ) throws -> [ReceiptRecord]
    func exportAll() throws -> Data
    func resetAll() async throws
}
