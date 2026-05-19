import AuralisPrimaryModels
import Foundation
import OSLog
import SwiftData

@Model
public final class StoredReceipt {
    #Index<StoredReceipt>(
        [\.correlationID],
        [\.createdAt, \.sequenceID],
        [\.accountAddress, \.chainRawValue, \.createdAt, \.sequenceID]
    )

    private static let logger = Logger(subsystem: "Auralis", category: "StoredReceipt")

    @Attribute(.unique) public var id: UUID
    public var sequenceID: Int
    public var createdAt: Date
    public var actorRawValue: String
    public var modeRawValue: String
    public var trigger: String
    public var scope: String
    public var summary: String
    public var provenance: String
    public var isSuccess: Bool
    public var correlationID: String?
    public var accountAddress: String?
    public var chainRawValue: String?
    public var accountSequenceID: Int
    public var payloadHash: String
    public var previousReceiptHash: String
    public var chainHash: String
    @Attribute(.externalStorage) private var detailsData: Data

    public init(
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
        timelineAccountAddress: String? = nil,
        timelineChainRawValue: String? = nil,
        accountSequenceID: Int,
        payloadHash: String,
        previousReceiptHash: String,
        chainHash: String,
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
        self.accountAddress = timelineAccountAddress ?? details.timelineAccountAddress
        self.chainRawValue = timelineChainRawValue ?? details.timelineChainRawValue
        self.accountSequenceID = accountSequenceID
        self.payloadHash = payloadHash
        self.previousReceiptHash = previousReceiptHash
        self.chainHash = chainHash
        self.detailsData = try Self.encodeDetails(details)
    }

    public var actor: ReceiptActor {
        get { ReceiptActor(rawValue: actorRawValue) ?? .system }
        set { actorRawValue = newValue.rawValue }
    }

    public var mode: ReceiptMode {
        get { ReceiptMode(rawValue: modeRawValue) ?? .observe }
        set { modeRawValue = newValue.rawValue }
    }

    public var category: String {
        scope
    }

    public var kind: String {
        trigger
    }

    public func decodedDetails() throws -> ReceiptPayload {
        try Self.decodeDetails(from: detailsData)
    }

    public func decodedPayload() throws -> ReceiptPayload {
        try decodedDetails()
    }

    public func decodedDetailsOrEmpty() -> ReceiptPayload {
        do {
            return try decodedDetails()
        } catch {
            Self.logger.error(
                "Falling back to empty receipt payload for receipt id=\(self.id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return ReceiptPayload(values: [:])
        }
    }

    public static func encodeDetails(_ details: ReceiptPayload) throws -> Data {
        try JSONEncoder().encode(details)
    }

    public static func decodeDetails(from data: Data) throws -> ReceiptPayload {
        try JSONDecoder().decode(ReceiptPayload.self, from: data)
    }
}

private extension ReceiptPayload {
    var timelineAccountAddress: String? {
        AuralisEthereumAddress.normalized(value(forKeys: ["accountAddress", "address"]))
    }

    var timelineChainRawValue: String? {
        guard let rawValue = value(forKeys: ["chain", "to_chain"]) else {
            return nil
        }

        return Chain(rawValue: rawValue)?.rawValue
    }

    func value(forKeys keys: [String]) -> String? {
        for key in keys {
            if case .string(let value)? = values[key] {
                return value
            }
        }

        return nil
    }
}
