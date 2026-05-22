import Foundation
import Security

public enum ReceiptIntegrityHeadStoreError: Error, Equatable {
    case operationFailed(operation: String, status: OSStatus)
    case stringEncodingFailed
    case dataDecodingFailed
}

public protocol ReceiptIntegrityHeadStoring: Sendable {
    func loadHead(for accountKey: String) async throws -> String?
    func loadAllHeads() async throws -> [String: String]
    func saveHead(_ hash: String, for accountKey: String) async throws
    func clearHead(for accountKey: String) async throws
    func clearAllHeads() async throws
}

public actor KeychainReceiptIntegrityHeadStore: ReceiptIntegrityHeadStoring {
    public static let storageDecisionIdentifier = "AuralisReceiptIntegrityHeadService"

    private let service = KeychainReceiptIntegrityHeadStore.storageDecisionIdentifier
    private let accessibility = kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String

    public init() { }

    public func loadHead(for accountKey: String) throws -> String? {
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(
            baseQuery(accountKey: accountKey).merging(
                [
                    kSecReturnData as String: true,
                    kSecMatchLimit as String: kSecMatchLimitOne
                ],
                uniquingKeysWith: { _, new in new }
            ) as CFDictionary,
            &dataTypeRef
        )

        switch status {
        case errSecSuccess:
            guard let data = dataTypeRef as? Data,
                  let hash = String(data: data, encoding: .utf8) else {
                throw ReceiptIntegrityHeadStoreError.dataDecodingFailed
            }
            return hash
        case errSecItemNotFound:
            return nil
        default:
            throw ReceiptIntegrityHeadStoreError.operationFailed(operation: "load", status: status)
        }
    }

    public func loadAllHeads() throws -> [String: String] {
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(
            serviceQuery().merging(
                [
                    kSecReturnAttributes as String: true,
                    kSecReturnData as String: true,
                    kSecMatchLimit as String: kSecMatchLimitAll
                ],
                uniquingKeysWith: { _, new in new }
            ) as CFDictionary,
            &dataTypeRef
        )

        switch status {
        case errSecSuccess:
            guard let items = dataTypeRef as? [[String: Any]] else {
                throw ReceiptIntegrityHeadStoreError.dataDecodingFailed
            }

            var heads: [String: String] = [:]
            for item in items {
                guard let accountKey = item[kSecAttrAccount as String] as? String,
                      let data = item[kSecValueData as String] as? Data,
                      let hash = String(data: data, encoding: .utf8) else {
                    throw ReceiptIntegrityHeadStoreError.dataDecodingFailed
                }
                heads[accountKey] = hash
            }
            return heads
        case errSecItemNotFound:
            return [:]
        default:
            throw ReceiptIntegrityHeadStoreError.operationFailed(operation: "loadAll", status: status)
        }
    }

    public func saveHead(_ hash: String, for accountKey: String) throws {
        guard let data = hash.data(using: .utf8) else {
            throw ReceiptIntegrityHeadStoreError.stringEncodingFailed
        }

        let status = SecItemAdd(
            baseQuery(accountKey: accountKey).merging(
                [
                    kSecValueData as String: data,
                    kSecAttrAccessible as String: accessibility
                ],
                uniquingKeysWith: { _, new in new }
            ) as CFDictionary,
            nil
        )

        switch status {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let updateStatus = SecItemUpdate(
                baseQuery(accountKey: accountKey) as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                throw ReceiptIntegrityHeadStoreError.operationFailed(operation: "update", status: updateStatus)
            }
        default:
            throw ReceiptIntegrityHeadStoreError.operationFailed(operation: "save", status: status)
        }
    }

    public func clearHead(for accountKey: String) throws {
        let status = SecItemDelete(baseQuery(accountKey: accountKey) as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw ReceiptIntegrityHeadStoreError.operationFailed(operation: "delete", status: status)
        }
    }

    public func clearAllHeads() throws {
        let status = SecItemDelete(serviceQuery() as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw ReceiptIntegrityHeadStoreError.operationFailed(operation: "deleteAll", status: status)
        }
    }

    private func baseQuery(accountKey: String) -> [String: Any] {
        var query = serviceQuery()
        query[kSecAttrAccount as String] = accountKey
        return query
    }

    private func serviceQuery() -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        #if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        return query
    }
}

public actor InMemoryReceiptIntegrityHeadStore: ReceiptIntegrityHeadStoring {
    private var heads: [String: String] = [:]

    public init() { }

    public func loadHead(for accountKey: String) -> String? {
        heads[accountKey]
    }

    public func loadAllHeads() -> [String: String] {
        heads
    }

    public func saveHead(_ hash: String, for accountKey: String) {
        heads[accountKey] = hash
    }

    public func clearHead(for accountKey: String) {
        heads.removeValue(forKey: accountKey)
    }

    public func clearAllHeads() {
        heads.removeAll()
    }
}
