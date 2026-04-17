@testable import Auralis
import Foundation
import Testing

@Suite
struct ReceiptSanitizerTests {
    private let sanitizer = DefaultReceiptPayloadSanitizer()

    @Test("sanitizer redacts raw RPC URL and raw error string fields recursively before persistence")
    func sanitizerRedactsSensitiveFields() {
        let rawPayload = RawReceiptPayload(
            fields: [
                .hashed("rpcURL", string: "https://base-mainnet.g.alchemy.com/v2/secret", kind: .opaqueToken),
                .public("error", string: "request failed with provider details", kind: .errorMessage),
                .number("count", 2),
                ReceiptPayloadField(
                    key: "nested",
                    value: .object([
                        "rpcUrl": .string("https://another-provider.example"),
                        "errorMessage": .string("nested failure"),
                        "ok": .bool(true)
                    ]),
                    sensitivity: .public,
                    valueKind: .object
                ),
                ReceiptPayloadField(
                    key: "events",
                    value: .array([
                        .object([
                            "rawError": .string("leaf failure"),
                            "raw_rpc_url": .string("https://leaf-provider.example")
                        ]),
                        .string("safe")
                    ]),
                    sensitivity: .public,
                    valueKind: .array
                )
            ]
        )

        let sanitized = sanitizer.sanitize(rawPayload)

        guard case .string(let rpcURLValue)? = sanitized.values["rpcURL"] else {
            Issue.record("Expected rpcURL string")
            return
        }
        #expect(rpcURLValue == "<redacted-url>")
        #expect(sanitized.values["error"] == .string("<redacted-error>"))
        #expect(sanitized.values["count"] == .number(2))

        guard case .object(let nested)? = sanitized.values["nested"] else {
            Issue.record("Expected nested object")
            return
        }

        #expect(nested["rpcUrl"] == .string("<redacted-url>"))
        #expect(nested["errorMessage"] == .string("<redacted-error>"))
        #expect(nested["ok"] == .bool(true))

        guard case .array(let events)? = sanitized.values["events"],
              case .object(let firstEvent) = events.first else {
            Issue.record("Expected nested array object")
            return
        }

        #expect(firstEvent["rawError"] == .string("<redacted-error>"))
        #expect(firstEvent["raw_rpc_url"] == .string("<redacted-url>"))
    }

    @Test("sanitizer only redacts the locked Phase 0 fields and leaves unrelated strings untouched")
    func sanitizerLeavesUnrelatedStringsAlone() {
        let rawPayload = RawReceiptPayload(
            fields: [
                .public("message", string: "keep this", kind: .label),
                .public("provider", string: "alchemy", kind: .label),
                .public("status", string: "error", kind: .label),
                ReceiptPayloadField(
                    key: "details",
                    value: .object([
                        "kind": .string("error"),
                        "reason": .string("still keep this")
                    ]),
                    sensitivity: .public,
                    valueKind: .object
                )
            ]
        )

        let sanitized = sanitizer.sanitize(rawPayload)

        #expect(sanitized.values["message"] == .string("keep this"))
        #expect(sanitized.values["provider"] == .string("alchemy"))
        #expect(sanitized.values["status"] == .string("error"))

        guard case .object(let details)? = sanitized.values["details"] else {
            Issue.record("Expected details object")
            return
        }

        #expect(details["kind"] == .string("error"))
        #expect(details["reason"] == .string("<redacted-unclassified-string>"))
    }
}
