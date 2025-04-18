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
}

public class EthereumKeyChainStorage: EthereumSingleKeyStorageProtocol {
    var addresses: [EOAccount]
    init(addresses: [EOAccount] = []) {
        self.addresses = addresses
    }

    // MARK: - KeyChain Constants
    private struct KeychainConstants {
        static let service = "com.Auralis.ethereum.keychain"
        static let addressPrefix = "ethereumAddress_"
        static let account = "ethereumPrivateKey"
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
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainConstants.service,
            kSecAttrAccount as String: KeychainConstants.account,
            kSecValueData as String: key
        ]

        // Add the private key to the keychain
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.storeError(status: status)
        }
    }

    public func loadPrivateKey() throws -> Data {
        // Set up the keychain query for retrieving
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainConstants.service,
            kSecAttrAccount as String: KeychainConstants.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

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

        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainConstants.service,
            kSecAttrAccount as String: account
        ]
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
        addresses.append(EOAccount(address: address.asString()))
    }
}
