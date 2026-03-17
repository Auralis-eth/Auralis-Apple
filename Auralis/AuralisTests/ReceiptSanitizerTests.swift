import Foundation
import Testing
@testable import Auralis

@Suite
struct ReceiptSanitizerTests {
    private let sanitizer = DefaultReceiptPayloadSanitizer()

    @Test("sanitizer redacts raw RPC URL and raw error string fields recursively before persistence")
    func sanitizerRedactsSensitiveFields() {
        let rawPayload = RawReceiptPayload(
            values: [
                "rpcURL": .string("https://base-mainnet.g.alchemy.com/v2/secret"),
                "error": .string("request failed with provider details"),
                "count": .number(2),
                "nested": .object([
                    "rpcUrl": .string("https://another-provider.example"),
                    "errorMessage": .string("nested failure"),
                    "ok": .bool(true)
                ]),
                "events": .array([
                    .object([
                        "rawError": .string("leaf failure"),
                        "raw_rpc_url": .string("https://leaf-provider.example")
                    ]),
                    .string("safe")
                ])
            ]
        )

        let sanitized = sanitizer.sanitize(rawPayload)

        #expect(sanitized.values["rpcURL"] == .string("<redacted-rpc-url>"))
        #expect(sanitized.values["error"] == .string("<redacted-error>"))
        #expect(sanitized.values["count"] == .number(2))

        guard case .object(let nested)? = sanitized.values["nested"] else {
            Issue.record("Expected nested object")
            return
        }

        #expect(nested["rpcUrl"] == .string("<redacted-rpc-url>"))
        #expect(nested["errorMessage"] == .string("<redacted-error>"))
        #expect(nested["ok"] == .bool(true))

        guard case .array(let events)? = sanitized.values["events"],
              case .object(let firstEvent) = events.first else {
            Issue.record("Expected nested array object")
            return
        }

        #expect(firstEvent["rawError"] == .string("<redacted-error>"))
        #expect(firstEvent["raw_rpc_url"] == .string("<redacted-rpc-url>"))
    }

    @Test("sanitizer only redacts the locked Phase 0 fields and leaves unrelated strings untouched")
    func sanitizerLeavesUnrelatedStringsAlone() {
        let rawPayload = RawReceiptPayload(
            values: [
                "message": .string("keep this"),
                "provider": .string("alchemy"),
                "status": .string("error"),
                "details": .object([
                    "kind": .string("error"),
                    "reason": .string("still keep this")
                ])
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
        #expect(details["reason"] == .string("still keep this"))
    }
}
