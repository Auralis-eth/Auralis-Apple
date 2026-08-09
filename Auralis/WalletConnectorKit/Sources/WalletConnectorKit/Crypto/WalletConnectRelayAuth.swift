import CryptoKit
import Foundation

/// Builds the Ed25519 DID-JWT the WalletConnect relay requires as its `auth`
/// query parameter. Mirrors reown-swift `ClientIdAuthenticator` / `RelayAuthPayload`.
///
/// The JWT is `base64url(header) . base64url(claims) . base64url(signature)` where
/// - header = `{"alg":"EdDSA","typ":"JWT"}`
/// - claims = `{"iss":<did:key>,"sub":<random hex>,"aud":<relayURL>,"iat":…,"exp":…,"act":"client_auth"}`
/// - `iss` is `did:key:z<base58btc(0xed01 ‖ publicKey)>`
enum WalletConnectRelayAuth {
    private struct Header: Encodable {
        let alg = "EdDSA"
        let typ = "JWT"
    }

    private struct Claims: Encodable {
        let iss: String
        let sub: String
        let aud: String
        let iat: UInt64
        let exp: UInt64
        let act = "client_auth"
    }

    /// Creates a signed relay auth token valid for `ttl` (default 1 day, matching
    /// the reference implementation).
    ///
    /// The reference impl mints `sub` once per app init and reuses it as a stable
    /// per-client correlation value; callers that want that behavior pass a cached
    /// `subject` (the keychain-backed provider does). When `subject` is `nil` a
    /// fresh random one is minted — harmless for plain socket authorization but not
    /// stable across tokens. Small backdate applied to `iat` so a device clock that
    /// runs slightly ahead of the relay does not produce a token the relay rejects
    /// as not-yet-valid.
    private static let clockSkewBackdate: TimeInterval = 60

    static func createToken(
        privateKey: Curve25519.Signing.PrivateKey,
        audience: String,
        subject: String? = nil,
        issuedAt: Date = Date(),
        ttl: TimeInterval = 86_400
    ) throws -> String {
        let iss = didKey(ed25519PublicKey: privateKey.publicKey.rawRepresentation)
        let issuedAtSeconds = issuedAt.timeIntervalSince1970
        let claims = Claims(
            iss: iss,
            sub: try subject ?? randomSubject(),
            aud: audience,
            iat: UInt64(max(0, issuedAtSeconds - clockSkewBackdate)),
            exp: UInt64(max(0, issuedAtSeconds + ttl))
        )

        let encoder = JSONEncoder()
        let headerString = base64url(try encoder.encode(Header()))
        let claimsString = base64url(try encoder.encode(claims))
        let signingInput = "\(headerString).\(claimsString)"
        guard let signingData = signingInput.data(using: .utf8) else {
            throw WalletConnectionError.cryptographyFailure
        }
        let signature = try privateKey.signature(for: signingData)
        return "\(signingInput).\(base64url(signature))"
    }

    /// `did:key` encoding of an Ed25519 public key (multicodec `0xed01`, base58btc).
    static func didKey(ed25519PublicKey publicKey: Data) -> String {
        let multicodec = Data([0xed, 0x01]) + publicKey
        return "did:key:z\(WalletConnectBase58.encode(multicodec))"
    }

    static func randomSubject() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        // A non-success status leaves `bytes` all zero, yielding a predictable
        // subject. Fail loudly instead (mirrors the transport's randomBytes).
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw WalletConnectionError.cryptographyFailure
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Vends relay auth tokens for a given audience (relay URL). The client identity
/// key is persisted so the relay sees a stable `client_id` across launches.
public protocol WalletConnectRelayAuthProviding: Sendable {
    func authToken(audience: String) throws -> String
}

/// Keychain-backed provider: persists a single Ed25519 identity key under the
/// `relayAuthIdentity` record so the relay `client_id` is stable across launches.
/// Device-local, non-syncing, available only while unlocked.
///
/// If the keychain is unavailable (e.g. a unit-test host without the keychain
/// entitlement, `errSecMissingEntitlement`), it falls back to an in-memory
/// identity key cached for the process lifetime so relay auth never hard-fails —
/// only cross-launch `client_id` stability is lost.
public final class WalletConnectKeychainRelayAuthProvider: WalletConnectRelayAuthProviding, @unchecked Sendable {
    private let keychain: any WalletRelayIdentityKeychain
    private let lock = NSLock()
    private var ephemeralKey: Curve25519.Signing.PrivateKey?
    /// Minted once and reused so the relay sees a stable `sub` across every token
    /// this provider issues (mirrors reown's once-per-client subject), instead of
    /// a fresh value per token.
    private var cachedSubject: String?

    /// - Parameter accessGroup: the keychain-sharing access group the relay
    ///   identity item is written into. `nil` (default) keeps the item in the
    ///   app's private default access group. Pass a shared group **only** if an
    ///   app extension must reuse the same relay `client_id`; the host must also
    ///   carry the matching Keychain Sharing entitlement.
    public init(service: String = "com.auraplay.walletconnect", accessGroup: String? = nil) {
        self.keychain = SecItemRelayIdentityKeychain(service: service, accessGroup: accessGroup)
    }

    /// Test seam: injects the keychain backing so the load/store OSStatus
    /// handling can be exercised without a real keychain.
    init(keychain: any WalletRelayIdentityKeychain) {
        self.keychain = keychain
    }

    public func authToken(audience: String) throws -> String {
        let key = loadOrCreateKey()
        return try WalletConnectRelayAuth.createToken(privateKey: key, audience: audience, subject: stableSubject())
    }

    /// Returns the process-lifetime `sub`, minting it once on first use so every
    /// token this provider issues carries the same relay client correlation value.
    private func stableSubject() throws -> String {
        try lock.withLock {
            if let cachedSubject { return cachedSubject }
            let subject = try WalletConnectRelayAuth.randomSubject()
            cachedSubject = subject
            return subject
        }
    }

    private func loadOrCreateKey() -> Curve25519.Signing.PrivateKey {
        do {
            if let existing = try loadKey() {
                return existing
            }
        } catch WalletSessionTopicStoreError.invalidTopicData {
            // A record exists but its bytes do not decode to a valid Ed25519
            // identity (corrupt, truncated, or a foreign item on this account).
            // This can NEVER self-heal on its own: returning an ephemeral key
            // here would silently forfeit cross-launch client_id stability
            // forever, because every future load hits the same undecodable
            // bytes and takes this branch again. Purge the bad record and fall
            // through to mint and persist a fresh identity so persistence
            // recovers on this launch.
            try? deleteKey()
        } catch {
            // A transient load failure — device locked, or a missing
            // entitlement on a test host (`errSecMissingEntitlement`). Do NOT
            // treat this as "no key" and overwrite the record — fall back to a
            // stable in-memory key so relay auth still succeeds without
            // clobbering a record that may simply be temporarily unreadable.
            return ephemeralFallback()
        }

        // Genuinely no stored key (or a corrupt one we just purged): create and
        // persist a fresh identity.
        let key = Curve25519.Signing.PrivateKey()
        do {
            try storeKey(key)
            return key
        } catch WalletSessionTopicStoreError.keychainFailure(errSecDuplicateItem) {
            // A record already exists (a concurrent writer, or a load that
            // spuriously reported "not found"). Return the PERSISTED key, not
            // the one we just generated, so the relay client_id stays stable
            // across launches.
            if let existing = try? loadKey() {
                return existing
            }
            return ephemeralFallback(key)
        } catch {
            // Keychain unavailable: reuse a single in-memory identity key so the
            // relay still receives a valid, self-consistent auth token.
            return ephemeralFallback(key)
        }
    }

    /// Returns the process-lifetime in-memory identity key, seeding it with
    /// `candidate` on first use so repeated calls stay self-consistent.
    private func ephemeralFallback(_ candidate: Curve25519.Signing.PrivateKey = Curve25519.Signing.PrivateKey()) -> Curve25519.Signing.PrivateKey {
        lock.withLock {
            if let ephemeralKey { return ephemeralKey }
            ephemeralKey = candidate
            return candidate
        }
    }

    private func loadKey() throws -> Curve25519.Signing.PrivateKey? {
        guard let data = try keychain.loadIdentityData() else { return nil }
        guard let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: data) else {
            throw WalletSessionTopicStoreError.invalidTopicData
        }
        return key
    }

    private func storeKey(_ key: Curve25519.Signing.PrivateKey) throws {
        try keychain.storeIdentityData(key.rawRepresentation)
    }

    private func deleteKey() throws {
        try keychain.deleteIdentityData()
    }
}

/// Seam over the keychain SecItem calls so the load/store OSStatus handling in
/// `WalletConnectKeychainRelayAuthProvider` is unit-testable without a real
/// keychain (unavailable on many test hosts).
protocol WalletRelayIdentityKeychain: Sendable {
    /// Returns the persisted identity key data, `nil` when genuinely not found,
    /// and throws for any other keychain error.
    func loadIdentityData() throws -> Data?
    /// Persists identity key data. Throws
    /// `WalletSessionTopicStoreError.keychainFailure(errSecDuplicateItem)` when
    /// a record already exists.
    func storeIdentityData(_ data: Data) throws
    /// Removes a persisted identity record. Used to purge a record whose bytes
    /// no longer decode to a valid identity so a fresh one can replace it. A
    /// missing record is not an error.
    func deleteIdentityData() throws
}

/// Production keychain backing: device-local, non-syncing, unlocked-only.
struct SecItemRelayIdentityKeychain: WalletRelayIdentityKeychain {
    let service: String
    let accessGroup: String?
    let account = WalletKeychainRecordKind.relayAuthIdentity.rawValue

    init(service: String, accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    private func baseQuery() -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
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

    func loadIdentityData() throws -> Data? {
        // Consolidate a relay identity written by an earlier build into the shared
        // access group first, so an extension-shared identity keeps a stable
        // client_id. No-op when no shared group is configured.
        if let accessGroup {
            KeychainAccessGroupMigration.migrateServiceIfNeeded(service: service, targetGroup: accessGroup)
        }
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw WalletSessionTopicStoreError.invalidTopicData
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw WalletSessionTopicStoreError.keychainFailure(status)
        }
    }

    func storeIdentityData(_ data: Data) throws {
        var query = baseQuery()
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw WalletSessionTopicStoreError.keychainFailure(status)
        }
    }

    func deleteIdentityData() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw WalletSessionTopicStoreError.keychainFailure(status)
        }
    }
}

/// In-memory provider for tests; generates a fresh identity key per instance.
public struct WalletConnectEphemeralRelayAuthProvider: WalletConnectRelayAuthProviding {
    private let privateKey: Curve25519.Signing.PrivateKey
    // Minted once at init so every token from this instance carries a stable `sub`.
    private let subject: String

    public init(privateKey: Curve25519.Signing.PrivateKey = Curve25519.Signing.PrivateKey()) {
        self.privateKey = privateKey
        self.subject = (try? WalletConnectRelayAuth.randomSubject()) ?? UUID().uuidString
    }

    public func authToken(audience: String) throws -> String {
        try WalletConnectRelayAuth.createToken(privateKey: privateKey, audience: audience, subject: subject)
    }
}

/// Minimal base58btc encoder (Bitcoin alphabet) for `did:key` identifiers.
/// Ported from reown-swift `WalletConnectUtils/DID/Base58.swift`.
enum WalletConnectBase58 {
    private static let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
    private static let base = 58

    static func encode(_ bytes: Data) -> String {
        var input = bytes
        var zeros = 0
        for byte in input {
            if byte != 0 { break }
            zeros += 1
        }
        input.removeFirst(zeros)

        let size = input.count * 138 / 100 + 1
        var encoded = [UInt8](repeating: 0, count: size)
        var length = 0
        for byte in input {
            var carry = Int(byte)
            var i = 0
            for j in stride(from: encoded.count - 1, through: 0, by: -1) where carry != 0 || i < length {
                carry += 256 * Int(encoded[j])
                encoded[j] = UInt8(carry % base)
                carry /= base
                i += 1
            }
            length = i
        }

        var trim = 0
        for byte in encoded {
            if byte != 0 { break }
            trim += 1
        }
        encoded.removeFirst(trim)

        return String(repeating: "1", count: zeros) + String(encoded.map { alphabet[Int($0)] })
    }

    /// Decodes a base58btc string back to bytes, returning `nil` for any character
    /// outside the Bitcoin alphabet. Used to recover a Solana account's raw ed25519
    /// public key (32 bytes) from its base58 address for ownership verification.
    static func decode(_ string: String) -> Data? {
        guard !string.isEmpty else { return Data() }

        var leadingZeros = 0
        for character in string {
            if character == "1" { leadingZeros += 1 } else { break }
        }

        var decoded = [UInt8](repeating: 0, count: string.count * 733 / 1000 + 1)
        var length = 0
        for character in string {
            guard let value = alphabet.firstIndex(of: character) else { return nil }
            var carry = value
            var i = 0
            for j in stride(from: decoded.count - 1, through: 0, by: -1) where carry != 0 || i < length {
                carry += base * Int(decoded[j])
                decoded[j] = UInt8(carry % 256)
                carry /= 256
                i += 1
            }
            length = i
        }

        var trim = 0
        for byte in decoded {
            if byte != 0 { break }
            trim += 1
        }
        decoded.removeFirst(trim)

        return Data(repeating: 0, count: leadingZeros) + Data(decoded)
    }
}
