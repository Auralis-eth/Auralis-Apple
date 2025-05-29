//
//  AnyValueTests.swift
//  AuralisTests
//
//  Created by Daniel Bell on 5/14/25.
//

import Foundation
import Testing
@testable import Auralis

@Suite struct AnyValueTests {
    struct TestCase {
        let json: String
        let expected: AnyValue
    }

    @Test("Test encode and decode value", arguments: [
        AnyValue.string("hello"),
        .string("42"),
        .string(""),
        .string("{\"key\": \"value\"}"),
        .string("true"),
        .integer(42),
        .integer(-42),
        .integer(Int.max),
        .double(3.14),
        .double(-3.14),
        .double(1e19),
        .double(1e-10),
        .double(Double.greatestFiniteMagnitude),
        .boolean(true),
        .boolean(false),
        .null
    ])
    func testRoundTrip(value: AnyValue) {
        let encoded = try! JSONEncoder().encode(value)
        let decoded = try! JSONDecoder().decode(AnyValue.self, from: encoded)
        #expect(decoded == value)
    }

//    @Test(.disabled(""), .bug("https://bugs.swift.org/browse/SR-14174", id: "14174"))
    @Test("Test Decoding", arguments: [
        TestCase(json: "\"\"", expected: .string("")),
        TestCase(json: "\"{\\\"key\\\": \\\"value\\\"}\"", expected: .string("{\"key\": \"value\"}")),
        TestCase(json: "-42", expected: .integer(-42)),
        TestCase(json: "1.23e4", expected: .integer(12300)),
        TestCase(json: "1e-10", expected: .double(1e-10))
    ])
    func testDecoding(testCase: TestCase) {
        let data = Data(testCase.json.utf8)
        let decoded = try! JSONDecoder().decode(AnyValue.self, from: data)
        #expect(decoded == testCase.expected)
    }

    @Test func testInvalidDecoding() {
        let failingJSON: [String] = [
            "[1,2,3]", // Array
            "{\"key\": \"value\"}" // Object
        ]

        for json in failingJSON {
            let data = Data(json.utf8)
            var failed = false

            do {
                let _ = try JSONDecoder().decode(AnyValue.self, from: data)
                failed = false // Should not reach here
            } catch {
                failed = true // Expected to throw
            }
            #expect(failed)
        }
    }
}
