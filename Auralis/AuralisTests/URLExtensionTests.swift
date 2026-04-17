//
//  URLExtensionTests.swift
//  AuralisTests
//
//  Created by Daniel Bell on 5/14/25.
//

import Foundation
import Testing
@testable import Auralis

@Suite struct URLExtensionTests {
    // Test isIPFS property
    @Test(arguments:[
        // Valid IPFS URLs
        TestCase(json: "ipfs://QmHash", expected: true),
        TestCase(json: "ipfs://QmHash/path/to/file", expected: true),
        // Non-IPFS URLs
        TestCase(json: "https://example.com", expected: false),
        TestCase(json: "http://example.com", expected: false),
        TestCase(json: "file://localhost/file.txt", expected: false),
        // Edge cases
        TestCase(json: "ipfs://", expected: true), // No host, but scheme is ipfs
        TestCase(json: "ftp://server.com", expected: false), // Other scheme
        TestCase(json: "://example.com", expected: false) // Malformed scheme
    ])
    func testIsIPFS(testCase: TestCase<Bool>) throws {
        let url = try #require(URL(string: testCase.json))
        #expect(url.isIPFS == testCase.expected, "\(testCase.json) should \(testCase.expected ? "be" : "not be") IPFS")
    }

    // Test ipfsHTML property
    @Test(arguments: [
        // Valid IPFS URLs
        TestCase(
            json: "ipfs://QmHash",
            expected: "https://gateway.pinata.cloud/ipfs/QmHash"
        ),
        TestCase(
            json: "ipfs://QmHash/path/to/file.mp4",
            expected: "https://gateway.pinata.cloud/ipfs/QmHash/path/to/file.mp4"
        ),
        TestCase(
            json: "ipfs://QmHash/", // Trailing slash
            expected: "https://gateway.pinata.cloud/ipfs/QmHash"
        ),
        // URLs without host
        TestCase(json: "ipfs://", expected: nil),
        TestCase(json: "ipfs:///", expected: nil),
        // Non-IPFS URLs with host
        TestCase(
            json: "https://example.com/path",
            expected: nil
        ),
        // Edge cases
        TestCase(json: "", expected: nil), // Invalid URL
        TestCase(json: "://example.com", expected: nil), // Malformed URL
        TestCase(
            json: "ipfs://QmHash?query=param#fragment",
            expected: "https://gateway.pinata.cloud/ipfs/QmHash?query=param#fragment"
        ),
    ])
    func testIpfsHTML(testCase: TestCase<String?>) {
        let result = testCase.json.ipfsGatewayURL()//"https://gateway.pinata.cloud/ipfs/QmHash"
        #expect(
            result?.absoluteString == testCase.expected,
            "\(testCase.json) should produce \(testCase.expected), got \(result?.absoluteString ?? "nil")"
        )

    }

    // Test isVideoMP4 property
    @Test(arguments: [
        // URLs with .mp4
        TestCase(json: "https://example.com/video.mp4", expected: true),
        TestCase(json: "ipfs://QmHash/path/to/video.mp4", expected: true),
        TestCase(json: "file://localhost/file.MP4", expected: true), // Case insensitivity
        // URLs without .mp4
        TestCase(json: "https://example.com/video.mp3", expected: false),
        TestCase(json: "https://example.com/video", expected: false),
        TestCase(json: "https://example.com/", expected: false),
        TestCase(json: "ipfs://QmHash", expected: false),
        // Edge cases
        TestCase(json: "https://example.com/video.mp4?query=param", expected: true), // With query
        TestCase(json: "https://example.com/video.mp4#fragment", expected: true), // With fragment
        TestCase(json: "https://example.com/path.mp4/file", expected: false) // .mp4 not at end
    ])
    func testIsVideoMP4(testCase: TestCase<Bool>) throws {
        let url = try #require(URL(string: testCase.json))
        #expect(url.isVideoMP4 == testCase.expected)
    }
}
