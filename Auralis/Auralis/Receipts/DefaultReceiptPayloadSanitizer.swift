import CryptoKit
import Foundation

struct DefaultReceiptPayloadSanitizer: ReceiptPayloadSanitizing {
    private let suspiciousKeyFragments: Set<String> = [
        "apikey",
        "api_key",
        "authorization",
        "auth",
        "bearer",
        "cookie",
        "copied",
        "error",
        "rpc",
        "secret",
        "token",
        "url",
        "value"
    ]

    func sanitize(_ payload: RawReceiptPayload) -> ReceiptPayload {
        ReceiptPayload(
            values: Dictionary(
                uniqueKeysWithValues: payload.fields.map { field in
                    (field.key, sanitize(field))
                }
            )
        )
    }
}

private extension DefaultReceiptPayloadSanitizer {
    func sanitize(_ field: ReceiptPayloadField) -> ReceiptJSONValue {
        switch field.value {
        case .string(let stringValue):
            return sanitizeString(field: field, stringValue: stringValue)
        case .object(let object):
            return .object(sanitizeObject(object))
        case .array(let values):
            return .array(values.map { sanitizeArrayValue($0, parentField: field) })
        case .number, .bool, .null:
            return field.value
        }
    }

    func sanitizeArrayValue(_ value: ReceiptJSONValue, parentField: ReceiptPayloadField) -> ReceiptJSONValue {
        switch value {
        case .string(let stringValue):
            return sanitizeString(field: parentField, stringValue: stringValue)
        case .object(let object):
            return .object(sanitizeObject(object))
        case .array(let values):
            return .array(values.map { sanitizeArrayValue($0, parentField: parentField) })
        case .number, .bool, .null:
            return value
        }
    }

    func sanitizeObject(_ object: [String: ReceiptJSONValue]) -> [String: ReceiptJSONValue] {
        Dictionary(
            uniqueKeysWithValues: object.map { key, value in
                let inferredField = ReceiptPayloadField(
                    key: key,
                    value: value,
                    sensitivity: inferredSensitivity(forKey: key, value: value),
                    valueKind: inferredValueKind(forKey: key, value: value)
                )
                return (key, sanitize(inferredField))
            }
        )
    }

    func sanitizeString(field: ReceiptPayloadField, stringValue: String) -> ReceiptJSONValue {
        let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .string("")
        }

        let effectiveKind = resolvedValueKind(for: field, stringValue: trimmed)
        let effectiveSensitivity = resolvedSensitivity(for: field, kind: effectiveKind, stringValue: trimmed)

        switch effectiveSensitivity {
        case .public:
            return sanitizePublicString(trimmed, kind: effectiveKind)
        case .redact:
            return .string(redactedPlaceholder(for: effectiveKind))
        case .hash:
            return .string(hashedValue(trimmed))
        case .truncate(let maxLength):
            return .string(truncatedValue(trimmed, maxLength: maxLength))
        }
    }

    func sanitizePublicString(_ value: String, kind: ReceiptPayloadValueKind) -> ReceiptJSONValue {
        switch kind {
        case .url:
            return .string(structurallySanitizedURLString(value))
        case .walletAddress:
            return .string(maskedWalletAddress(value))
        case .errorMessage:
            return .string("<redacted-error>")
        case .copiedText:
            return .string("<redacted-copied-value>")
        case .freeformText:
            return .string(truncatedValue(value, maxLength: 48))
        case .opaqueToken:
            return .string(hashedValue(value))
        case .unknownString:
            return .string("<redacted-unclassified-string>")
        case .chain, .timestamp, .label:
            return .string(value)
        case .number, .bool, .object, .array, .null:
            return .string("<redacted-unexpected-string>")
        }
    }

    func resolvedSensitivity(
        for field: ReceiptPayloadField,
        kind: ReceiptPayloadValueKind,
        stringValue: String
    ) -> ReceiptPayloadFieldSensitivity {
        if keyLooksSensitive(field.key) {
            return .redact
        }

        switch kind {
        case .url:
            return .public
        case .walletAddress:
            return field.sensitivity == .public ? .public : .hash
        case .chain, .timestamp, .label:
            return field.sensitivity
        case .errorMessage, .copiedText:
            return .redact
        case .freeformText:
            return field.sensitivity == .public ? .truncate(maxLength: 48) : field.sensitivity
        case .opaqueToken, .unknownString:
            return .redact
        case .number, .bool, .object, .array, .null:
            return field.sensitivity
        }
    }

    func resolvedValueKind(for field: ReceiptPayloadField, stringValue: String) -> ReceiptPayloadValueKind {
        switch field.valueKind {
        case .unknownString:
            return inferredValueKind(forKey: field.key, value: .string(stringValue))
        default:
            if looksLikeOpaqueToken(stringValue) {
                return .opaqueToken
            }
            if looksLikeRPCURL(stringValue) || looksLikeURL(stringValue) {
                return .url
            }
            if looksLikeWalletAddress(stringValue) {
                return .walletAddress
            }
            return field.valueKind
        }
    }

    func inferredSensitivity(forKey key: String, value: ReceiptJSONValue) -> ReceiptPayloadFieldSensitivity {
        switch value {
        case .string:
            return keyLooksSensitive(key) ? .redact : .public
        case .number, .bool, .null, .object, .array:
            return .public
        }
    }

    func inferredValueKind(forKey key: String, value: ReceiptJSONValue) -> ReceiptPayloadValueKind {
        let normalizedKey = normalized(key)
        switch value {
        case .string(let stringValue):
            if normalizedKey.contains("chain") {
                return .chain
            }
            if normalizedKey.contains("time") || normalizedKey.contains("date") {
                return .timestamp
            }
            if normalizedKey.contains("label") || normalizedKey.contains("kind") || normalizedKey.contains("subject") || normalizedKey.contains("surface") {
                return .label
            }
            if normalizedKey.contains("error") {
                return .errorMessage
            }
            if normalizedKey.contains("copy") || normalizedKey == "value" {
                return .copiedText
            }
            if normalizedKey.contains("url") || looksLikeURL(stringValue) {
                return .url
            }
            if normalizedKey.contains("address") || looksLikeWalletAddress(stringValue) {
                return .walletAddress
            }
            if looksLikeOpaqueToken(stringValue) {
                return .opaqueToken
            }
            return .unknownString
        case .number:
            return .number
        case .bool:
            return .bool
        case .object:
            return .object
        case .array:
            return .array
        case .null:
            return .null
        }
    }

    func normalized(_ key: String) -> String {
        key.replacingOccurrences(of: "-", with: "_").lowercased()
    }

    func keyLooksSensitive(_ key: String) -> Bool {
        let normalizedKey = normalized(key)
        return suspiciousKeyFragments.contains { normalizedKey.contains($0) }
    }

    func looksLikeWalletAddress(_ value: String) -> Bool {
        value.range(of: #"^0x[a-fA-F0-9]{40}$"#, options: .regularExpression) != nil
    }

    func looksLikeURL(_ value: String) -> Bool {
        URL(string: value)?.scheme != nil
    }

    func looksLikeRPCURL(_ value: String) -> Bool {
        guard let url = URL(string: value), let host = url.host?.lowercased() else {
            return false
        }

        return host.contains("alchemy.com")
            || host.contains("infura.io")
            || host.contains("rpc")
    }

    func looksLikeOpaqueToken(_ value: String) -> Bool {
        guard value.count >= 24 else {
            return false
        }

        return value.range(
            of: #"^[A-Za-z0-9_\-]{24,}$"#,
            options: .regularExpression
        ) != nil
    }

    func structurallySanitizedURLString(_ value: String) -> String {
        guard let components = URLComponents(string: value) else {
            return "<redacted-url>"
        }

        let scheme = components.scheme ?? "unknown"
        let host = components.host ?? "unknown-host"
        let hasPath = !(components.path.isEmpty || components.path == "/")
        let hasQuery = !(components.queryItems?.isEmpty ?? true)
        let pathSuffix = hasPath ? "/<redacted-path>" : ""
        let querySuffix = hasQuery ? "?<redacted-query>" : ""
        return "\(scheme)://\(host)\(pathSuffix)\(querySuffix)"
    }

    func maskedWalletAddress(_ value: String) -> String {
        guard value.count > 10 else {
            return "<redacted-wallet-address>"
        }

        let prefix = value.prefix(6)
        let suffix = value.suffix(4)
        return "\(prefix)…\(suffix)"
    }

    func hashedValue(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        let hex = digest.compactMap { String(format: "%02x", $0) }.joined()
        return "sha256:\(hex)"
    }

    func truncatedValue(_ value: String, maxLength: Int) -> String {
        guard value.count > maxLength, maxLength > 0 else {
            return value
        }

        return "\(value.prefix(maxLength))…"
    }

    func redactedPlaceholder(for kind: ReceiptPayloadValueKind) -> String {
        switch kind {
        case .url:
            return "<redacted-url>"
        case .walletAddress:
            return "<redacted-wallet-address>"
        case .errorMessage:
            return "<redacted-error>"
        case .copiedText:
            return "<redacted-copied-value>"
        case .freeformText:
            return "<redacted-freeform-text>"
        case .opaqueToken:
            return "<redacted-opaque-token>"
        case .unknownString:
            return "<redacted-unclassified-string>"
        case .chain:
            return "<redacted-chain>"
        case .timestamp:
            return "<redacted-timestamp>"
        case .label:
            return "<redacted-label>"
        case .number, .bool, .object, .array, .null:
            return "<redacted-string>"
        }
    }
}
