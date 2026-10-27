import CryptoKit
import Foundation

/// The privacy/handling class of a context field.
public enum ContextDataClass: String, Codable, CaseIterable, Sendable {
    case publicIdentifier
    case userProvided
    case localPreference
    case sensitive
    case derived
}

/// A closed vocabulary for sources trusted to contribute governed context.
///
/// Callers cannot manufacture an authoritative source by spelling an arbitrary string. Adding a new
/// source is an explicit kernel change, which makes source review and contract matching exhaustive.
public enum GovernedContextSource: String, Codable, CaseIterable, Sendable {
    case playbookDefinition
    case walletStore
    case chainProvider
    case localPreferences
    case worklogStore
    case runtimeHost
    case capabilityLeaseRegistry
    case operatorExecutor
    case receiptStore
    case runtimeEventBus
    case artifactStore
    case modelProvider
    case userProvided
    case localCache
}

/// The payload carried by a context field.
///
/// Sensitive bytes are deliberately not representable. A sensitive field may carry only an opaque
/// reference to a secret held by an injected vault, or an explicit redaction marker.
public enum ContextValue: Equatable, Sendable, Codable {
    case text(String)
    case sensitiveReference(String)
    case redacted

    public var operatorValue: String? {
        switch self {
        case let .text(value), let .sensitiveReference(value): return value
        case .redacted: return nil
        }
    }
}

/// One resolved field of context.
public struct ContextField: Codable, Equatable, Sendable {
    public let key: String
    public let value: ContextValue?
    public let dataClass: ContextDataClass
    public let source: GovernedContextSource?
    public let lastRefreshed: Date?

    /// Compatibility projection for presentation code. Redacted values never project a string.
    public var stringValue: String? { value?.operatorValue }

    /// Creates a non-sensitive field. Supplying a string for `.sensitive` always redacts it, so raw
    /// secret material cannot cross the type boundary even through legacy call sites.
    public init(
        key: String,
        stringValue: String?,
        dataClass: ContextDataClass,
        source: GovernedContextSource? = nil,
        lastRefreshed: Date? = nil
    ) {
        self.key = key
        if dataClass == .sensitive, stringValue != nil {
            value = .redacted
        } else {
            value = stringValue.map(ContextValue.text)
        }
        self.dataClass = dataClass
        self.source = source
        self.lastRefreshed = lastRefreshed
    }

    /// Creates a sensitive field using an opaque vault reference, never the secret itself.
    public init(
        key: String,
        sensitiveReference: String,
        source: GovernedContextSource,
        lastRefreshed: Date? = nil
    ) {
        self.key = key
        value = .sensitiveReference(sensitiveReference)
        dataClass = .sensitive
        self.source = source
        self.lastRefreshed = lastRefreshed
    }

    private enum CodingKeys: String, CodingKey {
        case key, value, stringValue, dataClass, source, lastRefreshed
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        dataClass = try container.decode(ContextDataClass.self, forKey: .dataClass)
        source = try container.decodeIfPresent(GovernedContextSource.self, forKey: .source)
        lastRefreshed = try container.decodeIfPresent(Date.self, forKey: .lastRefreshed)
        if let decoded = try container.decodeIfPresent(ContextValue.self, forKey: .value) {
            if dataClass == .sensitive, decoded.operatorValue != nil {
                if case .sensitiveReference = decoded {
                    value = decoded
                } else {
                    value = .redacted
                }
            } else {
                value = decoded
            }
        } else if let legacy = try container.decodeIfPresent(String.self, forKey: .stringValue) {
            value = dataClass == .sensitive ? .redacted : .text(legacy)
        } else {
            value = nil
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        try container.encodeIfPresent(value, forKey: .value)
        try container.encode(dataClass, forKey: .dataClass)
        try container.encodeIfPresent(source, forKey: .source)
        try container.encodeIfPresent(lastRefreshed, forKey: .lastRefreshed)
    }

}

/// A governed, contract-checkable bundle of context.
public struct ContextBundle: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2
    public static let maximumFieldCount = 64
    public static let maximumKeyByteCount = 128
    public static let maximumValueByteCount = 16 * 1_024
    public static let maximumAggregateByteCount = 64 * 1_024

    public let schemaVersion: Int
    public let fields: [ContextField]

    public init(schemaVersion: Int = Self.currentSchemaVersion, fields: [ContextField]) {
        self.schemaVersion = schemaVersion
        self.fields = fields
    }

    private enum CodingKeys: String, CodingKey { case schemaVersion, fields }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        fields = try container.decode([ContextField].self, forKey: .fields)
    }

    public func field(_ key: String) -> ContextField? { fields.first { $0.key == key } }

    /// Rejects bundles that could become blob-like context or exhaust workflow resources.
    public func sizeViolations() -> [String] {
        var violations: [String] = []
        if fields.count > Self.maximumFieldCount {
            violations.append("bundle contains more than \(Self.maximumFieldCount) fields")
        }

        var aggregateByteCount = 0
        for field in fields {
            let keyByteCount = field.key.utf8.count
            let valueByteCount: Int
            switch field.value {
            case let .text(value), let .sensitiveReference(value): valueByteCount = value.utf8.count
            case .redacted, nil: valueByteCount = 0
            }
            aggregateByteCount += keyByteCount + valueByteCount
            if keyByteCount > Self.maximumKeyByteCount {
                violations.append("field key exceeds \(Self.maximumKeyByteCount) bytes")
            }
            if valueByteCount > Self.maximumValueByteCount {
                violations.append("field “\(field.key)” exceeds \(Self.maximumValueByteCount) value bytes")
            }
        }
        if aggregateByteCount > Self.maximumAggregateByteCount {
            violations.append("bundle exceeds \(Self.maximumAggregateByteCount) aggregate bytes")
        }
        return violations
    }

    /// Stable evidence for receipts/worklogs without recording field values.
    public func evidenceDigest() -> String {
        let manifest = fields
            .map { field in
                let valueCommitment = Self.valueCommitment(field.value)
                return "\(field.key)|\(field.dataClass.rawValue)|\(field.source?.rawValue ?? "none")|\(field.lastRefreshed?.timeIntervalSince1970 ?? 0)|\(valueCommitment)"
            }
            .sorted()
            .joined(separator: "\n")
        return SHA256.hash(data: Data("v\(schemaVersion)\n\(manifest)".utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// Commits the audit digest to the value without placing that value in logs or receipts.
    /// The case tag prevents equal strings in different value domains from sharing a commitment.
    private static func valueCommitment(_ value: ContextValue?) -> String {
        let canonicalValue: String
        switch value {
        case let .text(text):
            canonicalValue = "text:\(text.utf8.count):\(text)"
        case let .sensitiveReference(reference):
            // This is an opaque vault handle, never secret bytes. Hashing still keeps the handle out
            // of audit output while binding the run to the exact approved reference.
            canonicalValue = "sensitiveReference:\(reference.utf8.count):\(reference)"
        case .redacted:
            canonicalValue = "redacted"
        case nil:
            canonicalValue = "nil"
        }
        return SHA256.hash(data: Data(canonicalValue.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
