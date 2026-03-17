import Foundation
import Testing
@testable import Auralis

@Suite
struct ReceiptContractTests {
    @Test("receipt drafts require sanitized payloads and preserve caller provided correlation IDs")
    func receiptDraftContract() {
        let payload = ReceiptPayload(
            values: [
                "address": .string("0xabc"),
                "attemptCount": .number(2),
                "success": .bool(true)
            ]
        )

        let draft = ReceiptDraft(
            createdAt: Date(timeIntervalSince1970: 123),
            category: "accounts",
            kind: "account.selected",
            correlationID: "flow-123",
            payload: payload
        )

        #expect(draft.createdAt == Date(timeIntervalSince1970: 123))
        #expect(draft.category == "accounts")
        #expect(draft.kind == "account.selected")
        #expect(draft.correlationID == "flow-123")
        #expect(draft.payload == payload)
    }

    @Test("receipt records capture immutable append-only metadata including sequence fallback ordering fields")
    func receiptRecordContract() {
        let record = ReceiptRecord(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            sequenceID: 42,
            createdAt: Date(timeIntervalSince1970: 456),
            category: "networking",
            kind: "nft.refresh.started",
            correlationID: "refresh-1",
            payload: ReceiptPayload(
                values: [
                    "chain": .string("base"),
                    "page": .number(1)
                ]
            )
        )

        #expect(record.id == UUID(uuidString: "11111111-1111-1111-1111-111111111111")!)
        #expect(record.sequenceID == 42)
        #expect(record.createdAt == Date(timeIntervalSince1970: 456))
        #expect(record.category == "networking")
        #expect(record.kind == "nft.refresh.started")
        #expect(record.correlationID == "refresh-1")
    }

    @Test("receipt JSON values round-trip through encoding for future export use")
    func receiptJSONValueRoundTrip() throws {
        let payload = ReceiptPayload(
            values: [
                "name": .string("Aura"),
                "count": .number(3),
                "ok": .bool(false),
                "nested": .object([
                    "items": .array([
                        .string("alpha"),
                        .null
                    ])
                ])
            ]
        )

        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(ReceiptPayload.self, from: data)

        #expect(decoded == payload)
    }

    @Test("sanitization is a separate responsibility that converts raw payload input before append")
    func payloadSanitizationBoundary() {
        let sanitizer = StubReceiptPayloadSanitizer()
        let rawPayload = RawReceiptPayload(
            values: [
                "rpcURL": .string("https://rpc.example"),
                "error": .string("Boom")
            ]
        )

        let sanitized = sanitizer.sanitize(rawPayload)

        #expect(sanitized.values == [
            "rpcURL": .string("<redacted-rpc-url>"),
            "error": .string("<redacted-error>")
        ])
    }
}

private struct StubReceiptPayloadSanitizer: ReceiptPayloadSanitizing {
    func sanitize(_ payload: RawReceiptPayload) -> ReceiptPayload {
        let sanitizedValues = payload.values.mapValues { value in
            switch value {
            case .string(let string) where string == "https://rpc.example":
                return ReceiptJSONValue.string("<redacted-rpc-url>")
            case .string(let string) where string == "Boom":
                return ReceiptJSONValue.string("<redacted-error>")
            default:
                return value
            }
        }

        return ReceiptPayload(values: sanitizedValues)
    }
}
