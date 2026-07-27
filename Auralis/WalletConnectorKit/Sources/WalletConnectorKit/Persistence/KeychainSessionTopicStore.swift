import Foundation
import Security

public struct WalletSessionTopicRecord: Hashable, Codable, Sendable {
    public let address: String
    public let topic: WalletPairingTopic

    public init(address: String, topic: WalletPairingTopic) {
        self.address = address
        self.topic = topic
    }
}

public enum WalletSessionTopicStoreError: Error, Equatable, Sendable {
    case invalidTopicData
    case keychainFailure(OSStatus)
}

public protocol WalletSessionTopicStoring: Sendable {
    func save(topic: WalletPairingTopic, walletAddress: String) async throws
    func load(walletAddress: String) async throws -> WalletPairingTopic?
    func loadAll() async throws -> [WalletSessionTopicRecord]
    func delete(walletAddress: String) async throws
}

public actor InMemoryWalletSessionTopicStore: WalletSessionTopicStoring {
    private var topicsByAddress: [String: WalletPairingTopic]

    public init(records: [WalletSessionTopicRecord] = []) {
        self.topicsByAddress = Dictionary(uniqueKeysWithValues: records.map { ($0.address, $0.topic) })
    }

    public func save(topic: WalletPairingTopic, walletAddress: String) {
        topicsByAddress[walletAddress] = topic
    }

    public func load(walletAddress: String) -> WalletPairingTopic? {
        topicsByAddress[walletAddress]
    }

    public func loadAll() -> [WalletSessionTopicRecord] {
        topicsByAddress.keys.sorted().compactMap { address in
            topicsByAddress[address].map { WalletSessionTopicRecord(address: address, topic: $0) }
        }
    }

    public func delete(walletAddress: String) {
        topicsByAddress.removeValue(forKey: walletAddress)
    }
}

public actor KeychainWalletSessionTopicStore: WalletSessionTopicStoring {
    private let queryFactory: KeychainSessionTopicQueryFactory

    public init(service: String = "com.auraplay.walletconnect") {
        self.queryFactory = KeychainSessionTopicQueryFactory(service: service)
    }

    public func save(topic: WalletPairingTopic, walletAddress: String) throws {
        let data = Data(topic.rawValue.utf8)
        let addStatus = SecItemAdd(queryFactory.addQuery(walletAddress: walletAddress, topicData: data) as CFDictionary, nil)

        switch addStatus {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let updateStatus = SecItemUpdate(
                queryFactory.lookupQuery(walletAddress: walletAddress) as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                throw WalletSessionTopicStoreError.keychainFailure(updateStatus)
            }
        default:
            throw WalletSessionTopicStoreError.keychainFailure(addStatus)
        }
    }

    public func load(walletAddress: String) throws -> WalletPairingTopic? {
        var query = queryFactory.lookupQuery(walletAddress: walletAddress)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard
                let data = result as? Data,
                let rawTopic = String(data: data, encoding: .utf8)
            else {
                throw WalletSessionTopicStoreError.invalidTopicData
            }
            return WalletPairingTopic(rawValue: rawTopic)
        case errSecItemNotFound:
            return nil
        default:
            throw WalletSessionTopicStoreError.keychainFailure(status)
        }
    }

    public func loadAll() throws -> [WalletSessionTopicRecord] {
        var query = queryFactory.allItemsQuery()
        query[kSecReturnAttributes as String] = true
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitAll

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let rows = result as? [[String: Any]] else {
                throw WalletSessionTopicStoreError.invalidTopicData
            }
            return try rows.compactMap { row in
                guard let address = row[kSecAttrAccount as String] as? String else {
                    return nil
                }
                guard
                    let data = row[kSecValueData as String] as? Data,
                    let rawTopic = String(data: data, encoding: .utf8)
                else {
                    throw WalletSessionTopicStoreError.invalidTopicData
                }
                return WalletSessionTopicRecord(address: address, topic: WalletPairingTopic(rawValue: rawTopic))
            }
        case errSecItemNotFound:
            return []
        default:
            throw WalletSessionTopicStoreError.keychainFailure(status)
        }
    }

    public func delete(walletAddress: String) throws {
        let status = SecItemDelete(queryFactory.lookupQuery(walletAddress: walletAddress) as CFDictionary)

        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw WalletSessionTopicStoreError.keychainFailure(status)
        }
    }
}

struct KeychainSessionTopicQueryFactory: Sendable {
    static let defaultService = "com.auraplay.walletconnect"

    let service: String

    func addQuery(walletAddress: String, topicData: Data) -> [String: Any] {
        var query = lookupQuery(walletAddress: walletAddress)
        query[kSecValueData as String] = topicData
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        query[kSecAttrSynchronizable as String] = false
        return query
    }

    func lookupQuery(walletAddress: String) -> [String: Any] {
        var query = baseQuery()
        query[kSecAttrAccount as String] = walletAddress
        return query
    }

    func allItemsQuery() -> [String: Any] {
        baseQuery()
    }

    private func baseQuery() -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: false,
        ]
#if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
#endif
        return query
    }
}
