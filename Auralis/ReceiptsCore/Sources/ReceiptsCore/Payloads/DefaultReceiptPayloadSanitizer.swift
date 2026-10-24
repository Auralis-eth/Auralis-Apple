import AuralisPrimaryModels
import CryptoKit
import Foundation

public struct DefaultReceiptPayloadSanitizer: ReceiptPayloadSanitizing {
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

    public init() { }

    public func sanitize(_ payload: RawReceiptPayload) -> ReceiptPayload {
        // Last value wins rather than trapping. `RawReceiptPayload.fields` is an array and never
        // deduplicates, and writers build it by conditional `append`, so the same key arriving twice
        // is reachable input — `Dictionary(uniqueKeysWithValues:)` would crash the app on the receipt
        // write path, which is the one path that must not take the process down.
        ReceiptPayload(
            values: Dictionary(
                payload.fields.map { field in
                    (field.key, sanitize(field))
                },
                uniquingKeysWith: { _, last in last }
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
            return sanitizeString(field: elementField(of: parentField), stringValue: stringValue)
        case .object(let object):
            return .object(sanitizeObject(object))
        case .array(let values):
            return .array(values.map { sanitizeArrayValue($0, parentField: parentField) })
        case .number, .bool, .null:
            return value
        }
    }

    /// The field an array *element* is classified against.
    ///
    /// Classifying elements against the parent verbatim meant they inherited `valueKind == .array`,
    /// and `.array` is not a string kind — so `sanitizePublicString` fell to its
    /// `<redacted-unexpected-string>` default and every element of every array was replaced by a
    /// placeholder. The declared element kind (see ``ReceiptPayloadField/elementValueKind``) is the
    /// one the writer actually meant; absent one, keep the old parent kind so nothing silently
    /// becomes *less* redacted than it was.
    ///
    /// The key is carried over deliberately: `keyLooksSensitive` is checked per element and must
    /// still win, so an array under an `apiKeys` key stays redacted whatever its elements claim.
    func elementField(of parentField: ReceiptPayloadField) -> ReceiptPayloadField {
        guard let elementValueKind = parentField.elementValueKind else { return parentField }
        return ReceiptPayloadField(
            key: parentField.key,
            value: parentField.value,
            sensitivity: parentField.sensitivity,
            valueKind: elementValueKind,
            elementValueKind: elementValueKind
        )
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
            // Fully-structured, fixed-length forms are classified *ahead* of the opaque-token
            // heuristic, and a UUID is exempted from it outright.
            //
            // The heuristic is `count >= 24 && ^[A-Za-z0-9_\-]{24,}$`, which a 42-character `0x…`
            // address and a 36-character UUID both satisfy. Testing it first therefore overrode
            // every explicitly declared kind and persisted `<redacted-opaque-token>` in place of
            // the identifiers a receipt exists to record: a spend receipt could not name its
            // recipient, two different playlists produced byte-identical identity fields, and
            // `ReceiptContentPresenter.artifactIDs(in:)` found nothing because the UUIDs were
            // gone. It also made the `looksLikeWalletAddress` branch below unreachable for any
            // real 40-hex address.
            //
            // Safe because neither shape can launder a secret through the receipt: both are
            // fixed-length and fully structured — 40 hex digits, or 32 hex digits in the five
            // dash-separated groups `UUID(uuidString:)` accepts — so there is no room to smuggle
            // an arbitrary string inside one. An arbitrary 24+ character `[A-Za-z0-9_-]` run
            // genuinely can, which is why the heuristic stays: here for everything that is not one
            // of those two shapes, and in `inferredValueKind(forKey:value:)` for `.unknownString`.
            //
            // The inference itself is kept rather than skipped for declared kinds, because it also
            // *upgrades* a declared kind to `.url`/`.walletAddress` — a writer cannot publish a
            // provider URL or a bare address by labelling it `.label`.
            if looksLikeRPCURL(stringValue) || looksLikeURL(stringValue) {
                return .url
            }
            if looksLikeWalletAddress(stringValue) {
                return .walletAddress
            }
            if looksLikeOpaqueToken(stringValue), !looksLikeUUID(stringValue) {
                return .opaqueToken
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
            if normalizedKey.contains("title") {
                return .freeformText
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
            // The same UUID exemption `resolvedValueKind(for:stringValue:)` applies to declared
            // kinds, applied here to *undeclared* ones — which is what every key nested inside an
            // `.object` payload value is, because `sanitizeObject` has no writer-supplied kind to
            // carry and infers one from the key alone.
            //
            // Without it the declared-kind fix was only half a fix. `MusicReceiptStateSummary`
            // puts `playlistID` inside its `beforeSummary`/`afterSummary` objects, so the
            // top-level field recorded the playlist while the before/after pair recorded
            // `<redacted-opaque-token>` — the same receipt disagreeing with itself about whether
            // it knows which playlist it describes.
            //
            // Safe for the same reason, and for one more that is specific to this path: a UUID is
            // 32 hex digits in five dash-separated groups, so there is no room to smuggle an
            // arbitrary string inside one; and `resolvedSensitivity(for:kind:stringValue:)` tests
            // `keyLooksSensitive(field.key)` *before* it looks at the kind, so a UUID-shaped value
            // under a key naming a token, secret, or credential is still redacted on the strength
            // of its key. Widening the kind cannot widen the sensitivity.
            //
            // `.label`, not `.unknownString`: an identifier is a thing the receipt means to state,
            // and `.unknownString` resolves to `.redact`, which is the defect being fixed.
            if looksLikeUUID(stringValue) {
                return .label
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
        AuralisEthereumAddress.normalized(value) != nil
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

    /// A UUID-shaped string, which ``resolvedValueKind(for:stringValue:)`` exempts from the
    /// opaque-token heuristic.
    ///
    /// `UUID(uuidString:)` rather than a regex because it is the same parser
    /// ``ReceiptContentPresenter/artifactIDs(in:)`` reads the value back with: anything it accepts
    /// here is exactly what that surface can recover, and nothing wider.
    func looksLikeUUID(_ value: String) -> Bool {
        UUID(uuidString: value) != nil
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
