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
        TestCase(provider: .alchemy, expected: "alchemy_key"),
    ])
    func testApiKeyValidCases(testcase: TestCase) {
        do {
            let result = try Secrets.apiKey(testcase.provider, bundle: Bundle(for: BundleLocatorClass.self))
            #expect(
                result == testcase.expected,
                "Expected API key '\(testcase.expected)' for provider \(testcase.provider.rawValue), got \(result)"
            )
        } catch {
            Issue.record("Unexpected error thrown for provider \(testcase.provider.rawValue): \(error)")
        }
    }
}

class BundleLocatorClass {
}
