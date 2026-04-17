//
//  OptionalStringImageSourceTests.swift
//  AuralisTests
//
//  Created by Daniel Bell on 5/17/25.
//

@testable import Auralis
import Foundation
import Testing

@Suite struct OptionalStringImageSourceTests {
    struct TestCase {
        let input: String?
        let expected: NFTImageSource?
    }
    @Test(arguments: [
        // Valid cases
        TestCase(
            input: "ipfs://QmHash",
            expected: .url(URL(string: "https://gateway.pinata.cloud/ipfs/QmHash")!)
        ),
        TestCase(
            input: "ipfs://QmHash/path/to/file",
            expected: .url(URL(string: "https://gateway.pinata.cloud/ipfs/QmHash/path/to/file")!)
        ),
        TestCase(
            input: "http://example.com/image.png",
            expected: .url(URL(string: "https://example.com/image.png")!)
        ),
        TestCase(
            input: "https://example.com/image.png",
            expected: .url(URL(string: "https://example.com/image.png")!)
        ),
        TestCase(
            input: "QmHash",
            expected: .url(URL(string: "https://ipfs.io/ipfs/QmHash/")!)
        ),
        TestCase(
            input: "data:image/svg+xml;base64,PHN2Zz48L3N2Zz4=", // Base64 for "<svg></svg>"
            expected: .svg("<svg></svg>")
        ),
        TestCase(
            input: "ipfs://QmHash?query=param#fragment",
            expected: .url(URL(string: "https://gateway.pinata.cloud/ipfs/QmHash?query=param#fragment")!)
        ),
        // Invalid cases
        TestCase(input: nil, expected: nil),
        TestCase(input: "", expected: nil),
        TestCase(input: "https://", expected: nil), // No host
        // Edge cases
        TestCase(
            input: String(repeating: "a", count: 100),
            expected: .url(URL(string: "https://ipfs.io/ipfs/" + String(repeating: "a", count: 100) + "/")!)
        )
    ])
    func testImageSource(testcase: TestCase) {
        let result = testcase.input.imageSource
        #expect(
            result == testcase.expected,
            "Input '\(testcase.input ?? "nil")' should produce \(String(describing: testcase.expected)), got \(String(describing: result))"
        )
    }

    // Test that invalid data URLs don't crash (not feasible due to fatalError)
    @Test func testInvalidDataURL() {
        // Note: Cannot test "data:invalid" due to fatalError("Invalid data URL")
        // Instead, test a non-SVG data URL that extractSVGData() rejects
        let input: String? = "data:image/png;base64,iVBORw0KGgo="
        let result = input.imageSource
        #expect(
            result == nil,
            "Invalid data URL '\(input)' should produce nil, got \(String(describing: result))"
        )
    }
}
