import Foundation
import Security

/// A fully-restorable snapshot of a settled custom-transport WalletConnect v2
/// session.
///
/// A stored *topic* alone is only a locker number; to actually resume a live
/// session across launches the transport also needs the derived session
/// symmetric key, the local X25519 key-agreement private key, the pairing
/// lineage, and the settled session metadata. Persisting this record is what
/// lets `WalletConnectIRNTransportClient` come back up after the process exits
/// instead of silently losing every session.
///
/// The session symmetric key and the self private key are secrets, so the
/// keychain-backed store keeps this device-local, non-syncing, and readable
/// only while the device is unlocked.
public struct WalletConnectPersistedSession: Hashable, Codable, Sendable {
    public let sessionTopic: String
    public let pairingTopic: String
    public let sessionSymmetricKeyHex: String
    /// Raw representation (hex) of the local X25519 key-agreement private key.
    /// Optional so records written by older builds still decode.
    public let selfPrivateKeyHex: String?
    public let providerID: WalletProviderID
    public let providerName: String
    public let accounts: [WalletAccount]
    public let namespaces: [WalletSessionNamespace]
    /// Required proposal namespaces that this session had to satisfy. Optional so
    /// records written before required-namespace tracking still decode.
    public let requiredNamespaces: WalletNamespaceProposalSet?
    /// CAIP-2 chain identifiers (including known-chain aliases) from the original
    /// proposal. Optional so older records decode; `nil` means the old record did
    /// not preserve this constraint.
    public let allowedChains: Set<String>?
    public let connectedAt: Date
    public let expiryDate: Date
    /// Whether the wallet proved control of these accounts (survives relaunch so
    /// a verified session is not silently downgraded to "claimed" on restore).
    /// Optional so records written before ownership tracking still decode.
    public let addressVerified: Bool?

    public init(
        sessionTopic: String,
        pairingTopic: String,
        sessionSymmetricKeyHex: String,
        selfPrivateKeyHex: String?,
        providerID: WalletProviderID,
        providerName: String,
        accounts: [WalletAccount],
        namespaces: [WalletSessionNamespace],
        requiredNamespaces: WalletNamespaceProposalSet? = nil,
        allowedChains: Set<String>? = nil,
        connectedAt: Date,
        expiryDate: Date,
        addressVerified: Bool? = nil
    ) {
        self.sessionTopic = sessionTopic
        self.pairingTopic = pairingTopic
        self.sessionSymmetricKeyHex = sessionSymmetricKeyHex
        self.selfPrivateKeyHex = selfPrivateKeyHex
        self.providerID = providerID
        self.providerName = providerName
        self.accounts = accounts
        self.namespaces = namespaces
        self.requiredNamespaces = requiredNamespaces
        self.allowedChains = allowedChains
        self.connectedAt = connectedAt
        self.expiryDate = expiryDate
        self.addressVerified = addressVerified
    }

    public var isExpired: Bool {
        expiryDate <= Date()
    }

    /// The in-memory `WalletSession` this record rehydrates to.
    public var walletSession: WalletSession {
        WalletSession(
            id: WalletSessionID(rawValue: sessionTopic),
            topic: WalletPairingTopic(rawValue: sessionTopic),
            providerID: providerID,
            providerName: providerName,
            accounts: accounts,
            namespaces: namespaces,
            connectedAt: connectedAt,
            expiryDate: expiryDate,
            addressVerified: addressVerified ?? false
        )
    }
}

/// Persists the full protocol state needed to resume custom-transport sessions.
public enum WalletConnectSessionStateStoreError: Error, Equatable, Sendable {
    case unreadable(OSStatus)
    case writeFailed(OSStatus)
    case encodingFailed
}

public protocol WalletConnectSessionStatePersisting: Sendable {
    func save(_ session: WalletConnectPersistedSession) async throws
    func loadAll() async throws -> [WalletConnectPersistedSession]
    func delete(sessionTopic: String) async throws
}

/// In-memory store used by tests and by callers that opt out of cross-launch
/// restoration. This is the transport's default so a bare `WalletConnectIRNTransportClient`
/// stays hermetic; ship a `KeychainWalletConnectSessionStateStore` for real
/// cross-launch restoration.
public actor InMemoryWalletConnectSessionStateStore: WalletConnectSessionStatePersisting {
    private var byTopic: [String: WalletConnectPersistedSession]

    public init(sessions: [WalletConnectPersistedSession] = []) {
        self.byTopic = Dictionary(uniqueKeysWithValues: sessions.map { ($0.sessionTopic, $0) })
    }

    public func save(_ session: WalletConnectPersistedSession) throws {
        byTopic[session.sessionTopic] = session
    }

    public func loadAll() -> [WalletConnectPersistedSession] {
        byTopic.keys.sorted().compactMap { byTopic[$0] }
    }

    public func delete(sessionTopic: String) throws {
        byTopic.removeValue(forKey: sessionTopic)
    }
}

/// Keychain-backed store for cross-launch session restoration.
///
/// Each session is kept in its **own** device-local generic-password item, keyed
/// by `session-record:<sessionTopic>`, so it never collides with the topic index
/// or the relay-auth identity that share the same service. Items are
/// `WhenUnlockedThisDeviceOnly` and non-syncing because they carry session key
/// material.
///
/// One-item-per-session (rather than a single shared JSON blob) removes a
/// cross-process write hazard: because `save`/`delete` mutate only the one item
/// for the affected topic — never a read-modify-write of a record holding *every*
/// session — two processes pointed at the same service (e.g. the app and an app
/// extension sharing session data) writing **different** sessions can no longer
/// clobber each other's records. Concurrent writes to the *same* topic still
/// last-writer-win, which is acceptable. Within one process the `actor` continues
/// to serialize all access.
///
/// Records written by older builds as one legacy `session-record` JSON-array blob
/// are transparently migrated to the per-topic layout on first access and then
/// removed (see `migrateLegacyRecordsIfNeeded`).
///
/// Persistence fails closed for writes: if the keychain is unavailable (e.g. a
/// unit-test host without the entitlement, `errSecMissingEntitlement`), saves and
/// deletes throw after reporting degradation. `loadAll` fails closed when the
/// keychain is unreadable so callers do not mistake hidden session state for "no
/// sessions" and destructively clean up accounts. A single item whose bytes do
/// not decode is treated as already lost and purged without dropping the others.
public actor KeychainWalletConnectSessionStateStore: WalletConnectSessionStatePersisting {
    /// Shared production store for the default keychain service. Prefer injecting
    /// this singleton into app composition so every custom IRN transport instance
    /// in this process serializes its keychain access through one actor.
    public static let shared = KeychainWalletConnectSessionStateStore()

    private let service: String
    /// Keychain-sharing access group these per-session items are written into.
    /// `nil` keeps them in the app's private default group (see `init`).
    private let accessGroup: String?
    /// Per-session account prefix: one keychain item per session topic.
    private let accountPrefix = WalletKeychainRecordKind.sessionRecord.rawValue + ":"
    /// Legacy single-blob account (all sessions in one JSON array). Retained only
    /// so pre-existing records migrate to the per-topic layout.
    private let legacyAccount = WalletKeychainRecordKind.sessionRecord.rawValue
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    /// Whether the one-shot legacy-blob migration has already run this process, so
    /// steady-state operations skip the extra keychain read after it completes.
    private var didMigrateLegacyRecords = false
    /// Invoked when a keychain write is dropped (keychain unavailable). Lets the
    /// host surface that a session that *looks* persisted was not actually
    /// stored, instead of the degradation being completely silent.
    private let onPersistenceDegraded: (@Sendable (OSStatus) -> Void)?

    /// - Parameter accessGroup: the keychain-sharing access group session-state
    ///   items (which carry session key material) are written into. `nil`
    ///   (default) keeps them in the app's private default access group — the
    ///   secure default. Pass a shared group **only** if an app extension must
    ///   read/restore custom-IRN sessions; the host must also carry the matching
    ///   Keychain Sharing entitlement, and it must match the group used by the
    ///   topic and relay-identity stores that share this service. Without this,
    ///   an extension cannot see these items at all (they are not shared merely
    ///   by an App Group container).
    public init(
        service: String = "com.auraplay.walletconnect",
        accessGroup: String? = nil,
        onPersistenceDegraded: (@Sendable (OSStatus) -> Void)? = nil
    ) {
        self.service = service
        self.accessGroup = accessGroup
        self.onPersistenceDegraded = onPersistenceDegraded
    }

    /// Consolidates pre-existing items into the shared access group before any
    /// account-layout migration, so an extension-shared store sees sessions that
    /// earlier builds wrote into the private default group. No-op when no shared
    /// group is configured.
    private func migrateAccessGroupIfNeeded() {
        guard let accessGroup else { return }
        KeychainAccessGroupMigration.migrateServiceIfNeeded(service: service, targetGroup: accessGroup)
    }

    public func save(_ session: WalletConnectPersistedSession) throws {
        migrateAccessGroupIfNeeded()
        migrateLegacyRecordsIfNeeded()
        guard let data = try? encoder.encode(session) else {
            throw WalletConnectSessionStateStoreError.encodingFailed
        }
        // Writes only this session's own item, so a locked/hidden keychain can
        // never cause us to clobber other sessions — and a write failure still
        // throws (fail-closed) so the transport does not emit a phantom success.
        try writeItem(account: accountPrefix + session.sessionTopic, data: data)
    }

    public func loadAll() throws -> [WalletConnectPersistedSession] {
        migrateAccessGroupIfNeeded()
        migrateLegacyRecordsIfNeeded()
        switch loadAllOutcome() {
        case .records(let sessions):
            return sessions.sorted { $0.sessionTopic < $1.sessionTopic }
        case .unreadable(let status):
            onPersistenceDegraded?(status)
            throw WalletConnectSessionStateStoreError.unreadable(status)
        }
    }

    public func delete(sessionTopic: String) throws {
        migrateAccessGroupIfNeeded()
        migrateLegacyRecordsIfNeeded()
        let status = SecItemDelete(itemQuery(account: accountPrefix + sessionTopic) as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            onPersistenceDegraded?(status)
            throw WalletConnectSessionStateStoreError.writeFailed(status)
        }
    }

    // MARK: - Keychain

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

    private func itemQuery(account: String) -> [String: Any] {
        var query = baseQuery()
        query[kSecAttrAccount as String] = account
        return query
    }

    /// The result of enumerating every per-session item:
    /// - `.records`: the decodable sessions (possibly empty). Any single item that
    ///   did not decode is purged as already-lost and reported via degradation,
    ///   without dropping the others.
    /// - `.unreadable`: the keychain returned an error (locked, missing
    ///   entitlement, …); state may be intact but hidden, so callers must NOT
    ///   treat it as "no sessions".
    private enum LoadAllOutcome {
        case records([WalletConnectPersistedSession])
        case unreadable(OSStatus)
    }

    private func loadAllOutcome() -> LoadAllOutcome {
        var query = baseQuery()
        query[kSecReturnAttributes as String] = true
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitAll

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let rows = result as? [[String: Any]] else { return .records([]) }
            var sessions: [WalletConnectPersistedSession] = []
            var corruptAccounts: [String] = []
            for row in rows {
                // The service is shared with the topic index and relay identity;
                // only our own per-session items carry the `session-record:` prefix.
                guard let account = row[kSecAttrAccount as String] as? String,
                      account.hasPrefix(accountPrefix) else { continue }
                guard let data = row[kSecValueData as String] as? Data,
                      let session = try? decoder.decode(WalletConnectPersistedSession.self, from: data) else {
                    corruptAccounts.append(account)
                    continue
                }
                sessions.append(session)
            }
            if !corruptAccounts.isEmpty {
                onPersistenceDegraded?(errSecDecode)
                for account in corruptAccounts {
                    // Best-effort purge of the individual lost item.
                    _ = SecItemDelete(itemQuery(account: account) as CFDictionary)
                }
            }
            return .records(sessions)
        case errSecItemNotFound:
            return .records([])
        default:
            return .unreadable(status)
        }
    }

    private func writeItem(account: String, data: Data) throws {
        let updateStatus = SecItemUpdate(itemQuery(account: account) as CFDictionary, updateAttributes(data: data) as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            try addItem(account: account, data: data)
        case errSecParam:
            // The platform refused to mutate the stored attributes in place (e.g.
            // migrating a weaker accessibility class); replace the exact item so it
            // adopts `WhenUnlockedThisDeviceOnly` instead of keeping the old class.
            try replaceItem(account: account, data: data)
        default:
            onPersistenceDegraded?(updateStatus)
            throw WalletConnectSessionStateStoreError.writeFailed(updateStatus)
        }
    }

    private func updateAttributes(data: Data) -> [String: Any] {
        [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
    }

    private func addItem(account: String, data: Data) throws {
        var addQuery = itemQuery(account: account)
        updateAttributes(data: data).forEach { key, value in
            addQuery[key] = value
        }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess {
            onPersistenceDegraded?(addStatus)
            throw WalletConnectSessionStateStoreError.writeFailed(addStatus)
        }
    }

    private func replaceItem(account: String, data: Data) throws {
        let deleteStatus = SecItemDelete(itemQuery(account: account) as CFDictionary)
        if deleteStatus != errSecSuccess, deleteStatus != errSecItemNotFound {
            onPersistenceDegraded?(deleteStatus)
            throw WalletConnectSessionStateStoreError.writeFailed(deleteStatus)
        }
        try addItem(account: account, data: data)
    }

    // MARK: - Legacy migration

    /// One-shot migration of the legacy single-blob `session-record` item into the
    /// per-topic layout. Idempotent and cheap after the first successful run (a
    /// `notFound` read). Best-effort: if the keychain is momentarily unreadable, it
    /// simply retries on the next call; if a partial write fails, the legacy blob
    /// is left in place so nothing is lost and the split is retried later.
    private func migrateLegacyRecordsIfNeeded() {
        guard !didMigrateLegacyRecords else { return }

        var query = itemQuery(account: legacyAccount)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let sessions = try? decoder.decode([WalletConnectPersistedSession].self, from: data) else {
                // Present but unusable — already lost; drop it.
                onPersistenceDegraded?(errSecDecode)
                _ = SecItemDelete(itemQuery(account: legacyAccount) as CFDictionary)
                didMigrateLegacyRecords = true
                return
            }
            var allMigrated = true
            for session in sessions {
                guard let encoded = try? encoder.encode(session) else { allMigrated = false; continue }
                do {
                    try writeItem(account: accountPrefix + session.sessionTopic, data: encoded)
                } catch {
                    allMigrated = false
                }
            }
            // Only drop the legacy blob once every session survived the split, so a
            // partial failure is safely retried on a later call.
            if allMigrated {
                _ = SecItemDelete(itemQuery(account: legacyAccount) as CFDictionary)
                didMigrateLegacyRecords = true
            }
        case errSecItemNotFound:
            didMigrateLegacyRecords = true
        default:
            // Unreadable right now; leave the flag unset so we retry next time.
            break
        }
    }
}
