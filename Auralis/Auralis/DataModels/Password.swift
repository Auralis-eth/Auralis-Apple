//
//  Password.swift
//  Auralis
//
//  Created by Daniel Bell on 4/18/25.
//

import Foundation


typealias Password = String

extension Password {
    var strength: PasswordStrengthView.PasswordStrength {
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
    func saveToKeychain() {
        let keychainQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "WalletPasswordAccount",
            kSecAttrService as String: "WalletPasswordService",
            kSecValueData as String: self.data(using: .utf8)!
        ]

        // Delete existing item first
        SecItemDelete(keychainQuery as CFDictionary)

        // Add new item
        let status = SecItemAdd(keychainQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            print("Error saving password to Keychain: \(status)")
            return
        }
    }

    static func loadFromKeychain() -> Password? {
        let keychainQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "WalletPasswordAccount",
            kSecAttrService as String: "WalletPasswordService",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(keychainQuery as CFDictionary, &dataTypeRef)

        if status == errSecSuccess, let retrievedData = dataTypeRef as? Data, let password = String(data: retrievedData, encoding: .utf8) {
            return password
        }

        return nil
    }
}
