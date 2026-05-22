import CryptoKit
import Foundation

enum ProviderErrorPayloadSanitizer {
    static func sanitizedMessage(
        from data: Data,
        parsedMessage: () -> String?
    ) -> String? {
        guard !data.isEmpty else { return nil }

        let fingerprint = fingerprint(for: data)
        guard let rawText = String(data: data, encoding: .utf8) else {
            return redactedMessage(reason: "non_utf8", fingerprint: fingerprint)
        }

        if containsSecretLikeContent(rawText) {
            return redactedMessage(reason: "secret_like", fingerprint: fingerprint)
        }

        guard isJSON(data) else {
            return redactedMessage(reason: "unclassified_body", fingerprint: fingerprint)
        }

        guard let message = parsedMessage()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !message.isEmpty else {
            return redactedMessage(reason: "unclassified_json", fingerprint: fingerprint)
        }

        return sanitizedProviderMessage(message, fingerprint: fingerprint)
    }

    static func sanitizedProviderMessage(
        _ message: String,
        fallbackReason: String = "unsafe_message"
    ) -> String {
        let fingerprint = fingerprint(for: Data(message.utf8))
        return sanitizedProviderMessage(message, fallbackReason: fallbackReason, fingerprint: fingerprint)
    }

    static func fingerprint(for data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func sanitizedProviderMessage(
        _ message: String,
        fallbackReason: String = "unsafe_message",
        fingerprint: String
    ) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return redactedMessage(reason: "empty_message", fingerprint: fingerprint)
        }

        if containsSecretLikeContent(trimmed) || looksLikeStructuredPayload(trimmed) {
            return redactedMessage(reason: fallbackReason, fingerprint: fingerprint)
        }

        guard isExplicitlyPublicProviderMessage(trimmed) else {
            return redactedMessage(reason: "unclassified_message", fingerprint: fingerprint)
        }

        return trimmed
    }

    private static func redactedMessage(reason: String, fingerprint: String) -> String {
        "provider_error_payload_redacted reason=\(reason) sha256=\(fingerprint)"
    }

    private static func isJSON(_ data: Data) -> Bool {
        (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    private static func looksLikeStructuredPayload(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("{") || trimmed.hasPrefix("[")
    }

    private static func containsSecretLikeContent(_ value: String) -> Bool {
        secretLikePatterns.contains { pattern in
            value.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    private static func isExplicitlyPublicProviderMessage(_ value: String) -> Bool {
        publicProviderMessagePatterns.contains { pattern in
            value.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    private static let publicProviderMessagePatterns = [
        #"^rate limit(?:ed)?(?: exceeded)?(?: for 0x[0-9a-f]{40})?$"#,
        #"^too many requests(?: for 0x[0-9a-f]{40})?$"#,
        #"^method not found$"#,
    ]

    private static let secretLikePatterns = [
        #""?(authorization|access[_-]?token|refresh[_-]?token|id[_-]?token|bearer|cookie|set-cookie|private[_-]?key|seed|mnemonic|password|secret|api[_-]?key)"?\s*[:=]"#,
        #"bearer\s+[A-Za-z0-9._~+/=-]{8,}"#,
        #"-----BEGIN\s+(EC\s+|RSA\s+|OPENSSH\s+)?PRIVATE\s+KEY-----"#,
        #"\b(seed phrase|mnemonic phrase)\b"#,
    ]
}
