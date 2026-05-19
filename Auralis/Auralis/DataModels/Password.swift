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

        let accessControl = try makeBiometricAccessControl()
        let itemAttributes: [String: Any] = [
            kSecValueData as String: passwordData,
            kSecAttrAccessControl as String: accessControl
        ]
        let keychainQuery = keychainBaseQuery.merging(
            itemAttributes,
            uniquingKeysWith: { _, new in new }
        )

        let status = SecItemAdd(keychainQuery as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let updateStatus = SecItemUpdate(
                keychainBaseQuery as CFDictionary,
                itemAttributes as CFDictionary
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

    /// Creates an access control that binds the password to the current biometric enrollment.
    /// The accessibility class lives inside the access control, so save queries must not also set `kSecAttrAccessible`.
    private func makeBiometricAccessControl() throws -> SecAccessControl {
        var error: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
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
