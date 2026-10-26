import CryptoKit
import Foundation
import Testing
@testable import WalletConnectorKit

/// Covers the multi-chain ownership additions: Solana ed25519 verification,
/// base58 decoding, and recovery-id-agnostic EVM `personal_sign` verification.
@Suite("Multi-chain ownership verification")
struct WalletMultiChainOwnershipTests {

    // MARK: - Solana (ed25519)

    @Test("Solana ownership verifier accepts a valid ed25519 signature and rejects tampering")
    func solanaOwnershipVerification() throws {
        let key = Curve25519.Signing.PrivateKey()
        let address = WalletConnectBase58.encode(key.publicKey.rawRepresentation)
        let message = Data("verify wallet ownership".utf8)
        let signature = try key.signature(for: message)

        #expect(WalletSolanaOwnershipVerifier.verifySignature(address: address, message: message, signature: signature))
        // A different message must not verify against the same signature.
        #expect(!WalletSolanaOwnershipVerifier.verifySignature(address: address, message: Data("other".utf8), signature: signature))
        // A different account (public key) must not verify.
        let otherAddress = WalletConnectBase58.encode(Curve25519.Signing.PrivateKey().publicKey.rawRepresentation)
        #expect(!WalletSolanaOwnershipVerifier.verifySignature(address: otherAddress, message: message, signature: signature))
        // A malformed (non-64-byte) signature is rejected.
        #expect(!WalletSolanaOwnershipVerifier.verifySignature(address: address, message: message, signature: Data(repeating: 0, count: 10)))
    }

    @Test("Solana signature parses base58, base64, and object response shapes")
    func solanaSignatureParsing() throws {
        let raw = Data((0..<64).map { UInt8(truncatingIfNeeded: $0 &* 3 &+ 1) })
        let base58 = WalletConnectBase58.encode(raw)
        let base64 = raw.base64EncodedString()

        #expect(WalletSolanaOwnershipVerifier.signature(fromResponse: base58) == raw)
        #expect(WalletSolanaOwnershipVerifier.signature(fromResponse: base64) == raw)
        #expect(WalletSolanaOwnershipVerifier.signature(fromResponse: "{\"signature\":\"\(base58)\"}") == raw)
        #expect(WalletSolanaOwnershipVerifier.signature(fromResponse: "not-a-signature") == nil)
    }

    @Test("verifyChallenge issues a solana_signMessage challenge and verifies the ed25519 response")
    func solanaVerifyChallenge() async throws {
        let key = Curve25519.Signing.PrivateKey()
        let address = WalletConnectBase58.encode(key.publicKey.rawRepresentation)

        // A cooperative wallet decodes the base58 `message` param and signs those
        // bytes — exactly what the verifier checks.
        let verified = try await WalletSolanaOwnershipVerifier.verifyChallenge(
            address: address,
            challengeText: "prove ownership nonce=abc123",
            expiryDate: Date().addingTimeInterval(300),
            send: { request in
                let messageParam = request.params.first?.stringValue ?? ""
                let messageBytes = WalletConnectBase58.decode(messageParam) ?? Data()
                let signature = try key.signature(for: messageBytes)
                return WalletResponse(id: request.id, result: WalletConnectBase58.encode(signature))
            }
        )
        #expect(verified)

        // A wallet that signs different bytes fails verification.
        let tampered = try await WalletSolanaOwnershipVerifier.verifyChallenge(
            address: address,
            challengeText: "prove ownership nonce=abc123",
            expiryDate: Date().addingTimeInterval(300),
            send: { request in
                let signature = try key.signature(for: Data("tampered".utf8))
                return WalletResponse(id: request.id, result: WalletConnectBase58.encode(signature))
            }
        )
        #expect(!tampered)
    }

    // MARK: - Base58 decode

    @Test("Base58 decode round-trips encode, including leading zeros")
    func base58DecodeRoundTrips() {
        let samples: [Data] = [
            Data([0]),
            Data([0, 0, 1, 2, 3]),
            Data((0..<40).map { UInt8($0) }),
            Data("hello world".utf8),
        ]
        for data in samples {
            #expect(WalletConnectBase58.decode(WalletConnectBase58.encode(data)) == data)
        }
        #expect(WalletConnectBase58.decode("") == Data())
        // Characters outside the Bitcoin alphabet are rejected.
        #expect(WalletConnectBase58.decode("0") == nil)
        #expect(WalletConnectBase58.decode("O") == nil)
        #expect(WalletConnectBase58.decode("l") == nil)
    }

    // MARK: - EVM recovery-id agnostic verification

    @Test("verifyPersonalSign is agnostic to the provider's recovery-id convention")
    func verifyPersonalSignRecoveryIDAgnostic() throws {
        let publicKey = Data((0..<64).map { UInt8(truncatingIfNeeded: $0 &* 7 &+ 5) })
        let expected = Self.evmAddress(for: publicKey)
        let message = Data("sign in".utf8)

        // Provider that only recovers under the 0/1 convention, and one under 27/28.
        let zeroOneProvider = RecoveryIDStubProvider(publicKey: publicKey, acceptedVs: [0, 1])
        let legacyProvider = RecoveryIDStubProvider(publicKey: publicKey, acceptedVs: [27, 28])

        // `WalletEthereumSignature` stores v as 27/28; verification must still
        // succeed against a provider expecting 0/1 (and vice-versa).
        let signature = WalletEthereumSignature(v: 28, r: Array(repeating: 1, count: 32), s: Array(repeating: 2, count: 32))
        #expect(try WalletOwnershipVerifier.verifyPersonalSign(expectedAddress: expected, message: message, signature: signature, using: zeroOneProvider))
        #expect(try WalletOwnershipVerifier.verifyPersonalSign(expectedAddress: expected, message: message, signature: signature, using: legacyProvider))

        // A mismatched address returns false (not throw) since recovery succeeded.
        let wrongAddress = "0x" + String(repeating: "0", count: 40)
        #expect(try WalletOwnershipVerifier.verifyPersonalSign(expectedAddress: wrongAddress, message: message, signature: signature, using: zeroOneProvider) == false)
    }

    @Test("verifyPersonalSign rethrows when no provider can recover")
    func verifyPersonalSignRethrowsWithoutRecovery() {
        let provider = DefaultWalletConnectorCryptoProvider()
        let signature = WalletEthereumSignature(v: 27, r: Array(repeating: 1, count: 32), s: Array(repeating: 2, count: 32))
        #expect(throws: WalletConnectionError.self) {
            _ = try WalletOwnershipVerifier.verifyPersonalSign(
                expectedAddress: "0x" + String(repeating: "0", count: 40),
                message: Data("x".utf8),
                signature: signature,
                using: provider
            )
        }
    }

    // MARK: - EIP-1271 smart-contract-wallet ownership (async overload)

    @Test("async verifyPersonalSign verifies an EOA signature via recovery")
    func asyncVerifyPersonalSignEOA() async throws {
        let publicKey = Data((0..<64).map { UInt8(truncatingIfNeeded: $0 &* 7 &+ 5) })
        let expected = Self.evmAddress(for: publicKey)
        let provider = RecoveryIDStubProvider(publicKey: publicKey, acceptedVs: [27, 28])
        let signatureHex = "0x" + String(repeating: "01", count: 32) + String(repeating: "02", count: 32) + "1b"
        let verified = try await WalletOwnershipVerifier.verifyPersonalSign(
            expectedAddress: expected,
            message: Data("sign in".utf8),
            signatureHex: signatureHex,
            chain: .ethereum,
            using: provider
        )
        #expect(verified)
    }

    @Test("async verifyPersonalSign falls back to EIP-1271 for a smart-contract wallet")
    func asyncVerifyPersonalSignERC1271() async throws {
        let address = "0x" + String(repeating: "ab", count: 20)
        let message = Data("prove ownership".utf8)
        // A contract-wallet signature is arbitrary-length (not the 65-byte EOA
        // layout), so EOA parsing fails and the on-chain validator is consulted.
        let contractSignature = Data((0..<80).map { UInt8(truncatingIfNeeded: $0) })
        let contractSignatureHex = "0x" + contractSignature.map { String(format: "%02x", $0) }.joined()
        let provider = SmartContractStubProvider(
            expectedAddress: address,
            expectedMessage: message,
            expectedSignature: contractSignature
        )
        let verified = try await WalletOwnershipVerifier.verifyPersonalSign(
            expectedAddress: address,
            message: message,
            signatureHex: contractSignatureHex,
            chain: .base,
            using: provider
        )
        #expect(verified)

        // A different message must not validate (the on-chain call is bound to it).
        let mismatched = try await WalletOwnershipVerifier.verifyPersonalSign(
            expectedAddress: address,
            message: Data("other".utf8),
            signatureHex: contractSignatureHex,
            chain: .base,
            using: provider
        )
        #expect(!mismatched)
    }

    @Test("async verifyPersonalSign without smart-contract support fails a non-EOA signature closed")
    func asyncVerifyPersonalSignNoSmartContractSupport() async {
        // A non-65-byte signature and an EOA-only provider: unusable for EOA
        // verification, so it fails closed with invalidResponse (unchanged behavior).
        let provider = RecoveryIDStubProvider(publicKey: Data(repeating: 9, count: 64), acceptedVs: [27])
        await #expect(throws: WalletConnectionError.invalidResponse) {
            _ = try await WalletOwnershipVerifier.verifyPersonalSign(
                expectedAddress: "0x" + String(repeating: "0", count: 40),
                message: Data("x".utf8),
                signatureHex: "0xabcdef",
                chain: .ethereum,
                using: provider
            )
        }
    }

    @Test("a provider that advertises smart-contract support but omits the impl fails loud")
    func smartContractDefaultImplementationThrows() async {
        let provider = MisconfiguredSmartContractProvider()
        await #expect(throws: WalletConnectionError.self) {
            _ = try await WalletOwnershipVerifier.verifyPersonalSign(
                expectedAddress: "0x" + String(repeating: "0", count: 40),
                message: Data("x".utf8),
                signatureHex: "0x" + String(repeating: "00", count: 40),
                chain: .ethereum,
                using: provider
            )
        }
    }

    private static func evmAddress(for publicKey: Data) -> String {
        let hashed = EthereumKeccak256.hash(publicKey)
        return "0x" + hashed.suffix(20).map { String(format: "%02x", $0) }.joined()
    }
}

/// A crypto provider that only "recovers" the configured public key when the
/// signature's `v` is in `acceptedVs`, modeling a real secp256k1 library that
/// expects one specific recovery-id convention.
private struct RecoveryIDStubProvider: WalletConnectorCryptoProvider {
    let publicKey: Data
    let acceptedVs: Set<UInt8>

    func recoverPublicKey(signature: WalletEthereumSignature, message: Data) throws -> Data {
        guard acceptedVs.contains(signature.v) else {
            throw WalletConnectionError.cryptographyFailure
        }
        return publicKey
    }

    func keccak256(_ data: Data) -> Data {
        EthereumKeccak256.hash(data)
    }
}

/// A provider that cannot recover an EOA key but validates a specific EIP-1271
/// signature on-chain, modeling a real RPC-backed smart-contract-wallet verifier.
private struct SmartContractStubProvider: WalletConnectorCryptoProvider {
    let expectedAddress: String
    let expectedMessage: Data
    let expectedSignature: Data

    var supportsSmartContractOwnership: Bool { true }

    func recoverPublicKey(signature: WalletEthereumSignature, message: Data) throws -> Data {
        throw WalletConnectionError.unavailable("no EOA recovery")
    }

    func keccak256(_ data: Data) -> Data {
        EthereumKeccak256.hash(data)
    }

    func isValidERC1271Signature(address: String, message: Data, signature: Data, chain: WalletChain) async throws -> Bool {
        address.caseInsensitiveCompare(expectedAddress) == .orderedSame
            && message == expectedMessage
            && signature == expectedSignature
    }
}

/// Advertises smart-contract support but relies on the protocol's default
/// `isValidERC1271Signature`, which throws — proving a misconfigured provider
/// fails loud instead of silently reporting a contract wallet as unowned.
private struct MisconfiguredSmartContractProvider: WalletConnectorCryptoProvider {
    var supportsSmartContractOwnership: Bool { true }

    func recoverPublicKey(signature: WalletEthereumSignature, message: Data) throws -> Data {
        throw WalletConnectionError.unavailable("no EOA recovery")
    }

    func keccak256(_ data: Data) -> Data {
        EthereumKeccak256.hash(data)
    }
}
