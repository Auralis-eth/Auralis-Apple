//
//  Password.swift
//  Auralis
//
//  Created by Daniel Bell on 4/18/25.
//

import Foundation
import OSLog
import Security

private let passwordStoreLogger = Logger(subsystem: "Auralis", category: "PasswordStore")

typealias Password = String

struct PasswordStore {
    let save: (Password) -> Void
    let load: () -> Password?
    let clear: () -> Void
}

enum PasswordStores {
    static let live = PasswordStore(
        save: { password in
            KeychainPasswordStore().save(password)
        },
        load: {
            KeychainPasswordStore().load()
        },
        clear: {
            KeychainPasswordStore().clear()
        }
    )

    static func test(userDefaults: UserDefaults = .standard) -> PasswordStore {
        let store = UserDefaultsPasswordStore(userDefaults: userDefaults)
        return PasswordStore(
            save: { password in
                store.save(password)
            },
            load: {
                store.load()
            },
            clear: {
                store.clear()
            }
        )
    }
}

private struct KeychainPasswordStore {
    private var keychainBaseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "WalletPasswordAccount",
            kSecAttrService as String: "WalletPasswordService"
        ]
    }

    func save(_ password: Password) {
        guard let passwordData = password.data(using: .utf8) else {
            return
        }

        let keychainQuery = keychainBaseQuery.merging(
            [
                kSecValueData as String: passwordData,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
            ],
            uniquingKeysWith: { _, new in new }
        )

        SecItemDelete(keychainBaseQuery as CFDictionary)

        let status = SecItemAdd(keychainQuery as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(
                keychainBaseQuery as CFDictionary,
                [kSecValueData as String: passwordData] as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                passwordStoreLogger.error("Error updating password in Keychain: \(updateStatus, privacy: .public)")
                return
            }
            return
        }

        guard status == errSecSuccess else {
            passwordStoreLogger.error("Error saving password to Keychain: \(status, privacy: .public)")
            return
        }
    }

    func load() -> Password? {
        let keychainQuery: [String: Any] = keychainBaseQuery.merging([
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ], uniquingKeysWith: { _, new in new })

        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(keychainQuery as CFDictionary, &dataTypeRef)

        if status == errSecSuccess,
           let retrievedData = dataTypeRef as? Data,
           let password = String(data: retrievedData, encoding: .utf8) {
            return password
        }

        return nil
    }

    func clear() {
        SecItemDelete(keychainBaseQuery as CFDictionary)
    }
}

private struct UserDefaultsPasswordStore {
    private let userDefaults: UserDefaults
    private let testFallbackKey = "WalletPasswordTestFallback"

    init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    func save(_ password: Password) {
        userDefaults.set(password, forKey: testFallbackKey)
    }

    func load() -> Password? {
        userDefaults.string(forKey: testFallbackKey)
    }

    func clear() {
        userDefaults.removeObject(forKey: testFallbackKey)
    }
}

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
    func save(using store: PasswordStore = PasswordStores.live) {
        store.save(self)
    }

    static func load(using store: PasswordStore = PasswordStores.live) -> Password? {
        store.load()
    }

    static func clear(using store: PasswordStore = PasswordStores.live) {
        store.clear()
    }
}
