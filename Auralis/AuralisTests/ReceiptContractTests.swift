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
            actor: .user,
            mode: .observe,
            trigger: "account.selected",
            scope: "accounts",
            summary: "Selected active account",
            provenance: "user_provided",
            isSuccess: true,
            correlationID: "flow-123",
            details: payload
        )

        #expect(draft.createdAt == Date(timeIntervalSince1970: 123))
        #expect(draft.actor == .user)
        #expect(draft.mode == .observe)
        #expect(draft.scope == "accounts")
        #expect(draft.trigger == "account.selected")
        #expect(draft.summary == "Selected active account")
        #expect(draft.provenance == "user_provided")
        #expect(draft.isSuccess)
        #expect(draft.correlationID == "flow-123")
        #expect(draft.details == payload)
    }

    @Test("receipt records capture immutable append-only metadata including sequence fallback ordering fields")
    func receiptRecordContract() {
        let record = ReceiptRecord(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            sequenceID: 42,
            createdAt: Date(timeIntervalSince1970: 456),
            actor: .system,
            mode: .observe,
            trigger: "nft.refresh.started",
            scope: "networking",
            summary: "Started NFT refresh",
            provenance: "on_chain",
            isSuccess: true,
            correlationID: "refresh-1",
            details: ReceiptPayload(
                values: [
                    "chain": .string("base"),
                    "page": .number(1)
                ]
            )
        )

        #expect(record.id == UUID(uuidString: "11111111-1111-1111-1111-111111111111")!)
        #expect(record.sequenceID == 42)
        #expect(record.createdAt == Date(timeIntervalSince1970: 456))
        #expect(record.actor == .system)
        #expect(record.mode == .observe)
        #expect(record.scope == "networking")
        #expect(record.trigger == "nft.refresh.started")
        #expect(record.summary == "Started NFT refresh")
        #expect(record.provenance == "on_chain")
        #expect(record.isSuccess)
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
        let sanitizer = DefaultReceiptPayloadSanitizer()
        let rawPayload = RawReceiptPayload(
            fields: [
                .public("rpcURL", string: "https://rpc.example", kind: .url),
                .public("error", string: "Boom", kind: .errorMessage),
                .public("url", string: "https://example.com/nft/123", kind: .url),
                .public("value", string: "0xabc", kind: .copiedText)
            ]
        )

        let sanitized = sanitizer.sanitize(rawPayload)

        #expect(sanitized.values == [
            "rpcURL": .string("<redacted-url>"),
            "error": .string("<redacted-error>"),
            "url": .string("<redacted-url>"),
            "value": .string("<redacted-copied-value>")
        ])
    }
}
