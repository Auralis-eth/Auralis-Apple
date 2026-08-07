import Foundation

public enum WalletJSONValue: Hashable, Codable, Sendable {
    case string(String)
    case bool(Bool)
    case int(Int)
    case double(Double)
    case array([WalletJSONValue])
    case object([String: WalletJSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([WalletJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: WalletJSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported wallet JSON value.")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var objectValue: [String: WalletJSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    public var arrayValue: [WalletJSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var jsonObject: Any? {
        switch self {
        case .string(let value):
            return value
        case .bool(let value):
            return value
        case .int(let value):
            return value
        case .double(let value):
            return value
        case .array(let values):
            return values.map(\.jsonObject)
        case .object(let values):
            return values.mapValues { $0.jsonObject }
        case .null:
            return nil
        }
    }
}

public extension WalletJSONValue {
    static func strings(_ values: [String]) -> [WalletJSONValue] {
        values.map(WalletJSONValue.string)
    }
}
