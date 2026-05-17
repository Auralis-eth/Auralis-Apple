//
//  Password.swift
//  Auralis
//
//  Created by Daniel Bell on 4/18/25.
//

import Foundation
import Security

typealias Password = String

struct PasswordStore {
    let save: (Password) async throws -> Void
    let load: () async throws -> Password?
    let clear: () async throws -> Void
}

enum KeychainFailure: Error, Equatable {
    case operationFailed(operation: String, status: OSStatus)
    case stringEncodingFailed
    case dataDecodingFailed
    case accessControlCreationFailed(status: OSStatus)

    var status: OSStatus? {
        switch self {
        case .operationFailed(_, let status), .accessControlCreationFailed(let status):
            return status
        case .stringEncodingFailed, .dataDecodingFailed:
            return nil
        }
    }
}

enum PasswordStores {
    static var live: PasswordStore {
        let store = KeychainPasswordStore()
        return PasswordStore(
            save: { password in
                try await store.save(password)
            },
            load: {
                try await store.load()
            },
            clear: {
                try await store.clear()
            }
        )
    }

    #if DEBUG
    /// Test-only fallback that stores plaintext in UserDefaults. Never use in production flows.
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
    #endif
}

private actor KeychainPasswordStore {
    private let accessibility = kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String

    private var keychainBaseQuery: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "WalletPasswordAccount",
            kSecAttrService as String: "WalletPasswordService"
        ]
        #if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        return query
    }

    func save(_ password: Password) throws {
        guard let passwordData = password.data(using: .utf8) else {
            throw KeychainFailure.stringEncodingFailed
        }

        let keychainQuery = keychainBaseQuery.merging(
            [
                kSecValueData as String: passwordData,
                kSecAttrAccessible as String: accessibility
            ],
            uniquingKeysWith: { _, new in new }
        )

        let status = SecItemAdd(keychainQuery as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let updateStatus = SecItemUpdate(
                keychainBaseQuery as CFDictionary,
                [
                    kSecValueData as String: passwordData
                ] as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                throw KeychainFailure.operationFailed(operation: "update", status: updateStatus)
            }
            return
        default:
            throw KeychainFailure.operationFailed(operation: "add", status: status)
        }
    }

    func load() throws -> Password? {
        let keychainQuery: [String: Any] = keychainBaseQuery.merging([
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ], uniquingKeysWith: { _, new in new })

        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(keychainQuery as CFDictionary, &dataTypeRef)

        switch status {
        case errSecSuccess:
            guard let retrievedData = dataTypeRef as? Data,
                  let password = String(data: retrievedData, encoding: .utf8) else {
                throw KeychainFailure.dataDecodingFailed
            }
            return password
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainFailure.operationFailed(operation: "load", status: status)
        }
    }

    func clear() throws {
        let status = SecItemDelete(keychainBaseQuery as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw KeychainFailure.operationFailed(operation: "delete", status: status)
        }
    }

    /// Future path for biometric-gated secrets: create the item with this access control
    /// instead of `kSecAttrAccessible`, then let Keychain enforce LocalAuthentication during reads.
    private func makeBiometricAccessControl() throws -> SecAccessControl {
        var error: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .biometryCurrentSet,
            &error
        ) else {
            let status = error
                .map { OSStatus(CFErrorGetCode($0.takeRetainedValue())) }
                ?? errSecParam
            throw KeychainFailure.accessControlCreationFailed(status: status)
        }
        return accessControl
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
    func save(using store: PasswordStore = PasswordStores.live) async throws {
        try await store.save(self)
    }

    static func load(using store: PasswordStore = PasswordStores.live) async throws -> Password? {
        try await store.load()
    }

    static func clear(using store: PasswordStore = PasswordStores.live) async throws {
        try await store.clear()
    }
}
