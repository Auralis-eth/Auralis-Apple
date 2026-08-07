import CryptoKit
import Foundation

/// Builds the Ed25519 DID-JWT the WalletConnect relay requires as its `auth`
/// query parameter. Mirrors reown-swift `ClientIdAuthenticator` / `RelayAuthPayload`.
///
/// The JWT is `base64url(header) . base64url(claims) . base64url(signature)` where
/// - header = `{"alg":"EdDSA","typ":"JWT"}`
/// - claims = `{"iss":<did:key>,"sub":<random hex>,"aud":<relayURL>,"iat":…,"exp":…}`
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
    }

    /// Creates a signed relay auth token valid for `ttl` (default 1 day, matching
    /// the reference implementation).
    static func createToken(
        privateKey: Curve25519.Signing.PrivateKey,
        audience: String,
        subject: String = randomSubject(),
        issuedAt: Date = Date(),
        ttl: TimeInterval = 86_400
    ) throws -> String {
        let iss = didKey(ed25519PublicKey: privateKey.publicKey.rawRepresentation)
        let claims = Claims(
            iss: iss,
            sub: subject,
            aud: audience,
            iat: UInt64(issuedAt.timeIntervalSince1970),
            exp: UInt64(issuedAt.addingTimeInterval(ttl).timeIntervalSince1970)
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

    static func randomSubject() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
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
public struct WalletConnectKeychainRelayAuthProvider: WalletConnectRelayAuthProviding {
    private let service: String
    private let account = WalletKeychainRecordKind.relayAuthIdentity.rawValue

    public init(service: String = "com.auraplay.walletconnect") {
        self.service = service
    }

    public func authToken(audience: String) throws -> String {
        let key = try loadOrCreateKey()
        return try WalletConnectRelayAuth.createToken(privateKey: key, audience: audience)
    }

    private func loadOrCreateKey() throws -> Curve25519.Signing.PrivateKey {
        if let existing = try loadKey() {
            return existing
        }
        let key = Curve25519.Signing.PrivateKey()
        try storeKey(key)
        return key
    }

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

    private func loadKey() throws -> Curve25519.Signing.PrivateKey? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: data) else {
                throw WalletSessionTopicStoreError.invalidTopicData
            }
            return key
        case errSecItemNotFound:
            return nil
        default:
            throw WalletSessionTopicStoreError.keychainFailure(status)
        }
    }

    private func storeKey(_ key: Curve25519.Signing.PrivateKey) throws {
        var query = baseQuery()
        query[kSecValueData as String] = key.rawRepresentation
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw WalletSessionTopicStoreError.keychainFailure(status)
        }
    }
}

/// In-memory provider for tests; generates a fresh identity key per instance.
public struct WalletConnectEphemeralRelayAuthProvider: WalletConnectRelayAuthProviding {
    private let privateKey: Curve25519.Signing.PrivateKey

    public init(privateKey: Curve25519.Signing.PrivateKey = Curve25519.Signing.PrivateKey()) {
        self.privateKey = privateKey
    }

    public func authToken(audience: String) throws -> String {
        try WalletConnectRelayAuth.createToken(privateKey: privateKey, audience: audience)
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
}
