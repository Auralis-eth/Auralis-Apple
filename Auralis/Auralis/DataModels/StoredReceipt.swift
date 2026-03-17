import Foundation
import SwiftData

/// SwiftData-backed Phase 0 receipt row.
///
/// This model persists the contract fields locked by `P0-501`:
/// - stable identifier
/// - monotonic sequence identifier
/// - created-at timestamp
/// - event category and kind
/// - optional caller-provided correlation ID
/// - sanitized payload encoded as export-safe JSON bytes
@Model
final class StoredReceipt {
    @Attribute(.unique) var id: UUID
    var sequenceID: Int
    var createdAt: Date
    var category: String
    var kind: String
    var correlationID: String?
    @Attribute(.externalStorage) private var payloadData: Data

    init(
        id: UUID = UUID(),
        sequenceID: Int,
        createdAt: Date,
        category: String,
        kind: String,
        correlationID: String? = nil,
        payload: ReceiptPayload
    ) throws {
        self.id = id
        self.sequenceID = sequenceID
        self.createdAt = createdAt
        self.category = category
        self.kind = kind
        self.correlationID = correlationID
        self.payloadData = try Self.encodePayload(payload)
    }

    func decodedPayload() throws -> ReceiptPayload {
        try Self.decodePayload(from: payloadData)
    }

    static func encodePayload(_ payload: ReceiptPayload) throws -> Data {
        try JSONEncoder().encode(payload)
    }

    static func decodePayload(from data: Data) throws -> ReceiptPayload {
        try JSONDecoder().decode(ReceiptPayload.self, from: data)
    }
}
