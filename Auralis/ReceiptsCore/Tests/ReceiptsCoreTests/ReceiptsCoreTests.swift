import AuralisPrimaryModels
import Foundation
import ReceiptsCore
import Testing

struct ReceiptsCoreTests {
    @Test("receipt draft preserves append contract fields")
    func receiptDraftPreservesFields() {
        let createdAt = Date(timeIntervalSince1970: 1_704_067_200)
        let payload = ReceiptPayload(values: ["kind": .string("fixture")])

        let draft = ReceiptDraft(
            createdAt: createdAt,
            actor: .user,
            mode: .observe,
            trigger: "test.trigger",
            scope: "tests",
            summary: "Test receipt",
            provenance: "unit-test",
            isSuccess: true,
            correlationID: "corr-1",
            timelineAccountAddress: "0x1234567890abcdef1234567890abcdef12345678",
            timelineChainRawValue: "eth-mainnet",
            details: payload
        )

        #expect(draft.createdAt == createdAt)
        #expect(draft.actor == .user)
        #expect(draft.trigger == "test.trigger")
        #expect(draft.scope == "tests")
        #expect(draft.correlationID == "corr-1")
        #expect(draft.details == payload)
    }

    @Test("payload sanitizer keeps public labels and redacts error and opaque-token fields")
    func sanitizerKeepsLabelsAndRedactsSensitiveKinds() {
        let payload = RawReceiptPayload(fields: [
            .public("label", string: "Visible Label", kind: .label),
            .public("error", string: "request failed with provider details", kind: .errorMessage),
            .redacted("token", string: "secret-token-value", kind: .opaqueToken),
        ])

        let sanitized = DefaultReceiptPayloadSanitizer().sanitize(payload)

        #expect(sanitized.values["label"] == .string("Visible Label"))
        #expect(sanitized.values["error"] == .string("<redacted-error>"))
        #expect(sanitized.values["token"] == .string("<redacted-opaque-token>"))
    }

    @Test("hashed freeform payload fields produce a stable sha256 digest")
    func hashedFreeformFieldsAreDeterministic() {
        let field = ReceiptPayloadField.hashed("safeHash", string: "stable input value", kind: .freeformText)
        let payload = RawReceiptPayload(fields: [field])

        let first = DefaultReceiptPayloadSanitizer().sanitize(payload)
        let second = DefaultReceiptPayloadSanitizer().sanitize(payload)

        #expect(first.values["safeHash"] == second.values["safeHash"])
        guard case .string(let hash) = first.values["safeHash"] else {
            Issue.record("Expected hashed string value.")
            return
        }
        #expect(hash.hasPrefix("sha256:"))
        #expect(hash.count == 71)
    }
}
