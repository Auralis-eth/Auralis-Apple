import CapabilitiesCore
import Foundation

/// A named field in a tool's input or output schema.
public struct ToolSchemaField: Equatable, Sendable, Codable {
    public enum Kind: String, Sendable, Codable {
        case string
        case number
        case bool
        case address
        case chain
        case chainID
        case unsignedQuantity
        case hexData
        case transactionHash
        case signature
        case uuid
    }

    public let name: String
    public let kind: Kind
    public let isRequired: Bool
    public let allowedValues: [String]

    public init(
        name: String,
        kind: Kind,
        isRequired: Bool = true,
        allowedValues: [String] = []
    ) {
        self.name = name
        self.kind = kind
        self.isRequired = isRequired
        self.allowedValues = allowedValues
    }
}

extension ToolSchemaField.Kind {
    /// Whether `character` is an ASCII hexadecimal digit.
    ///
    /// Explicitly ASCII-restricted, because `Character.isHexDigit` is not: it is true for the
    /// fullwidth forms (`０`–`９`, U+FF10…) and other Unicode digit variants, so a 40-character
    /// address made entirely of fullwidth digits satisfied a plain `allSatisfy(\.isHexDigit)`. That
    /// address then cleared ``AddressFormatCheck`` too — the same permissive test sits under
    /// `AuralisEthereumAddress`, and with no cased letters to test, EIP-55 classified it
    /// `.unchecksummed`, which is a *warning* rather than a failure — so a confusable address reached
    /// `draftTransaction`, the high-risk path. ``ENSNameFormatCheck`` already refuses this whole
    /// class of homoglyph for names and documents why; hex fields get the same rule.
    static func isASCIIHexDigit(_ character: Character) -> Bool {
        character.isASCII && character.isHexDigit
    }

    /// Whether `character` is an ASCII decimal digit.
    ///
    /// ASCII-restricted for the reason above: `Character.isNumber` is true for Arabic-Indic digits
    /// (`١٢٣`), fractions, and other numeric scalars, none of which any downstream quantity parser
    /// accepts. Admitting them here turned a rejectable proposal into one that failed later, past
    /// the point where governance could explain why.
    static func isASCIIDigit(_ character: Character) -> Bool {
        character.isASCII && character.isNumber
    }

    /// Returns a human-readable problem if `value` is not well-formed for this kind, else `nil`.
    /// This is deliberately shallow well-formedness (address shape, numeric parse, boolean literal) —
    /// scope/allowlist judgments (e.g. which chains are permitted) stay in deterministic checks.
    func validationProblem(for value: String) -> String? {
        switch self {
        case .string:
            return value.isEmpty ? "must not be empty" : nil
        case .number:
            return Double(value) == nil ? "must be a number" : nil
        case .bool:
            return (value == "true" || value == "false") ? nil : "must be “true” or “false”"
        case .address:
            guard value.hasPrefix("0x") else { return "must be a 0x-prefixed 40-hex address" }
            let hex = String(value.dropFirst(2))
            let valid = hex.count == 40 && hex.allSatisfy(Self.isASCIIHexDigit)
            return valid ? nil : "must be a 0x-prefixed 40-hex address"
        case .chain:
            return value.isEmpty ? "must name a chain" : nil
        case .chainID:
            var candidate = value.lowercased()
            if candidate.hasPrefix("eip155:") {
                candidate = String(candidate.dropFirst("eip155:".count))
            }
            if candidate.hasPrefix("0x") {
                let digits = candidate.dropFirst(2)
                return !digits.isEmpty && digits.allSatisfy(Self.isASCIIHexDigit)
                    ? nil
                    : "must be a positive decimal, hexadecimal, or eip155 chain ID"
            }
            guard let parsed = UInt64(candidate), parsed > 0 else {
                return "must be a positive decimal, hexadecimal, or eip155 chain ID"
            }
            return nil
        case .unsignedQuantity:
            if value.hasPrefix("0x") {
                let digits = value.dropFirst(2)
                return !digits.isEmpty && digits.allSatisfy(Self.isASCIIHexDigit)
                    ? nil
                    : "must be an unsigned decimal or 0x-prefixed hexadecimal quantity"
            }
            return !value.isEmpty && value.allSatisfy(Self.isASCIIDigit)
                ? nil
                : "must be an unsigned decimal or 0x-prefixed hexadecimal quantity"
        case .hexData:
            guard value.hasPrefix("0x") else { return "must be 0x-prefixed hexadecimal data" }
            let hex = value.dropFirst(2)
            return hex.count.isMultiple(of: 2) && hex.allSatisfy(Self.isASCIIHexDigit)
                ? nil
                : "must be 0x-prefixed, even-length hexadecimal data"
        case .transactionHash:
            guard value.hasPrefix("0x") else { return "must be a 0x-prefixed 32-byte hash" }
            let hex = value.dropFirst(2)
            return hex.count == 64 && hex.allSatisfy(Self.isASCIIHexDigit)
                ? nil
                : "must be a 0x-prefixed 32-byte hash"
        case .signature:
            guard value.hasPrefix("0x") else { return "must be a 0x-prefixed signature" }
            let hex = value.dropFirst(2)
            return !hex.isEmpty && hex.count.isMultiple(of: 2) && hex.allSatisfy(Self.isASCIIHexDigit)
                ? nil
                : "must be a 0x-prefixed, even-length hexadecimal signature"
        case .uuid:
            return UUID(uuidString: value) == nil ? "must be a UUID" : nil
        }
    }
}

/// A minimal declared schema for a tool's inputs or outputs.
public struct ToolSchema: Equatable, Sendable, Codable {
    public let fields: [ToolSchemaField]
    public let allowsAdditionalFields: Bool
    public let allowedAdditionalFieldPrefixes: [String]

    public init(
        fields: [ToolSchemaField] = [],
        allowsAdditionalFields: Bool = true,
        allowedAdditionalFieldPrefixes: [String] = []
    ) {
        self.fields = fields
        self.allowsAdditionalFields = allowsAdditionalFields
        self.allowedAdditionalFieldPrefixes = allowedAdditionalFieldPrefixes
    }

    public static let empty = ToolSchema()

    /// Validates `parameters` against this schema, returning one human-readable problem per offending
    /// field. An empty result means the parameters satisfy the schema. An empty schema always passes,
    /// so tools that don't declare a schema are unaffected.
    ///
    /// A present-but-empty value on a required field is treated as missing.
    public func validationProblems(against parameters: [String: String]) -> [String] {
        var problems: [String] = []
        for field in fields {
            guard let raw = parameters[field.name], !raw.isEmpty else {
                if field.isRequired {
                    problems.append("missing required field “\(field.name)”")
                }
                continue
            }
            if let problem = field.kind.validationProblem(for: raw) {
                problems.append("field “\(field.name)” \(problem)")
            }
            if !field.allowedValues.isEmpty, !field.allowedValues.contains(raw) {
                problems.append("field “\(field.name)” must be one of: \(field.allowedValues.joined(separator: ", "))")
            }
        }
        if !allowsAdditionalFields {
            let declared = Set(fields.map(\.name))
            let unexpected = parameters.keys
                .filter { key in
                    !declared.contains(key)
                        && !allowedAdditionalFieldPrefixes.contains { key.hasPrefix($0) }
                }
                .sorted()
            problems.append(contentsOf: unexpected.map { "unexpected field “\($0)”" })
        }
        return problems
    }

    public var definitionProblems: [String] {
        var problems: [String] = []
        let names = fields.map(\.name)
        if names.contains(where: \.isEmpty) {
            problems.append("schema field names must not be empty")
        }
        if Set(names).count != names.count {
            problems.append("schema field names must be unique")
        }
        if allowedAdditionalFieldPrefixes.contains(where: \.isEmpty) {
            problems.append("additional-field prefixes must not be empty")
        }
        return problems
    }
}

/// The governed contract for a runnable tool.
///
/// Distinct from `CapabilityDescriptor` (which is human-readable capability metadata): a
/// `ToolDefinition` binds a concrete tool to the capability it exercises, its impact class, the
/// deterministic checks it requires, and whether it must produce a receipt. The registry + pipeline
/// use these fields to gate execution.
public struct ToolDefinition: Identifiable, Equatable, Sendable, Codable {
    public let id: String
    public let title: String
    public let capability: CapabilityID
    public let impact: ActionImpactClass
    public let inputSchema: ToolSchema
    public let outputSchema: ToolSchema
    public let requiredCheckIDs: [String]
    public let requiresReceipt: Bool

    public init(
        id: String,
        title: String,
        capability: CapabilityID,
        impact: ActionImpactClass,
        inputSchema: ToolSchema = .empty,
        outputSchema: ToolSchema = .empty,
        requiredCheckIDs: [String] = [],
        requiresReceipt: Bool? = nil
    ) {
        self.id = id
        self.title = title
        self.capability = capability
        self.impact = impact
        self.inputSchema = inputSchema
        self.outputSchema = outputSchema
        self.requiredCheckIDs = requiredCheckIDs
        // Default the receipt requirement from the impact class unless the tool overrides it.
        self.requiresReceipt = requiresReceipt ?? impact.requiresReceipt
    }

    public var definitionProblems: [String] {
        var problems: [String] = []
        if id.isEmpty { problems.append("tool ID must not be empty") }
        if title.isEmpty { problems.append("tool title must not be empty") }
        if Set(requiredCheckIDs).count != requiredCheckIDs.count {
            problems.append("required deterministic-check IDs must be unique")
        }
        problems.append(contentsOf: inputSchema.definitionProblems.map { "input \($0)" })
        problems.append(contentsOf: outputSchema.definitionProblems.map { "output \($0)" })
        return problems
    }
}
