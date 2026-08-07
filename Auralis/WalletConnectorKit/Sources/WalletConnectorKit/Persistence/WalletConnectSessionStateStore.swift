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
    public let connectedAt: Date
    public let expiryDate: Date

    public init(
        sessionTopic: String,
        pairingTopic: String,
        sessionSymmetricKeyHex: String,
        selfPrivateKeyHex: String?,
        providerID: WalletProviderID,
        providerName: String,
        accounts: [WalletAccount],
        namespaces: [WalletSessionNamespace],
        connectedAt: Date,
        expiryDate: Date
    ) {
        self.sessionTopic = sessionTopic
        self.pairingTopic = pairingTopic
        self.sessionSymmetricKeyHex = sessionSymmetricKeyHex
        self.selfPrivateKeyHex = selfPrivateKeyHex
        self.providerID = providerID
        self.providerName = providerName
        self.accounts = accounts
        self.namespaces = namespaces
        self.connectedAt = connectedAt
        self.expiryDate = expiryDate
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
            expiryDate: expiryDate
        )
    }
}

/// Persists the full protocol state needed to resume custom-transport sessions.
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

    public func save(_ session: WalletConnectPersistedSession) {
        byTopic[session.sessionTopic] = session
    }

    public func loadAll() -> [WalletConnectPersistedSession] {
        byTopic.keys.sorted().compactMap { byTopic[$0] }
    }

    public func delete(sessionTopic: String) {
        byTopic.removeValue(forKey: sessionTopic)
    }
}

/// Keychain-backed store for cross-launch session restoration.
///
/// All sessions are kept in a single device-local generic-password item
/// (account `session-record`) holding a JSON array, so this never collides with
/// the topic index or the relay-auth identity that share the same service. The
/// item is `WhenUnlockedThisDeviceOnly` and non-syncing because it carries
/// session key material.
///
/// Persistence is best-effort: if the keychain is unavailable (e.g. a unit-test
/// host without the entitlement, `errSecMissingEntitlement`), saves and deletes
/// are dropped and loads return empty rather than hard-failing the transport —
/// only cross-launch restoration is lost, never a live connection.
public actor KeychainWalletConnectSessionStateStore: WalletConnectSessionStatePersisting {
    private let service: String
    private let account = WalletKeychainRecordKind.sessionRecord.rawValue
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(service: String = "com.auraplay.walletconnect") {
        self.service = service
    }

    public func save(_ session: WalletConnectPersistedSession) {
        var sessions = load()
        sessions.removeAll { $0.sessionTopic == session.sessionTopic }
        sessions.append(session)
        write(sessions)
    }

    public func loadAll() -> [WalletConnectPersistedSession] {
        load().sorted { $0.sessionTopic < $1.sessionTopic }
    }

    public func delete(sessionTopic: String) {
        var sessions = load()
        sessions.removeAll { $0.sessionTopic == sessionTopic }
        write(sessions)
    }

    // MARK: - Keychain

    private func baseQuery() -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]
#if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
#endif
        return query
    }

    private func load() -> [WalletConnectPersistedSession] {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let sessions = try? decoder.decode([WalletConnectPersistedSession].self, from: data) else {
            return []
        }
        return sessions
    }

    private func write(_ sessions: [WalletConnectPersistedSession]) {
        guard let data = try? encoder.encode(sessions) else { return }

        if sessions.isEmpty {
            SecItemDelete(baseQuery() as CFDictionary)
            return
        }

        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(baseQuery() as CFDictionary, attributes as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = baseQuery()
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            SecItemAdd(addQuery as CFDictionary, nil)
        default:
            // Keychain unavailable: drop the write rather than hard-fail.
            return
        }
    }
}
