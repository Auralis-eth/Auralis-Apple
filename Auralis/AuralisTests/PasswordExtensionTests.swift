//
//  PasswordExtensionTests.swift
//  AuralisTests
//
//  Created by Daniel Bell on 5/16/25.
//

import Foundation
import Testing
import Security
@testable import Auralis

// Helper to clean up Keychain before/after tests

@Suite class PasswordExtensionTests {
    struct TestCase {
        let password: String
        let expected: PasswordStrength
    }
    func cleanKeychain() {
        let keychainQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "WalletPasswordAccount",
            kSecAttrService as String: "WalletPasswordService"
        ]
        SecItemDelete(keychainQuery as CFDictionary)
        UserDefaults.standard.removeObject(forKey: "WalletPasswordTestFallback")
    }

    // Clean up Keychain before and after each test
    init() {
        cleanKeychain()
    }

    deinit {
        cleanKeychain()
    }

    // Test password strength
    @Test(arguments: [
        // Weak passwords
        TestCase(password: "", expected: .weak), // Empty
        TestCase(password: "abc", expected: .weak), // Short
        TestCase(password: "abcd", expected: .weak), // Short
        TestCase(password: "abcdef", expected: .weak), // Length ≥ 5, no other criteria
        TestCase(password: "123456", expected: .weak), // Only numbers
        TestCase(password: "abcdefg", expected: .weak), // Only lowercase
        // Medium passwords
        TestCase(password: "Abcdef", expected: .medium), // Mixed case
        TestCase(password: "abc123", expected: .medium), // Lowercase + numbers
        TestCase(password: "abc!@#", expected: .medium), // Lowercase + special
        TestCase(password: "abcdefgh", expected: .medium), // Length ≥ 8
        TestCase(password: "Abcd123", expected: .medium), // Mixed case + numbers
        TestCase(password: "Abcd!@#", expected: .medium), // Mixed case + special
        // Strong passwords
        TestCase(password: "Abcd123!long", expected: .strong), // All criteria + length
        TestCase(password: "Ab1!", expected: .weak), // Short but all criteria
        TestCase(password: "Abcd1234567!", expected: .strong), // All criteria + length
        // Edge cases
        TestCase(password: "a", expected: .weak), // Single char
        TestCase(password: "!@#$%", expected: .weak), // Special only, short
        TestCase(password: "!@#$%^&*()_+", expected: .medium), // Special only, length ≥ 8
        TestCase(
            password: "A".padding(toLength: 100, withPad: "a", startingAt: 0),
            expected: .medium
        ) // Long, mixed case
    ])
    func testPasswordStrength(testcase: TestCase) {
        #expect(
            testcase.password.strength == testcase.expected,
            "Password '\(testcase.password)' should have strength \(testcase.expected), got \(testcase.password.strength)"
        )
    }
}
