//
//  SecretsTests.swift
//  AuralisTests
//
//  Created by Daniel Bell on 5/16/25.
//

import Foundation
import Testing
@testable import Auralis

@Suite struct SecretsTests {
    struct TestCase {
        let provider: Secrets.APIKeyProvider
        let expected: String
    }
    // Test valid API key retrieval for each provider
    @Test(arguments: [
        TestCase(provider: .moralis, expected: "moralis_key"),
        TestCase(provider: .infura, expected: "infura_key"),
        TestCase(provider: .alchemy, expected: "alchemy_key"),
    ])
    func testApiKeyValidCases(testcase: TestCase) {
        let result = Secrets.apiKey(testcase.provider, bundle: Bundle(for: BundleLocatorClass.self))
        #expect(
            result == testcase.expected,
            "Expected API key '\(testcase.expected)' for provider \(testcase.provider.rawValue), got \(result ?? "nil")"
        )
    }
}

class BundleLocatorClass {
}
