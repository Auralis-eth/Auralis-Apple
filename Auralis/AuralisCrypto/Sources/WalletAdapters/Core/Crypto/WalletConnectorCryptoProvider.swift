import CryptoKit
import Foundation
import Security

public struct WalletEthereumSignature: Hashable, Sendable {
    public let v: UInt8
    public let r: [UInt8]
    public let s: [UInt8]

    public init(v: UInt8, r: [UInt8], s: [UInt8]) {
        self.v = v
        self.r = r
        self.s = s
    }
}

public protocol WalletConnectorCryptoProvider: Sendable {
    /// Recovers the signer's public key from `signature` over `message`.
    ///
    /// - Important: `message` is the **already-hashed 32-byte digest** the caller
    ///   passes in (e.g. `WalletOwnershipVerifier` passes the EIP-191
    ///   `personalSignDigest`). The provider must run raw secp256k1 recovery over
    ///   these 32 bytes and must **not** re-apply the
    ///   `\u{19}Ethereum Signed Message` prefix or re-hash — doing so recovers the
    ///   wrong key and ownership verification will silently fail to match. Return
    ///   the uncompressed public key: 64 bytes (X ‖ Y) or the 65-byte SEC1 form
    ///   with a leading `0x04`.
    func recoverPublicKey(signature: WalletEthereumSignature, message: Data) throws -> Data
    func keccak256(_ data: Data) -> Data

    /// Whether this provider can actually perform secp256k1 public-key recovery.
    ///
    /// Defaults to `false` so a provider that has not implemented recovery (e.g.
    /// `DefaultWalletConnectorCryptoProvider`) is treated as *incapable* of EVM
    /// ownership verification. A real recovery-backed provider (e.g. the Auralis
    /// web3.swift provider) must override this to `true`. Connectors read it to
    /// decide whether they can advertise production-ready EVM ownership proofs
    /// instead of silently failing closed at verification time.
    var supportsRecovery: Bool { get }

    /// Whether this provider can validate **EIP-1271** smart-contract-wallet
    /// signatures (Safe, Coinbase Smart Wallet, most ERC-4337 accounts).
    ///
    /// A smart-contract account has no recoverable EOA private key — it validates
    /// signatures on-chain via `isValidSignature(bytes32,bytes)`, so `ecrecover`
    /// can never match its address and EOA-only ownership verification silently
    /// returns `false`. Defaults to `false`; a provider with RPC access overrides
    /// it to `true` and implements `isValidERC1271Signature`. `WalletOwnershipVerifier`
    /// reads it to decide whether to attempt the on-chain fallback after EOA
    /// recovery fails, instead of rejecting a legitimate contract wallet.
    var supportsSmartContractOwnership: Bool { get }

    /// Validates an **EIP-1271** signature for the smart-contract account
    /// `address` on `chain`. Called by `WalletOwnershipVerifier` only when
    /// `supportsSmartContractOwnership == true` and EOA recovery did not match.
    ///
    /// - Parameter message: the **raw** personal-sign message bytes (not the
    ///   digest). The provider applies whatever EIP-191 prefixing / hashing its
    ///   `isValidSignature` call expects and performs the on-chain `eth_call`.
    /// - Parameter signature: the raw signature bytes the wallet returned (an
    ///   EIP-1271 signature is arbitrary-length, not the 65-byte EOA layout).
    ///
    /// The default throws `WalletConnectionError.unavailable`, so a provider that
    /// advertises `supportsSmartContractOwnership` but forgets to implement this
    /// fails loud rather than silently reporting a contract wallet as unowned.
    func isValidERC1271Signature(address: String, message: Data, signature: Data, chain: WalletChain) async throws -> Bool
}

public extension WalletConnectorCryptoProvider {
    var supportsRecovery: Bool { false }
    var supportsSmartContractOwnership: Bool { false }

    func isValidERC1271Signature(address: String, message: Data, signature: Data, chain: WalletChain) async throws -> Bool {
        throw WalletConnectionError.unavailable(
            "EIP-1271 smart-contract signature validation is not configured. Inject a WalletConnectorCryptoProvider with supportsSmartContractOwnership == true (RPC-backed) to verify smart-contract wallets, or use WalletConnectionLifecycleService(ownershipPolicy: .allowUnverified) for intentionally non-sensitive flows."
        )
    }
}

/// Default crypto provider.
///
/// - `keccak256` is fully implemented (audited against the standard Ethereum
///   Keccak-256 test vectors in `WalletCryptoProviderTests`).
/// - `recoverPublicKey` is intentionally **not** implemented: SIWE / auth
///   signature verification requires secp256k1 public-key recovery, which this
///   package does not vend. Inject a `WalletConnectorCryptoProvider` backed by a
///   real secp256k1 implementation before enabling those flows; until then any
///   recovery call throws `WalletConnectionError.unavailable` with guidance
///   rather than failing silently.
public struct DefaultWalletConnectorCryptoProvider: WalletConnectorCryptoProvider {
    public init() {}

    public func recoverPublicKey(signature: WalletEthereumSignature, message: Data) throws -> Data {
        throw WalletConnectionError.unavailable(
            "Ethereum public key recovery is not configured. Inject a WalletConnectorCryptoProvider that supports recovery before enabling SIWE or auth verification."
        )
    }

    public func keccak256(_ data: Data) -> Data {
        EthereumKeccak256.hash(data)
    }
}

public enum WalletOwnershipChallengeMessageBuilder {
    public static func evmSIWEMessage(
        address: String,
        chain: WalletChain,
        statement: String,
        nonce: String,
        issuedAt: Date,
        expiration: Date,
        metadata: WalletConnectionMetadata
    ) -> String {
        """
        \(domain(for: metadata)) wants you to sign in with your Ethereum account:
        \(address)

        \(statement)

        URI: \(metadata.appURL.absoluteString)
        Version: 1
        Chain ID: \(chain.chainReference)
        Nonce: \(nonce)
        Issued At: \(iso8601String(from: issuedAt))
        Expiration Time: \(iso8601String(from: expiration))
        """
    }

    public static func solanaMessage(
        address: String,
        statement: String,
        nonce: String,
        issuedAt: Date,
        expiration: Date,
        metadata: WalletConnectionMetadata
    ) -> String {
        """
        \(domain(for: metadata)) wants you to verify ownership of your Solana account:
        \(address)

        \(statement)

        URI: \(metadata.appURL.absoluteString)
        Version: 1
        Chain: solana
        Nonce: \(nonce)
        Issued At: \(iso8601String(from: issuedAt))
        Expiration Time: \(iso8601String(from: expiration))
        """
    }

    public static func nonce() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw WalletConnectionError.cryptographyFailure
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func domain(for metadata: WalletConnectionMetadata) -> String {
        var domain = metadata.appURL.host ?? metadata.appURL.absoluteString
        if let port = metadata.appURL.port {
            domain += ":\(port)"
        }
        return domain
    }

    private static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

/// Verifies wallet ownership from a `personal_sign` (EIP-191) signature.
///
/// Connecting a wallet only proves the wallet *claims* an address — it does not
/// prove the user controls the private key. To establish ownership, issue a
/// `personal_sign` challenge (e.g. a SIWE message) and verify the returned
/// signature recovers the expected address. Recovery requires secp256k1, which
/// this package does not vend: inject a `WalletConnectorCryptoProvider` whose
/// `recoverPublicKey` returns the 64-byte uncompressed public key (no `0x04`
/// prefix). The Auralis app supplies one backed by web3.swift.
public enum WalletOwnershipVerifier {
    /// EIP-191 "personal sign" digest: `keccak256("\u{19}Ethereum Signed Message:\n" + len + message)`.
    public static func personalSignDigest(message: Data) -> Data {
        var prefixed = Data("\u{19}Ethereum Signed Message:\n\(message.count)".utf8)
        prefixed.append(message)
        return EthereumKeccak256.hash(prefixed)
    }

    /// Returns `true` when `signature` over `message` recovers `expectedAddress`
    /// (case-insensitive EVM comparison).
    ///
    /// The recovery id (`v`) convention varies by secp256k1 implementation — some
    /// expect `0/1`, others the legacy `27/28`. Rather than depend on the injected
    /// provider agreeing with our encoding (a mismatch would silently recover the
    /// wrong key and report a false negative), we try both conventions for the
    /// signature's parity and accept if either recovers the expected address. If
    /// **every** recovery attempt throws (e.g. no recovery-capable provider was
    /// injected), the error is rethrown so the caller fails loud rather than
    /// silently returning `false`.
    public static func verifyPersonalSign(
        expectedAddress: String,
        message: Data,
        signature: WalletEthereumSignature,
        using provider: any WalletConnectorCryptoProvider
    ) throws -> Bool {
        let digest = personalSignDigest(message: message)
        var anyRecovered = false
        var lastError: Error?
        for candidate in candidateSignatures(for: signature) {
            do {
                let recoveredKey = try provider.recoverPublicKey(signature: candidate, message: digest)
                anyRecovered = true
                if addressMatches(recoveredKey, expectedAddress: expectedAddress, using: provider) {
                    return true
                }
            } catch {
                lastError = error
            }
        }
        if !anyRecovered, let lastError {
            throw lastError
        }
        return false
    }

    /// Verifies a `personal_sign` challenge response that may come from **either**
    /// an EOA **or** an EIP-1271 smart-contract wallet.
    ///
    /// Order of attempts:
    /// 1. **EOA:** if `signatureHex` parses as a 65-byte `r ‖ s ‖ v` signature, run
    ///    secp256k1 recovery (the existing EOA path). A match returns `true`.
    /// 2. **EIP-1271:** if recovery does not match (or the response is not
    ///    EOA-shaped) and the provider advertises `supportsSmartContractOwnership`,
    ///    validate the raw signature on-chain via `isValidERC1271Signature`. This
    ///    is how Safe / Coinbase Smart Wallet / ERC-4337 accounts prove ownership —
    ///    they have no recoverable key, so EOA-only verification would reject them.
    ///
    /// Fail-closed semantics are preserved: with no recovery-capable provider the
    /// EOA path rethrows (loud); an EOA wallet returning a malformed signature and
    /// no contract-validation support throws `.invalidResponse` (unchanged); and a
    /// contract wallet with no injected validator surfaces the provider's
    /// `.unavailable` guidance rather than a silent `false`.
    public static func verifyPersonalSign(
        expectedAddress: String,
        message: Data,
        signatureHex: String,
        chain: WalletChain,
        using provider: any WalletConnectorCryptoProvider
    ) async throws -> Bool {
        if let eoaSignature = WalletEthereumSignature(hexSignature: signatureHex) {
            do {
                if try verifyPersonalSign(expectedAddress: expectedAddress, message: message, signature: eoaSignature, using: provider) {
                    return true
                }
                // Recovery succeeded but did not match the claimed address — fall
                // through to the EIP-1271 attempt below (it may be a contract wallet
                // that happens to return an EOA-shaped signature).
            } catch {
                // No candidate could be recovered (e.g. the provider lacks secp256k1
                // recovery). Only fall through to EIP-1271 if the provider can do it;
                // otherwise rethrow so the caller still fails loud.
                guard provider.supportsSmartContractOwnership else { throw error }
            }
        } else if !provider.supportsSmartContractOwnership {
            // Not an EOA-shaped signature and no contract validator available: the
            // response is unusable for EOA verification (preserves prior behavior).
            throw WalletConnectionError.invalidResponse
        }

        guard provider.supportsSmartContractOwnership else { return false }

        guard let signatureBytes = WalletConnectV2Crypto.data(hexEncoded: strippingHexPrefix(signatureHex)) else {
            return false
        }
        return try await provider.isValidERC1271Signature(
            address: expectedAddress,
            message: message,
            signature: signatureBytes,
            chain: chain
        )
    }

    private static func strippingHexPrefix(_ hex: String) -> String {
        if hex.hasPrefix("0x") || hex.hasPrefix("0X") {
            return String(hex.dropFirst(2))
        }
        return hex
    }

    /// The signature under both recovery-id conventions (`27/28` and `0/1`) for its
    /// parity, so verification is agnostic to what the injected provider expects.
    private static func candidateSignatures(for signature: WalletEthereumSignature) -> [WalletEthereumSignature] {
        // Normalize to a 0/1 parity, then present both encodings. Dedupe so an
        // already-0/1 (or out-of-range) `v` does not produce redundant attempts.
        let parity: UInt8
        switch signature.v {
        case 27, 28: parity = signature.v - 27
        case 0, 1: parity = signature.v
        default: parity = signature.v & 1
        }
        let candidateVs = [27 + parity, parity]
        var seen = Set<UInt8>()
        return candidateVs.compactMap { value in
            guard seen.insert(value).inserted else { return nil }
            return WalletEthereumSignature(v: value, r: signature.r, s: signature.s)
        }
    }

    /// Whether `recoveredKey` (64-byte `X ‖ Y`, or 65-byte SEC1 with a leading
    /// `0x04`) derives to `expectedAddress`. Any other length is rejected so a
    /// malformed key can never hash to a coincidental match.
    private static func addressMatches(
        _ recoveredKey: Data,
        expectedAddress: String,
        using provider: any WalletConnectorCryptoProvider
    ) -> Bool {
        let publicKey: Data
        if recoveredKey.count == 65, recoveredKey.first == 0x04 {
            publicKey = recoveredKey.dropFirst()
        } else if recoveredKey.count == 64 {
            publicKey = recoveredKey
        } else {
            return false
        }
        // Address = last 20 bytes of keccak256(publicKey).
        let hashed = provider.keccak256(publicKey)
        guard hashed.count >= 20 else { return false }
        let recovered = "0x" + hashed.suffix(20).map { String(format: "%02x", $0) }.joined()
        return recovered.caseInsensitiveCompare(expectedAddress) == .orderedSame
    }
}

/// Verifies Solana wallet ownership from an ed25519 `solana_signMessage`
/// signature. Unlike EVM (which needs secp256k1 recovery from an injected
/// provider), a Solana account address **is** its ed25519 public key, so this is
/// fully self-contained via CryptoKit — no external dependency and no crypto
/// provider required.
public enum WalletSolanaOwnershipVerifier {
    /// Returns `true` when `signature` (64 raw bytes) is a valid ed25519 signature
    /// over `message` for the account whose base58 `address` is its public key.
    public static func verifySignature(address: String, message: Data, signature: Data) -> Bool {
        guard signature.count == 64,
              let publicKeyData = WalletConnectBase58.decode(address),
              publicKeyData.count == 32,
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData) else {
            return false
        }
        return publicKey.isValidSignature(signature, for: message)
    }

    /// Parses a wallet's `solana_signMessage` response into the 64-byte signature.
    /// Tolerates the common shapes: a bare base58/base64 string, or an object with
    /// a `signature` field carrying the same.
    public static func signature(fromResponse result: String) -> Data? {
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        // Object form: {"signature":"…"} (optionally alongside other fields).
        if let data = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let value = object["signature"] as? String {
            return decodeSignature(value)
        }
        // Bare string form (possibly JSON-quoted).
        let unquoted = trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"") && trimmed.count >= 2
            ? String(trimmed.dropFirst().dropLast())
            : trimmed
        return decodeSignature(unquoted)
    }

    private static func decodeSignature(_ value: String) -> Data? {
        if let base58 = WalletConnectBase58.decode(value), base58.count == 64 {
            return base58
        }
        if let base64 = Data(base64Encoded: value), base64.count == 64 {
            return base64
        }
        return nil
    }

    /// Issues a `solana_signMessage` ownership challenge for `challengeText` via
    /// `send` and verifies the returned ed25519 signature. The challenge is
    /// base58-encoded on the wire (the `solana_signMessage` convention); the wallet
    /// signs the decoded bytes, which is exactly what we verify against. Shared by
    /// every connector so Solana ownership is verified identically everywhere.
    public static func verifyChallenge(
        address: String,
        challengeText: String,
        expiryDate: Date,
        send: @Sendable (WalletRequest) async throws -> WalletResponse
    ) async throws -> Bool {
        let challengeBytes = Data(challengeText.utf8)
        let request = WalletRequestBuilder.solanaSignMessage(
            id: WalletSignRequestID(rawValue: "ownership-\(UUID().uuidString)"),
            address: address,
            message: WalletConnectBase58.encode(challengeBytes),
            expiryDate: expiryDate
        )
        let response = try await send(request)
        guard let signature = signature(fromResponse: response.result) else {
            throw WalletConnectionError.invalidResponse
        }
        return verifySignature(address: address, message: challengeBytes, signature: signature)
    }
}

enum EthereumKeccak256 {
    static func hash(_ data: Data) -> Data {
        var state = [UInt64](repeating: 0, count: 25)
        let rate = 136
        var offset = 0
        let bytes = [UInt8](data)

        while offset + rate <= bytes.count {
            absorb(Array(bytes[offset..<(offset + rate)]), into: &state)
            keccakF1600(&state)
            offset += rate
        }

        var block = [UInt8](repeating: 0, count: rate)
        let remainder = bytes.count - offset
        if remainder > 0 {
            block.replaceSubrange(0..<remainder, with: bytes[offset...])
        }
        block[remainder] ^= 0x01
        block[rate - 1] ^= 0x80
        absorb(block, into: &state)
        keccakF1600(&state)

        var output = Data(capacity: 32)
        for lane in state {
            var littleEndian = lane.littleEndian
            withUnsafeBytes(of: &littleEndian) { output.append(contentsOf: $0) }
            if output.count >= 32 { break }
        }
        return output.prefix(32)
    }

    private static func absorb(_ block: [UInt8], into state: inout [UInt64]) {
        for laneIndex in 0..<(block.count / 8) {
            var lane: UInt64 = 0
            for byteIndex in 0..<8 {
                lane |= UInt64(block[laneIndex * 8 + byteIndex]) << UInt64(8 * byteIndex)
            }
            state[laneIndex] ^= lane
        }
    }

    private static func keccakF1600(_ state: inout [UInt64]) {
        let rotationOffsets = [
            0, 1, 62, 28, 27,
            36, 44, 6, 55, 20,
            3, 10, 43, 25, 39,
            41, 45, 15, 21, 8,
            18, 2, 61, 56, 14,
        ]
        let roundConstants: [UInt64] = [
            0x0000000000000001, 0x0000000000008082,
            0x800000000000808a, 0x8000000080008000,
            0x000000000000808b, 0x0000000080000001,
            0x8000000080008081, 0x8000000000008009,
            0x000000000000008a, 0x0000000000000088,
            0x0000000080008009, 0x000000008000000a,
            0x000000008000808b, 0x800000000000008b,
            0x8000000000008089, 0x8000000000008003,
            0x8000000000008002, 0x8000000000000080,
            0x000000000000800a, 0x800000008000000a,
            0x8000000080008081, 0x8000000000008080,
            0x0000000080000001, 0x8000000080008008,
        ]

        for roundConstant in roundConstants {
            var columnParity = [UInt64](repeating: 0, count: 5)
            for x in 0..<5 {
                columnParity[x] = state[x] ^ state[x + 5] ^ state[x + 10] ^ state[x + 15] ^ state[x + 20]
            }

            var theta = [UInt64](repeating: 0, count: 5)
            for x in 0..<5 {
                theta[x] = columnParity[(x + 4) % 5] ^ columnParity[(x + 1) % 5].rotatedLeft(by: 1)
            }
            for index in 0..<25 {
                state[index] ^= theta[index % 5]
            }

            var rotated = [UInt64](repeating: 0, count: 25)
            for x in 0..<5 {
                for y in 0..<5 {
                    let sourceIndex = x + 5 * y
                    let destinationX = y
                    let destinationY = (2 * x + 3 * y) % 5
                    rotated[destinationX + 5 * destinationY] = state[sourceIndex].rotatedLeft(by: rotationOffsets[sourceIndex])
                }
            }

            for x in 0..<5 {
                for y in 0..<5 {
                    state[x + 5 * y] = rotated[x + 5 * y] ^ ((~rotated[((x + 1) % 5) + 5 * y]) & rotated[((x + 2) % 5) + 5 * y])
                }
            }

            state[0] ^= roundConstant
        }
    }
}

private extension UInt64 {
    func rotatedLeft(by amount: Int) -> UInt64 {
        let shift = UInt64(amount % 64)
        guard shift != 0 else { return self }
        return (self << shift) | (self >> (64 - shift))
    }
}
