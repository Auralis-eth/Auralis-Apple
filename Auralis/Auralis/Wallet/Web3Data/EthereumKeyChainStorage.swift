//
//  EthereumKeyChainStorage.swift
//  Auralis
//
//  Created by Daniel Bell on 4/12/25.
//

import Foundation
import Security
import web3

// Error enum for better error handling
public enum KeychainError: Error {
    case storeError(status: OSStatus)
    case loadError(status: OSStatus)
    case unexpectedData
    case unexpectedStatus(OSStatus)
    case dataConversionError
    case addressNotFound
    case accessControlCreationError
}

public class EthereumKeyChainStorage: EthereumSingleKeyStorageProtocol {
    var addresses: [EOAccount]

    // SecAccessControl property to manage keychain access restrictions
    private var _accessControl: SecAccessControl?

    init(addresses: [EOAccount] = []) {
        self.addresses = addresses
        // Initialize with default biometric access control
        setupDefaultAccessControl()
    }

    // MARK: - KeyChain Constants
    private struct KeychainConstants {
        static let service = "com.Auralis.ethereum.keychain"
        static let addressPrefix = "ethereumAddress_"
        static let account = "ethereumPrivateKey"
    }

    // Setup default access control with biometric authentication
    private func setupDefaultAccessControl() {
        let accessControlFlags: SecAccessControlCreateFlags = [.biometryAny, .privateKeyUsage]
        do {
            _accessControl = try createAccessControl(with: accessControlFlags)
        } catch {
            print("Failed to set up default access control: \(error)")
        }
    }

    // Helper method to create SecAccessControl with given flags
    private func createAccessControl(with flags: SecAccessControlCreateFlags) throws -> SecAccessControl {
        var error: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            flags,
            &error
        ) else {
            if let unwrappedError = error?.takeRetainedValue() {
                throw unwrappedError
            }
            throw KeychainError.accessControlCreationError
        }
        return accessControl
    }

    public func storePrivateKey(key: Data) throws {
        // First, try to delete any existing key
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainConstants.service,
            kSecAttrAccount as String: KeychainConstants.account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Set up the keychain query for storing
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainConstants.service,
            kSecAttrAccount as String: KeychainConstants.account,
            kSecValueData as String: key
        ]

        // Apply access control if available
        if let accessControl = _accessControl {
            query[kSecAttrAccessControl as String] = accessControl
        }

        // Add the private key to the keychain
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.storeError(status: status)
        }
    }

    public func loadPrivateKey() throws -> Data {
        // Set up the keychain query for retrieving
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainConstants.service,
            kSecAttrAccount as String: KeychainConstants.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        // Apply access control if available (for authentication prompts)
        if _accessControl != nil {
            query[kSecUseOperationPrompt as String] = "Access your Ethereum private key"
        }

        // Query the keychain
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        // Check if the operation succeeded
        guard status == errSecSuccess else {
            throw KeychainError.loadError(status: status)
        }

        // Ensure we got back the expected data
        guard let keyData = result as? Data else {
            throw KeychainError.unexpectedData
        }

        return keyData
    }
}

extension EthereumKeyChainStorage: EthereumMultipleKeyStorageProtocol {

    // MARK: - Keychain Query Helper
    private func keychainQuery(for address: web3.EthereumAddress) -> [String: Any] {
        let account = KeychainConstants.addressPrefix + address.asString()

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainConstants.service,
            kSecAttrAccount as String: account
        ]

        // Apply access control if available
        if let accessControl = _accessControl {
            query[kSecAttrAccessControl as String] = accessControl
        }

        return query
    }

    // MARK: - Public Methods
    public func deleteAllKeys() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainConstants.service
        ]

        let status = SecItemDelete(query as CFDictionary)

        // If the item doesn't exist, that's fine for delete all
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
        addresses = []
    }

    public func deletePrivateKey(for address: web3.EthereumAddress) throws {
        let query = keychainQuery(for: address)

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
        addresses = addresses.filter { $0.address != address.asString() }
    }

    public func fetchAccounts() throws -> [web3.EthereumAddress] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainConstants.service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return []
        }

        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }

        guard let items = result as? [[String: Any]] else {
            return []
        }

        return items.compactMap { item in
            guard let accountValue = item[kSecAttrAccount as String] as? String,
                  accountValue.hasPrefix(KeychainConstants.addressPrefix) else {
                return nil
            }

            let addressString = accountValue.replacingOccurrences(of: KeychainConstants.addressPrefix, with: "")
            return EthereumAddress(addressString)
        }
    }

    public func loadPrivateKey(for address: EthereumAddress) throws -> Data {
        guard addresses.contains(where: { $0.address.lowercased() == address.asString().lowercased() }) else {
            throw KeychainError.addressNotFound
        }
        var query = keychainQuery(for: address)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        // Add authentication prompt if access control is set
        if _accessControl != nil {
            query[kSecUseOperationPrompt as String] = "Access your Ethereum private key for \(address.asString())"
        }

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.addressNotFound
            }
            throw KeychainError.unexpectedStatus(status)
        }

        guard let data = result as? Data else {
            throw KeychainError.dataConversionError
        }

        return data
    }

    public func storePrivateKey(key: Data, with address: web3.EthereumAddress) throws {
        // First try to delete any existing key for this address
        try? deletePrivateKey(for: address)

        var query = keychainQuery(for: address)
        query[kSecValueData as String] = key

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
        addresses.append(EOAccount(address: address.asString(), access: .wallet))
    }
}

// Extension to KeyChainStorage to support SecAccessControl
extension EthereumKeyChainStorage {
    var accessControl: SecAccessControl? {
        get {
            return _accessControl
        }
        set {
            _accessControl = newValue
            // Update any existing keys with the new access control
            updateExistingKeysWithCurrentAccessControl()
        }
    }

    // Set access control with specific parameters
    func setAccessControl(flags: SecAccessControlCreateFlags) throws {
        let newAccessControl = try createAccessControl(with: flags)
        self.accessControl = newAccessControl
    }

    // Update existing keys with current access control settings
    private func updateExistingKeysWithCurrentAccessControl() {
        do {
            // Get all current accounts
            let accounts = try fetchAccounts()

            // For each account, update its access control
            for address in accounts {
                do {
                    // Load the private key
                    let privateKey = try loadPrivateKey(for: address)

                    // Delete and re-store with new access control
                    try deletePrivateKey(for: address)
                    try storePrivateKey(key: privateKey, with: address)
                } catch {
                    print("Failed to update access control for address \(address.asString()): \(error)")
                }
            }

            // Also update the main private key if it exists
            do {
                let mainKey = try loadPrivateKey()
                try storePrivateKey(key: mainKey)
            } catch {
                // Main key might not exist, so just log and continue
                print("No main private key to update: \(error)")
            }
        } catch {
            print("Failed to update existing keys with new access control: \(error)")
        }
    }

    // Check if biometric authentication is available
    func canUseBiometricAuthentication() -> Bool {
        var error: Unmanaged<CFError>?
        guard SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .biometryAny,
            &error
        ) != nil else {
            return false
        }
        return true
    }
}
