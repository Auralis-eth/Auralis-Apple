import Foundation
import Security

public enum WalletKeychainRecordKind: String, CaseIterable, Hashable, Codable, Sendable {
    case relayAuthIdentity = "relay-auth-identity"
    case pairingRecord = "pairing-record"
    case pairingSymmetricKey = "pairing-symmetric-key"
    case sessionRecord = "session-record"
    case sessionSymmetricKey = "session-symmetric-key"
    case sessionTopic = "session-topic"
    case providerSessionReference = "provider-session-reference"
}

public struct WalletSessionTopicRecord: Hashable, Codable, Sendable {
    public let address: String
    public let topic: WalletPairingTopic
    /// The chain the address belongs to. Optional for backward compatibility
    /// with records persisted before the chain was stored; when absent, callers
    /// fall back to inferring the chain from the address format.
    public let chain: WalletChain?
    /// Whether the wallet proved ownership of this address at connect time.
    ///
    /// SDK connectors (Reown/Coinbase) hold their session records in a vendor
    /// store outside this package, so a restored SDK session always reports
    /// `addressVerified == false` even after a successful connect-time proof.
    /// Persisting the proof here lets restore merge it back rather than dropping
    /// the wallet from the active set on every cold launch. Defaults to `false`
    /// so a legacy record (or an unverified flow) is never silently trusted.
    public let verified: Bool

    public init(address: String, topic: WalletPairingTopic, chain: WalletChain? = nil, verified: Bool = false) {
        self.address = address
        self.topic = topic
        self.chain = chain
        self.verified = verified
    }
}

public struct WalletKeychainRecordDescriptor: Hashable, Codable, Sendable {
    public let kind: WalletKeychainRecordKind
    public let identifier: String

    public init(kind: WalletKeychainRecordKind, identifier: String) {
        self.kind = kind
        self.identifier = identifier
    }

    public var accountKey: String {
        "\(kind.rawValue):\(identifier)"
    }
}

public enum WalletSessionTopicStoreError: Error, Equatable, Sendable {
    case invalidTopicData
    case keychainFailure(OSStatus)
}

public protocol WalletSessionTopicStoring: Sendable {
    func save(topic: WalletPairingTopic, walletAddress: String, chain: WalletChain?) async throws
    func load(walletAddress: String, chain: WalletChain?) async throws -> WalletPairingTopic?
    func loadAll() async throws -> [WalletSessionTopicRecord]
    func delete(walletAddress: String, chain: WalletChain?) async throws

    /// Persists a topic record, recording whether the wallet proved ownership of
    /// `walletAddress` at connect time. The default implementation ignores
    /// `verified` and falls back to the ownership-agnostic `save` so existing
    /// conformers (e.g. test mocks) keep compiling; the shipped in-memory and
    /// keychain stores override it to actually persist the flag.
    func save(topic: WalletPairingTopic, walletAddress: String, chain: WalletChain?, verified: Bool) async throws
}

public extension WalletSessionTopicStoring {
    func save(topic: WalletPairingTopic, walletAddress: String) async throws {
        try await save(topic: topic, walletAddress: walletAddress, chain: nil)
    }

    func load(walletAddress: String) async throws -> WalletPairingTopic? {
        try await load(walletAddress: walletAddress, chain: nil)
    }

    func delete(walletAddress: String) async throws {
        try await delete(walletAddress: walletAddress, chain: nil)
    }

    func save(topic: WalletPairingTopic, walletAddress: String, chain: WalletChain?, verified: Bool) async throws {
        try await save(topic: topic, walletAddress: walletAddress, chain: chain)
    }
}

public actor InMemoryWalletSessionTopicStore: WalletSessionTopicStoring {
    private var recordsByKey: [String: WalletSessionTopicRecord]

    public init(records: [WalletSessionTopicRecord] = []) {
        self.recordsByKey = Dictionary(uniqueKeysWithValues: records.map { (Self.recordKey(address: $0.address, chain: $0.chain), $0) })
    }

    public func save(topic: WalletPairingTopic, walletAddress: String, chain: WalletChain?) {
        save(topic: topic, walletAddress: walletAddress, chain: chain, verified: false)
    }

    public func save(topic: WalletPairingTopic, walletAddress: String, chain: WalletChain?, verified: Bool) {
        recordsByKey[Self.recordKey(address: walletAddress, chain: chain)] = WalletSessionTopicRecord(address: walletAddress, topic: topic, chain: chain, verified: verified)
    }

    public func load(walletAddress: String, chain: WalletChain?) -> WalletPairingTopic? {
        if let record = recordsByKey[Self.recordKey(address: walletAddress, chain: chain)] {
            return record.topic
        }
        guard chain == nil else { return nil }
        return recordsByKey.values
            .filter { $0.address == walletAddress }
            .sorted { Self.recordKey(address: $0.address, chain: $0.chain) < Self.recordKey(address: $1.address, chain: $1.chain) }
            .first?
            .topic
    }

    public func loadAll() -> [WalletSessionTopicRecord] {
        recordsByKey.keys.sorted().compactMap { recordsByKey[$0] }
    }

    public func delete(walletAddress: String, chain: WalletChain?) {
        recordsByKey.removeValue(forKey: Self.recordKey(address: walletAddress, chain: chain))
    }

    private static func recordKey(address: String, chain: WalletChain?) -> String {
        chain.map { "\($0.caip2):\(address)" } ?? address
    }
}

public actor KeychainWalletSessionTopicStore: WalletSessionTopicStoring {
    private let queryFactory: KeychainSessionTopicQueryFactory
    /// Whether the one-shot migration of legacy (un-namespaced) topic records to
    /// the `session-topic:` account layout has run this process. See
    /// `migrateLegacyTopicRecordsIfNeeded`.
    private var didMigrateLegacyTopicRecords = false

    /// - Parameter accessGroup: the keychain-sharing access group topic records
    ///   are written into. `nil` (default) keeps them in the app's private
    ///   default access group. Pass a shared group **only** if an app extension
    ///   must read/restore the same sessions; the host must also carry the
    ///   matching Keychain Sharing entitlement. Must match the group used by the
    ///   session-state and relay-identity stores that share this service.
    public init(service: String = "com.auraplay.walletconnect", accessGroup: String? = nil) {
        self.queryFactory = KeychainSessionTopicQueryFactory(service: service, accessGroup: accessGroup)
    }

    public func save(topic: WalletPairingTopic, walletAddress: String, chain: WalletChain?) throws {
        try save(topic: topic, walletAddress: walletAddress, chain: chain, verified: false)
    }

    /// Consolidates pre-existing topic records into the shared access group before
    /// the account-layout migration, so an extension-shared store sees records that
    /// earlier builds wrote into the private default group. No-op when no shared
    /// group is configured.
    private func migrateAccessGroupIfNeeded() {
        guard let accessGroup = queryFactory.accessGroup else { return }
        KeychainAccessGroupMigration.migrateServiceIfNeeded(service: queryFactory.service, targetGroup: accessGroup)
    }

    public func save(topic: WalletPairingTopic, walletAddress: String, chain: WalletChain?, verified: Bool) throws {
        migrateAccessGroupIfNeeded()
        migrateLegacyTopicRecordsIfNeeded()
        let data = Data(topic.rawValue.utf8)
        let addStatus = SecItemAdd(queryFactory.addQuery(walletAddress: walletAddress, topicData: data, chain: chain, verified: verified) as CFDictionary, nil)

        switch addStatus {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            // Always write the label (empty when no chain) and the verified flag
            // so re-saving overwrites any previously stored values rather than
            // leaving them stale.
            let attributes = queryFactory.updateAttributes(topicData: data, chain: chain, verified: verified)
            let updateStatus = SecItemUpdate(
                queryFactory.lookupQuery(walletAddress: walletAddress, chain: chain) as CFDictionary,
                attributes as CFDictionary
            )
            switch updateStatus {
            case errSecSuccess:
                return
            case errSecParam:
                try replaceExistingRecord(topic: topic, walletAddress: walletAddress, chain: chain, verified: verified)
            default:
                throw WalletSessionTopicStoreError.keychainFailure(updateStatus)
            }
        default:
            throw WalletSessionTopicStoreError.keychainFailure(addStatus)
        }
    }

    public func load(walletAddress: String, chain: WalletChain?) throws -> WalletPairingTopic? {
        migrateAccessGroupIfNeeded()
        migrateLegacyTopicRecordsIfNeeded()
        var query = queryFactory.lookupQuery(walletAddress: walletAddress, chain: chain)
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
            guard chain == nil else { return nil }
            return try loadFirstRecordMatchingAddress(walletAddress)
        default:
            throw WalletSessionTopicStoreError.keychainFailure(status)
        }
    }

    public func loadAll() throws -> [WalletSessionTopicRecord] {
        migrateAccessGroupIfNeeded()
        migrateLegacyTopicRecordsIfNeeded()
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
                // The keychain service is shared with the relay-auth identity and
                // the per-topic session-state records; only our own items carry the
                // `session-topic:` account prefix. Skip everything else so a foreign
                // record (e.g. raw Ed25519 identity bytes that are not valid UTF-8,
                // or a session-state JSON blob) is never mis-read as a topic — or, in
                // the non-UTF-8 case, made to throw and break restore entirely.
                guard let account = row[kSecAttrAccount as String] as? String,
                      account.hasPrefix(KeychainSessionTopicQueryFactory.accountPrefix) else {
                    return nil
                }
                guard
                    let data = row[kSecValueData as String] as? Data,
                    let rawTopic = String(data: data, encoding: .utf8)
                else {
                    throw WalletSessionTopicStoreError.invalidTopicData
                }
                let parsedIdentifier = KeychainSessionTopicQueryFactory.parseRecordIdentifier(account)
                let chain = (row[kSecAttrLabel as String] as? String).flatMap(WalletChain.init(caip2:))
                    ?? parsedIdentifier.chain
                // Absent on legacy records → treated as unverified (fail-closed).
                let verified = (row[kSecAttrDescription as String] as? String) == "1"
                return WalletSessionTopicRecord(
                    address: parsedIdentifier.address,
                    topic: WalletPairingTopic(rawValue: rawTopic),
                    chain: chain,
                    verified: verified
                )
            }
        case errSecItemNotFound:
            return []
        default:
            throw WalletSessionTopicStoreError.keychainFailure(status)
        }
    }

    public func delete(walletAddress: String, chain: WalletChain?) throws {
        migrateAccessGroupIfNeeded()
        migrateLegacyTopicRecordsIfNeeded()
        if let chain {
            let status = SecItemDelete(queryFactory.lookupQuery(walletAddress: walletAddress, chain: chain) as CFDictionary)
            switch status {
            case errSecSuccess, errSecItemNotFound:
                return
            default:
                throw WalletSessionTopicStoreError.keychainFailure(status)
            }
        }

        let legacyStatus = SecItemDelete(queryFactory.lookupQuery(walletAddress: walletAddress, chain: nil) as CFDictionary)
        guard legacyStatus == errSecSuccess || legacyStatus == errSecItemNotFound else {
            throw WalletSessionTopicStoreError.keychainFailure(legacyStatus)
        }
    }

    /// One-shot migration of legacy topic records that were stored keyed only by
    /// address (no `session-topic:` discriminator), from before this keychain
    /// service also held the relay-auth identity and the per-topic session-state
    /// records. Re-keys each legacy record under the namespaced account and removes
    /// the un-prefixed original, so `loadAll` can filter to its own records instead
    /// of mis-reading a foreign item as a topic.
    ///
    /// Best-effort and idempotent: records already namespaced, or belonging to
    /// another known record kind that shares this service (relay-auth identity,
    /// session-state records), are left untouched; a transient keychain error just
    /// retries on the next call.
    private func migrateLegacyTopicRecordsIfNeeded() {
        guard !didMigrateLegacyTopicRecords else { return }

        var query = queryFactory.allItemsQuery()
        query[kSecReturnAttributes as String] = true
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitAll

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            let rows = (result as? [[String: Any]]) ?? []
            var allMigrated = true
            for row in rows {
                guard let account = row[kSecAttrAccount as String] as? String else { continue }
                // Already namespaced.
                if account.hasPrefix(KeychainSessionTopicQueryFactory.accountPrefix) { continue }
                // Belongs to another record kind sharing this service (relay-auth
                // identity, per-topic session-state records, …) — never migrate it.
                if WalletKeychainRecordKind.allCases.contains(where: { account == $0.rawValue || account.hasPrefix($0.rawValue + ":") }) { continue }
                guard let data = row[kSecValueData as String] as? Data else { continue }
                let parsed = KeychainSessionTopicQueryFactory.parseRecordIdentifier(account)
                let chain = (row[kSecAttrLabel as String] as? String).flatMap(WalletChain.init(caip2:)) ?? parsed.chain
                let verified = (row[kSecAttrDescription as String] as? String) == "1"
                let addStatus = SecItemAdd(
                    queryFactory.addQuery(walletAddress: parsed.address, topicData: data, chain: chain, verified: verified) as CFDictionary,
                    nil
                )
                switch addStatus {
                case errSecSuccess, errSecDuplicateItem:
                    _ = SecItemDelete(queryFactory.rawItemQuery(account: account) as CFDictionary)
                default:
                    // Leave the legacy record in place and retry on a later call.
                    allMigrated = false
                }
            }
            if allMigrated { didMigrateLegacyTopicRecords = true }
        case errSecItemNotFound:
            didMigrateLegacyTopicRecords = true
        default:
            // Keychain momentarily unreadable; retry on the next call.
            break
        }
    }

    private func loadFirstRecordMatchingAddress(_ walletAddress: String) throws -> WalletPairingTopic? {
        try loadAll()
            .filter { $0.address == walletAddress }
            .sorted { lhs, rhs in
                KeychainSessionTopicQueryFactory.recordIdentifier(address: lhs.address, chain: lhs.chain)
                    < KeychainSessionTopicQueryFactory.recordIdentifier(address: rhs.address, chain: rhs.chain)
            }
            .first?
            .topic
    }

    private func replaceExistingRecord(topic: WalletPairingTopic, walletAddress: String, chain: WalletChain?, verified: Bool) throws {
        let deleteStatus = SecItemDelete(queryFactory.lookupQuery(walletAddress: walletAddress, chain: chain) as CFDictionary)
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
            throw WalletSessionTopicStoreError.keychainFailure(deleteStatus)
        }

        let data = Data(topic.rawValue.utf8)
        let addStatus = SecItemAdd(queryFactory.addQuery(walletAddress: walletAddress, topicData: data, chain: chain, verified: verified) as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw WalletSessionTopicStoreError.keychainFailure(addStatus)
        }
    }
}

struct KeychainSessionTopicQueryFactory: Sendable {
    static let defaultService = "com.auraplay.walletconnect"
    /// Account discriminator so a topic record never collides with the relay-auth
    /// identity or the per-topic session-state records that share this keychain
    /// service, and so `loadAll` can filter to only its own items.
    static let accountPrefix = WalletKeychainRecordKind.sessionTopic.rawValue + ":"

    let service: String
    let accessGroup: String?

    init(service: String, accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    func addQuery(walletAddress: String, topicData: Data, chain: WalletChain? = nil, verified: Bool = false) -> [String: Any] {
        var query = lookupQuery(walletAddress: walletAddress, chain: chain)
        updateAttributes(topicData: topicData, chain: chain, verified: verified).forEach { key, value in
            query[key] = value
        }
        return query
    }

    func updateAttributes(topicData: Data, chain: WalletChain? = nil, verified: Bool = false) -> [String: Any] {
        [
            kSecValueData as String: topicData,
            // Foreground-only, device-local storage: the pairing topic is readable
            // only while the device is unlocked and never syncs to iCloud Keychain.
            // Kept in sync with the store's unit/integration tests, which assert this
            // exact attribute.
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: false,
            // Store the chain (empty when unknown) so add and update stay symmetric.
            kSecAttrLabel as String: chain?.caip2 ?? "",
            // Persist the connect-time ownership proof ("1" verified / "0" not) so
            // restore can merge it onto SDK sessions whose vendor store cannot.
            kSecAttrDescription as String: verified ? "1" : "0",
        ]
    }

    func lookupQuery(walletAddress: String, chain: WalletChain? = nil) -> [String: Any] {
        var query = baseQuery()
        query[kSecAttrAccount as String] = Self.recordIdentifier(address: walletAddress, chain: chain)
        return query
    }


    func allItemsQuery() -> [String: Any] {
        baseQuery()
    }

    /// A lookup query addressing an item by its exact stored account. Used to
    /// remove a legacy (un-prefixed) topic record during migration, where the
    /// prefixing `recordIdentifier` cannot reproduce the old account key.
    func rawItemQuery(account: String) -> [String: Any] {
        var query = baseQuery()
        query[kSecAttrAccount as String] = account
        return query
    }

    static func recordIdentifier(address: String, chain: WalletChain?) -> String {
        accountPrefix + (chain.map { "\($0.caip2):\(address)" } ?? address)
    }

    static func parseRecordIdentifier(_ identifier: String) -> (address: String, chain: WalletChain?) {
        // Tolerate both the namespaced account (current) and a bare legacy account
        // (pre-migration), so parsing works during the one-shot migration too.
        let body = identifier.hasPrefix(accountPrefix)
            ? String(identifier.dropFirst(accountPrefix.count))
            : identifier
        let pieces = body.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard pieces.count == 3 else {
            return (body, nil)
        }
        let caip2 = "\(pieces[0]):\(pieces[1])"
        guard let chain = WalletChain(caip2: caip2) else {
            return (body, nil)
        }
        return (String(pieces[2]), chain)
    }

    private func baseQuery() -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: false,
        ]
        // Only pin an access group when the host opts into extension sharing;
        // otherwise the item stays in the app's private default group.
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
#if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
#endif
        return query
    }
}
