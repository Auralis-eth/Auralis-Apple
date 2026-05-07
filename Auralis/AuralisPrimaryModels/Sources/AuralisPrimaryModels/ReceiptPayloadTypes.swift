import Foundation

/// JSON-compatible payload value used by receipts before export.
public enum ReceiptJSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: ReceiptJSONValue])
    case array([ReceiptJSONValue])
    case null

    public init(from decoder: any Decoder) throws {
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

    public func encode(to encoder: any Encoder) throws {
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
public struct ReceiptPayload: Codable, Equatable, Sendable {
    public let values: [String: ReceiptJSONValue]

    public init(values: [String: ReceiptJSONValue]) {
        self.values = values
    }
}

public enum ReceiptActor: String, Codable, Equatable, Sendable {
    case user
    case system
}

public enum ReceiptMode: String, Codable, Equatable, Sendable {
    case observe = "Observe"
}
