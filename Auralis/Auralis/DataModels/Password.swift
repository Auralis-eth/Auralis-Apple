//
//  Password.swift
//  Auralis
//
//  Created by Daniel Bell on 4/18/25.
//

import Foundation
import Security


typealias Password = String

enum PasswordStrength: String {
    case weak, medium, strong
    var message: String {
        switch self {
        case .weak:
            return "Use at least 8 characters with numbers, symbols, and mixed case letters."
        case .medium:
            return "Good password, but consider adding more complexity."
        case .strong:
            return "Strong password!"
        }
    }
}


extension Password {
    var strength: PasswordStrength {
        if count < 5 {
            return .weak
        }

        var score = 0

        // Check for mixed case

        if rangeOfCharacter(from: .uppercaseLetters) != nil {
            score += 1
            if rangeOfCharacter(from: .lowercaseLetters) != nil {
                score += 1
            }
        } else if rangeOfCharacter(from: .lowercaseLetters) != nil {
            score += 1
            if rangeOfCharacter(from: .uppercaseLetters) != nil {
                score += 1
            }
        }

        // Check for numbers
        if rangeOfCharacter(from: .decimalDigits) != nil {
            score += 1
        }

        // Check for special characters
        if rangeOfCharacter(from: CharacterSet(charactersIn: "!@#$%^&*()_-+=<>?/[]{}|~")) != nil {
            score += 1
        }

        // Length bonus
        if count >= 8 {
            score += 1
        }

        switch score {
        case 0...1:
            return .weak
        case 2...3:
            return .medium
        default:
            return .strong
        }
    }
}

extension Password {
    private static let testFallbackKey = "WalletPasswordTestFallback"

    private static var keychainBaseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "WalletPasswordAccount",
            kSecAttrService as String: "WalletPasswordService"
        ]
    }

    private static var isRunningTests: Bool {
#if DEBUG
        return true
#else
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
        Bundle.allBundles.contains(where: { $0.bundlePath.hasSuffix(".xctest") })
#endif
    }

    func saveToKeychain() {
        if Self.isRunningTests {
            UserDefaults.standard.set(self, forKey: Self.testFallbackKey)
            return
        }

        guard let passwordData = self.data(using: .utf8) else {
            return
        }

        let keychainQuery = Self.keychainBaseQuery.merging(
            [
                kSecValueData as String: passwordData,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
            ],
            uniquingKeysWith: { _, new in new }
        )

        // Delete existing item first
        SecItemDelete(Self.keychainBaseQuery as CFDictionary)

        // Add new item
        let status = SecItemAdd(keychainQuery as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(
                Self.keychainBaseQuery as CFDictionary,
                [kSecValueData as String: passwordData] as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                print("Error updating password in Keychain: \(updateStatus)")
                return
            }
            return
        }

        guard status == errSecSuccess else {
            print("Error saving password to Keychain: \(status)")
            return
        }
    }

    static func loadFromKeychain() -> Password? {
        if isRunningTests {
            return UserDefaults.standard.string(forKey: testFallbackKey)
        }

        let keychainQuery: [String: Any] = keychainBaseQuery.merging([
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ], uniquingKeysWith: { _, new in new })

        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(keychainQuery as CFDictionary, &dataTypeRef)

        if status == errSecSuccess, let retrievedData = dataTypeRef as? Data, let password = String(data: retrievedData, encoding: .utf8) {
            return password
        }

        return nil
    }
}
