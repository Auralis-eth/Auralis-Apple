//
//  StringExtensionTests.swift
//  AuralisTests
//
//  Created by Daniel Bell on 5/16/25.
//

import Testing
@testable import Auralis

@Suite struct StringExtensionTests {
    // Test isHex property
    @Test(arguments: [
        // Valid hex strings
        TestCase(json: "0x123", expected: true),
        TestCase(json: "0xABCDEF", expected: true),
        TestCase(json: "0xabc", expected: true), // Case insensitivity
        TestCase(json: "0x", expected: true), // Empty hex string
        TestCase(json: "0x0000", expected: true), // Leading zeros
        // Invalid hex strings
        TestCase(json: "123", expected: false), // Missing 0x
        TestCase(json: "0x12G", expected: false), // Non-hex character
        TestCase(json: "0x@#$", expected: false), // Invalid characters
        TestCase(json: "0X123", expected: false), // Wrong case for prefix
        TestCase(json: "0x 123", expected: false), // Space in string
        TestCase(json: "hello", expected: false), // Non-hex string
        TestCase(json: "", expected: false), // Empty string
    ])
    func testIsHex(testCase: TestCase<Bool>) {
        #expect(testCase.json.isHex == testCase.expected)
    }

    // Test isHexIgnorePrefix property
    @Test(arguments:[
        // Valid hex strings with/without 0x
        TestCase(json: "0x123", expected: true),
        TestCase(json: "123", expected: true),
        TestCase(json: "0xABCDEF", expected: true),
        TestCase(json: "ABCDEF", expected: true),
        TestCase(json: "0xabc", expected: true), // Case insensitivity
        TestCase(json: "abc", expected: true),
        TestCase(json: "0x", expected: true), // Empty hex string
        TestCase(json: "0", expected: true), // Single digit without 0x
        TestCase(json: "F", expected: true), // Single hex character
        // Invalid hex strings
        TestCase(json: "", expected: false), // Empty string
        TestCase(json: "0x12G", expected: false), // Non-hex character
        TestCase(json: "12G", expected: false), // Non-hex without 0x
        TestCase(json: "0x@#$", expected: false), // Invalid characters
        TestCase(json: "0X123", expected: false), // Wrong case for prefix
        TestCase(json: " 123", expected: false), // Leading space
        // Edge case: long hex string
        TestCase(json: "1234567890ABCDEF1234567890ABCDEF", expected: true),
    ])
    func testIsHexIgnorePrefix(testcase: TestCase<Bool>) {
        #expect(testcase.json.isHexIgnorePrefix == testcase.expected)
    }

    // Test displayAddress
    @Test(arguments: [
        // Long strings (> 10 characters)
        TestCase(
            json: "1234567890123456",
            expected: "123456...3456"
        ),
        TestCase(
            json: "0x1234567890abcdef",
            expected: "0x1234...cdef"
        ),
        // Exactly 10 characters
        TestCase(
            json: "1234567890",
            expected: "1234567890" // displayAddress returns unchanged
        ),
        // Short strings (< 10 characters)
        TestCase(json: "123456", expected: "123456"),
        TestCase(json: "123", expected: "123"),
        TestCase(json: "", expected: ""),
        // Edge cases
        TestCase(
            json: "abcdefg123456",
            expected: "abcdef...3456"
        ),
        TestCase(
            json: "A1B2C3D4E5F6G7",
            expected: "A1B2C3...F6G7"
        ), // Case preservation
        TestCase(
            json: "123456789", // 9 characters
            expected: "123456789"
        ),
    ])
    func testAddressDisplay(testcase: TestCase<String>) {
        #expect(testcase.json.displayAddress == testcase.expected)
    }
}
