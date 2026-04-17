//
//  StringExtractSVGDataTests.swift
//  AuralisTests
//
//  Created by Daniel Bell on 5/17/25.
//

@testable import Auralis
import Foundation
import Testing

@Suite struct StringExtractSVGDataTests {
    struct TestCase {
        let input: String
        let expected: String?
    }
    @Test(arguments: [
        // Valid cases
        TestCase(
            input: "data:image/svg+xml,<svg width=\"100\" height=\"100\"></svg>",
            expected: "<svg width=\"100\" height=\"100\"></svg>"
        ),
        TestCase(
            input: "data:image/svg+xml;utf8,<svg></svg>",
            expected: "<svg></svg>"
        ),
        TestCase(
            input: "data:image/svg+xml;charset=utf-8,<svg></svg>",
            expected: "<svg></svg>"
        ),
        TestCase(
            input: "data:image/svg+xml;base64,PHN2Zz48L3N2Zz4=", // Base64 for "<svg></svg>"
            expected: "<svg></svg>"
        ),
        TestCase(
            input: "data:image/svg+xml,%3Csvg%3E%3C%2Fsvg%3E", // URL-encoded "<svg></svg>"
            expected: nil
        ),
        TestCase(
            // Complex SVG
            input: "data:image/svg+xml,<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\"><circle cx=\"50\" cy=\"50\" r=\"40\"/></svg>",
            expected: "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\"><circle cx=\"50\" cy=\"50\" r=\"40\"/></svg>"
        ),
        // Invalid cases
        TestCase(input: "", expected: nil),
        TestCase(input: "data:image/png;base64,iVBORw0KGgo=", expected: nil),
        TestCase(input: "data:image/svg+xml,invalid", expected: nil),
        TestCase(input: "https://example.com", expected: nil),
        TestCase(input: "data:image/svg+xml;base64,invalid", expected: nil),
        // Edge cases
        TestCase(
            // Case variation
            input: "data:IMAGE/SVG+XML;CHARSET=UTF-8,<svg></svg>",
            expected: "<svg></svg>"
        ),
        TestCase(
            // Long base64
            input: "data:image/svg+xml;base64," + Data(("<svg>" + String(repeating: "x", count: 1000) + "</svg>").utf8).base64EncodedString(),
            expected: "<svg>" + String(repeating: "x", count: 1000) + "</svg>"
        ),
    ])
    func testExtractSVGData(testcase: TestCase) {
        let result = testcase.input.extractSVGData()
        #expect(
            result == testcase.expected,
            "Input '\(testcase.input)' should produce \(testcase.expected ?? "nil"), got \(result ?? "nil")"
        )
    }

    // Test regex error handling
    @Test(arguments: [
        "data:image/svg+xml;invalid,<svg></svg>", // Unexpected MIME parameter
        "data:image/svg+xml;base64,==" // Malformed base64
    ])
    func testRegexErrorHandling(input: String) {
        // Simulate a regex error by using an invalid pattern (not possible with hardcoded regex)
        // Instead, rely on the catch block handling invalid inputs gracefully
        let result = input.extractSVGData()
        #expect(
            result == nil,
            "Invalid input '\(input)' should produce nil, got \(result ?? "nil")"
        )
    }
}
