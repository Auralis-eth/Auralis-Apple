import Foundation
import SwiftData

/// SwiftData-backed Phase 0 receipt row.
///
/// This model persists the contract fields locked by `P0-501`:
/// - stable identifier
/// - monotonic sequence identifier
/// - created-at timestamp
/// - actor, mode, trigger, scope, summary, provenance, and success/failure
/// - optional caller-provided correlation ID
/// - sanitized details payload encoded as export-safe JSON bytes
@Model
final class StoredReceipt {
    @Attribute(.unique) var id: UUID
    var sequenceID: Int
    var createdAt: Date
    var actorRawValue: String
    var modeRawValue: String
    var trigger: String
    var scope: String
    var summary: String
    var provenance: String
    var isSuccess: Bool
    var correlationID: String?
    @Attribute(.externalStorage) private var detailsData: Data

    init(
        id: UUID = UUID(),
        sequenceID: Int,
        createdAt: Date,
        actor: ReceiptActor,
        mode: ReceiptMode,
        trigger: String,
        scope: String,
        summary: String,
        provenance: String,
        isSuccess: Bool,
        correlationID: String? = nil,
        details: ReceiptPayload
    ) throws {
        self.id = id
        self.sequenceID = sequenceID
        self.createdAt = createdAt
        self.actorRawValue = actor.rawValue
        self.modeRawValue = mode.rawValue
        self.trigger = trigger
        self.scope = scope
        self.summary = summary
        self.provenance = provenance
        self.isSuccess = isSuccess
        self.correlationID = correlationID
        self.detailsData = try Self.encodeDetails(details)
    }

    var actor: ReceiptActor {
        ReceiptActor(rawValue: actorRawValue) ?? .system
    }

    var mode: ReceiptMode {
        ReceiptMode(rawValue: modeRawValue) ?? .observe
    }

    var category: String {
        scope
    }

    var kind: String {
        trigger
    }

    func decodedDetails() throws -> ReceiptPayload {
        try Self.decodeDetails(from: detailsData)
    }

    func decodedPayload() throws -> ReceiptPayload {
        try decodedDetails()
    }

    static func encodeDetails(_ details: ReceiptPayload) throws -> Data {
        try JSONEncoder().encode(details)
    }

    static func decodeDetails(from data: Data) throws -> ReceiptPayload {
        try JSONDecoder().decode(ReceiptPayload.self, from: data)
    }
}
