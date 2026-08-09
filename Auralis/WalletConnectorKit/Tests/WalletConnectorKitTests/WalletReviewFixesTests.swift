import CryptoKit
import Foundation
import Security
import Testing
@testable import WalletConnectorKit

@Suite("Review fixes")
struct WalletReviewFixesTests {
    // MARK: - #1 relay identity key persistence

    /// Injectable keychain seam. Optionally simulates a record that only becomes
    /// visible *after* a store attempt (the load-fails-but-item-exists race).
    private final class StubRelayIdentityKeychain: WalletRelayIdentityKeychain, @unchecked Sendable {
        var storedData: Data?
        var loadError: Error?
        var storeError: Error?
        var persistOnStore: Data?
        private(set) var storeCallCount = 0
        private(set) var deleteCallCount = 0
        private var didStore = false

        init(storedData: Data? = nil) { self.storedData = storedData }

        func loadIdentityData() throws -> Data? {
            if let loadError { throw loadError }
            if didStore, let persistOnStore { return persistOnStore }
            return storedData
        }

        func storeIdentityData(_ data: Data) throws {
            storeCallCount += 1
            didStore = true
            if let storeError { throw storeError }
            storedData = data
        }

        func deleteIdentityData() throws {
            deleteCallCount += 1
            // Clearing the corrupt record also clears the load error that
            // simulated it, so a subsequent load reflects the empty slot the
            // provider can repopulate with a fresh identity.
            storedData = nil
            loadError = nil
        }
    }

    private static func claims(ofJWT token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var b64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func iss(ofJWT token: String) -> String? {
        claims(ofJWT: token)?["iss"] as? String
    }

    @Test("Store-duplicate returns the persisted identity, not the freshly generated one")
    func relayIdentityStoreDuplicateReturnsPersisted() throws {
        let persistedKey = Curve25519.Signing.PrivateKey()
        let keychain = StubRelayIdentityKeychain()
        keychain.persistOnStore = persistedKey.rawRepresentation
        keychain.storeError = WalletSessionTopicStoreError.keychainFailure(errSecDuplicateItem)

        let provider = WalletConnectKeychainRelayAuthProvider(keychain: keychain)
        let token = try provider.authToken(audience: "wss://relay.example")

        let expected = WalletConnectRelayAuth.didKey(ed25519PublicKey: persistedKey.publicKey.rawRepresentation)
        #expect(Self.iss(ofJWT: token) == expected)
    }

    @Test("A non-not-found load error falls back to a stable in-memory key without overwriting")
    func relayIdentityLoadErrorFallsBackWithoutOverwrite() throws {
        let keychain = StubRelayIdentityKeychain()
        keychain.loadError = WalletSessionTopicStoreError.keychainFailure(errSecMissingEntitlement)

        let provider = WalletConnectKeychainRelayAuthProvider(keychain: keychain)
        let first = try provider.authToken(audience: "wss://relay.example")
        let second = try provider.authToken(audience: "wss://relay.example")

        // The record was never overwritten, and the client_id stays stable.
        #expect(keychain.storeCallCount == 0)
        #expect(Self.iss(ofJWT: first) != nil)
        #expect(Self.iss(ofJWT: first) == Self.iss(ofJWT: second))
    }

    @Test("A persisted key yields a stable client_id and is never re-stored")
    func relayIdentityPersistedKeyIsStable() throws {
        let persistedKey = Curve25519.Signing.PrivateKey()
        let keychain = StubRelayIdentityKeychain(storedData: persistedKey.rawRepresentation)
        let provider = WalletConnectKeychainRelayAuthProvider(keychain: keychain)

        let token = try provider.authToken(audience: "wss://relay.example")
        let expected = WalletConnectRelayAuth.didKey(ed25519PublicKey: persistedKey.publicKey.rawRepresentation)
        #expect(Self.iss(ofJWT: token) == expected)
        #expect(keychain.storeCallCount == 0)
    }

    @Test("A corrupt identity record is purged and replaced, then stays stable")
    func relayIdentityCorruptRecordSelfHeals() throws {
        // Bytes that exist but do not decode to a valid Ed25519 key: loadKey
        // throws `.invalidTopicData`. Before the fix this fell back to an
        // ephemeral key forever and never overwrote the bad record, silently
        // losing cross-launch client_id stability.
        let keychain = StubRelayIdentityKeychain(storedData: Data([0x01, 0x02, 0x03]))
        let provider = WalletConnectKeychainRelayAuthProvider(keychain: keychain)

        let first = try provider.authToken(audience: "wss://relay.example")
        // The corrupt record was purged once and a fresh identity persisted.
        #expect(keychain.deleteCallCount == 1)
        #expect(keychain.storeCallCount == 1)
        #expect(Self.iss(ofJWT: first) != nil)

        // A subsequent launch reads the freshly-persisted key: stable client_id,
        // no further purge or re-store.
        let second = try provider.authToken(audience: "wss://relay.example")
        #expect(keychain.deleteCallCount == 1)
        #expect(keychain.storeCallCount == 1)
        #expect(Self.iss(ofJWT: first) == Self.iss(ofJWT: second))
    }
    // MARK: - #3 isCanonicalV2 enforcement for externally-scanned URIs

    @Test("External scanned URI rejects a truncated symmetric key")
    func externalURIRejectsShortKey() {
        let shortKey = "wc:topic@2?relay-protocol=irn&symKey=abcd&expiryTimestamp=1800000000"
        #expect(WalletConnectURI(externalScannedString: shortKey) == nil)
        // The permissive parser still accepts it for test fixtures.
        #expect(WalletConnectURI(absoluteString: shortKey) != nil)
    }

    @Test("External scanned URI accepts a canonical 32-byte key")
    func externalURIAcceptsCanonicalKey() throws {
        let key = String(repeating: "a", count: 64)
        let uri = "wc:\(String(repeating: "b", count: 64))@2?relay-protocol=irn&symKey=\(key)&expiryTimestamp=1800000000"
        let parsed = try #require(WalletConnectURI(externalScannedString: uri))
        #expect(parsed.isCanonicalV2)
    }

    // MARK: - #4 EVM address / hex validation

    @Test("eth_sendTransaction rejects a malformed from address")
    func rejectsBadFromAddress() {
        let request = WalletRequest(
            id: "r",
            chain: WalletBlockchain(namespace: "eip155", reference: "1"),
            method: .ethSendTransaction,
            params: [.object([
                "from": .string("0x123"), // too short
                "to": .string("0x742d35Cc6634C0532925a3b844Bc454e4438f44e"),
                "value": .string("0x0"),
                "data": .string("0x"),
                "chainId": .string("0x1"),
            ])]
        )
        #expect(throws: WalletConnectionError.self) {
            try WalletRequestValidation.validate(request)
        }
    }

    @Test("eth_sendTransaction accepts valid addresses and hex data")
    func acceptsValidTransaction() throws {
        let request = WalletRequest(
            id: "r",
            chain: WalletBlockchain(namespace: "eip155", reference: "1"),
            method: .ethSendTransaction,
            params: [.object([
                "from": .string("0x742d35Cc6634C0532925a3b844Bc454e4438f44e"),
                "to": .string("0x742d35Cc6634C0532925a3b844Bc454e4438f44e"),
                "value": .string("0x0"),
                "data": .string("0xabcd"),
                "chainId": .string("0x1"),
            ])]
        )
        try WalletRequestValidation.validate(request)
    }

    // MARK: - #2 ownership verifier

    private struct StubCryptoProvider: WalletConnectorCryptoProvider {
        let publicKey: Data
        func recoverPublicKey(signature: WalletEthereumSignature, message: Data) throws -> Data { publicKey }
        func keccak256(_ data: Data) -> Data { EthereumKeccak256.hash(data) }
    }

    // MARK: - Relay-auth JWT iat backdating

    @Test("Relay auth JWT backdates iat to tolerate clock skew")
    func relayAuthJWTBackdatesIssuedAt() throws {
        let issuedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let token = try WalletConnectRelayAuth.createToken(
            privateKey: Curve25519.Signing.PrivateKey(),
            audience: "wss://relay.example",
            issuedAt: issuedAt
        )
        let claims = try #require(Self.claims(ofJWT: token))
        let iat = try #require(claims["iat"] as? UInt64)
        let exp = try #require(claims["exp"] as? UInt64)
        #expect(claims["act"] as? String == "client_auth")
        // iat is strictly before issuedAt (backdated) and exp is issuedAt + ttl.
        #expect(iat < UInt64(issuedAt.timeIntervalSince1970))
        #expect(exp == UInt64(issuedAt.timeIntervalSince1970) + 86_400)
    }

    // MARK: - Persisted session ownership-flag back-compat

    @Test("Persisted session defaults addressVerified to false for legacy records")
    func persistedSessionOwnershipFlagBackCompat() throws {
        // A record written before ownership tracking existed has no
        // `addressVerified` key; it must decode as unverified, never trusted.
        let legacyJSON = """
        {
          "sessionTopic": "t", "pairingTopic": "p",
          "sessionSymmetricKeyHex": "ab", "providerID": "mock",
          "providerName": "Mock", "accounts": [], "namespaces": [],
          "connectedAt": 0, "expiryDate": 1800000000
        }
        """
        let decoded = try JSONDecoder().decode(WalletConnectPersistedSession.self, from: Data(legacyJSON.utf8))
        #expect(decoded.requiredNamespaces == nil)
        #expect(decoded.allowedChains == nil)
        #expect(decoded.addressVerified == nil)
        #expect(decoded.walletSession.addressVerified == false)

        // A verified record round-trips true and preserves restore chain constraints.
        let verified = WalletConnectPersistedSession(
            sessionTopic: "t", pairingTopic: "p", sessionSymmetricKeyHex: "ab",
            selfPrivateKeyHex: nil, providerID: "mock", providerName: "Mock",
            accounts: [], namespaces: [], requiredNamespaces: nil,
            allowedChains: ["eip155:1"], connectedAt: Date(timeIntervalSince1970: 0),
            expiryDate: Date(timeIntervalSince1970: 1_800_000_000), addressVerified: true
        )
        let roundTripped = try JSONDecoder().decode(
            WalletConnectPersistedSession.self,
            from: JSONEncoder().encode(verified)
        )
        #expect(roundTripped.allowedChains == ["eip155:1"])
        #expect(roundTripped.addressVerified == true)
        #expect(roundTripped.walletSession.addressVerified == true)
    }

    // MARK: - verifyOwnership protocol default (fail-closed)

    /// A connector that implements only the required surface and inherits the
    /// protocol's default `verifyOwnership`.
    private struct BareConnector: WalletConnector {
        var events: AsyncStream<WalletConnectorEvent> { AsyncStream { $0.finish() } }
        func connect(proposal: WalletNamespaceProposalSet, wallet: ThirdPartyWalletProvider?) async throws -> WalletConnectionStart {
            WalletConnectionStart(pairingURI: nil, qrPayload: "")
        }
        func handleCallback(url: URL) async throws {}
        func sessions() async throws -> [WalletConnectorSession] { [] }
        func disconnect(sessionId: WalletSessionID) async throws {}
        func request(_ request: WalletRequest, in sessionId: WalletSessionID) async throws -> WalletResponse {
            WalletResponse(id: request.id, result: "")
        }
    }

    @Test("verifyOwnership fails closed on a connector that does not implement it")
    func verifyOwnershipFailsClosedByDefault() async {
        let connector = BareConnector()
        await #expect(throws: WalletConnectionError.self) {
            _ = try await connector.verifyOwnership(of: "0xabc", in: WalletSessionID(rawValue: "s"))
        }
    }

    @Test("Ownership verifier recovers the expected EVM address")
    func ownershipVerifierMatchesAddress() throws {
        let pubKey = Data((0..<64).map { UInt8($0) })
        let provider = StubCryptoProvider(publicKey: pubKey)
        let expected = "0x" + EthereumKeccak256.hash(pubKey).suffix(20).map { String(format: "%02x", $0) }.joined()
        let signature = WalletEthereumSignature(v: 27, r: [], s: [])

        #expect(try WalletOwnershipVerifier.verifyPersonalSign(
            expectedAddress: expected.uppercased(),
            message: Data("hello".utf8),
            signature: signature,
            using: provider
        ))
        #expect(try !WalletOwnershipVerifier.verifyPersonalSign(
            expectedAddress: "0x0000000000000000000000000000000000000000",
            message: Data("hello".utf8),
            signature: signature,
            using: provider
        ))
    }
}
