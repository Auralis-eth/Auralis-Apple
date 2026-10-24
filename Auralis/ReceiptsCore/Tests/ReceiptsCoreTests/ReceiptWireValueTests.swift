import Foundation
import ReceiptsCore
import Testing

@Suite("Receipt wire values")
struct ReceiptWireValueTests {
    @Test("receipt JSON values preserve every wire shape")
    func receiptJSONValuesRoundTrip() throws {
        let value = ReceiptJSONValue.object([
            "array": .array([.string("value"), .number(42), .bool(true), .null]),
            "nested": .object(["enabled": .bool(false)])
        ])

        let encoded = try JSONEncoder().encode(value)
        #expect(try JSONDecoder().decode(ReceiptJSONValue.self, from: encoded) == value)
    }

    @Test("receipt payload remains a keyed JSON wrapper")
    func receiptPayloadWireShape() throws {
        let payload = ReceiptPayload(values: ["kind": .string("fixture")])
        let encoded = try JSONEncoder().encode(payload)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let values = try #require(object["values"] as? [String: Any])

        #expect(values["kind"] as? String == "fixture")
        #expect(try JSONDecoder().decode(ReceiptPayload.self, from: encoded) == payload)
    }

    @Test(
        "receipt mode raw values remain stable",
        arguments: [
            (ReceiptMode.observe, "Observe"),
            (ReceiptMode.assist, "Assist"),
            (ReceiptMode.operate, "Operate")
        ]
    )
    func receiptModeRawValues(mode: ReceiptMode, rawValue: String) {
        #expect(mode.rawValue == rawValue)
    }
}
