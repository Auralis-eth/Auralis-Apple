import ReceiptsCore
@testable import Auralis
import AuralisPrimaryModels
import AuralisPrimaryPersistence
import Foundation
import Testing

@Suite
struct ReceiptContractTests {
    @Test("receipt records round-trip cleanly through JSON encoding to preserve append-only metadata")
    func receiptRecordRoundTripsThroughJSONEncoding() throws {
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

        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(ReceiptRecord.self, from: data)

        #expect(decoded == record)
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
