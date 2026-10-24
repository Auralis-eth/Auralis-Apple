import AuralisFoundation
import Foundation
import Testing

struct JSONValueTests {
    @Test("recursive JSON values round-trip without losing integer and double cases")
    func recursiveValuesRoundTrip() throws {
        let value = JSONValue.object([
            "string": .string("value"),
            "int": .int(7),
            "double": .double(7.5),
            "bool": .bool(true),
            "array": .array([.null, .int(1)]),
        ])

        let data = try JSONEncoder().encode(value)
        #expect(try JSONDecoder().decode(JSONValue.self, from: data) == value)
    }

    @Test("integer and fractional JSON numbers decode to distinct cases")
    func numericCasesRemainDistinct() throws {
        #expect(try JSONDecoder().decode(JSONValue.self, from: Data("1".utf8)) == .int(1))
        #expect(try JSONDecoder().decode(JSONValue.self, from: Data("1.5".utf8)) == .double(1.5))
    }

    @Test("JSON string encoding remains available to provider adapters")
    func encodedJSONStringPreservesObjectShape() {
        let encoded = JSONValue.object(["enabled": .bool(true)]).encodedJSONString()
        #expect(encoded == "{\"enabled\":true}")
    }
}
