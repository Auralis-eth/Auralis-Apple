//
//  AnyValue.swift
//  Auralis
//
//  Created by Daniel Bell on 3/29/25.
//

import Foundation

enum AnyValue: Codable, Equatable {
    case string(String)
    case integer(Int)
    case double(Double)
    case boolean(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let integer = try? container.decode(Int.self) {
            self = .integer(integer)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let boolean = try? container.decode(Bool.self) {
            self = .boolean(boolean)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Value cannot be decoded as any supported type"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let value):
            try container.encode(value)
        case .integer(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .boolean(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    static func == (lhs: AnyValue, rhs: AnyValue) -> Bool {
        switch (lhs, rhs) {
        case (.string(let l), .string(let r)): return l == r
        case (.integer(let l), .integer(let r)): return l == r
        case (.double(let l), .double(let r)): return l == r
        case (.boolean(let l), .boolean(let r)): return l == r
        case (.null, .null): return true
        default: return false
        }
    }
}

