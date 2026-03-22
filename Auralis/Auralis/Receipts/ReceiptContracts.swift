import Foundation

/// JSON-compatible payload value used by receipts before export.
enum ReceiptJSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: ReceiptJSONValue])
    case array([ReceiptJSONValue])
    case null

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: ReceiptJSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([ReceiptJSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported receipt JSON value."
            )
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

/// Persisted/exported payload wrapper so callers cannot hand raw unsanitized maps directly to the store.
struct ReceiptPayload: Codable, Equatable, Sendable {
    let values: [String: ReceiptJSONValue]
}

/// Unsanitized input used at orchestration boundaries before persistence.
struct RawReceiptPayload: Equatable, Sendable {
    let values: [String: ReceiptJSONValue]
}

enum ReceiptActor: String, Codable, Equatable, Sendable {
    case user
    case system
}

enum ReceiptMode: String, Codable, Equatable, Sendable {
    case observe = "Observe"
}

/// Phase 0 append requests are immutable facts. The store adds identifiers and ordering metadata.
struct ReceiptDraft: Equatable, Sendable {
    let createdAt: Date
    let actor: ReceiptActor
    let mode: ReceiptMode
    let trigger: String
    let scope: String
    let summary: String
    let provenance: String
    let isSuccess: Bool
    let correlationID: String?
    let details: ReceiptPayload

    init(
        createdAt: Date = .now,
        actor: ReceiptActor = .system,
        mode: ReceiptMode = .observe,
        trigger: String,
        scope: String,
        summary: String,
        provenance: String,
        isSuccess: Bool,
        correlationID: String? = nil,
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
        self.details = details
    }

    init(
        createdAt: Date = .now,
        category: String,
        kind: String,
        correlationID: String? = nil,
        payload: ReceiptPayload,
        actor: ReceiptActor = .system,
        mode: ReceiptMode = .observe,
        summary: String? = nil,
        provenance: String = "local",
        isSuccess: Bool = true
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
            details: payload
        )
    }
}

/// Receipt records are immutable historical facts. Append-only means stores may create and list them, export them, or reset the full collection.
struct ReceiptRecord: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let sequenceID: Int
    let createdAt: Date
    let actor: ReceiptActor
    let mode: ReceiptMode
    let trigger: String
    let scope: String
    let summary: String
    let provenance: String
    let isSuccess: Bool
    let correlationID: String?
    let details: ReceiptPayload
}

extension ReceiptDraft {
    var category: String { scope }
    var kind: String { trigger }
    var payload: ReceiptPayload { details }
}

extension ReceiptRecord {
    var category: String { scope }
    var kind: String { trigger }
    var payload: ReceiptPayload { details }
}

/// Sanitization must happen before persistence so export can use persisted payloads directly.
protocol ReceiptPayloadSanitizing {
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
protocol ReceiptStore {
    func append(_ receipt: ReceiptDraft) throws -> ReceiptRecord
    func latest(limit: Int) throws -> [ReceiptRecord]
    func receipts(
        forCorrelationID correlationID: String,
        limit: Int
    ) throws -> [ReceiptRecord]
    func exportAll() throws -> Data
    func resetAll() throws
}
