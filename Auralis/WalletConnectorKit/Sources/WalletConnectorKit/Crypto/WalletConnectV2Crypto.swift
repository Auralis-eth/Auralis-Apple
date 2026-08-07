import CryptoKit
import Foundation

/// Low-level WalletConnect v2 cryptographic primitives, implemented with
/// CryptoKit and kept bit-for-bit compatible with the reference implementation
/// (reown-swift `WalletConnectKMS`).
///
/// - Symmetric encryption is ChaCha20-Poly1305. The sealed box layout is
///   `nonce(12) ‖ ciphertext ‖ tag(16)` — identical to CryptoKit's
///   `ChaChaPoly.SealedBox.combined`.
/// - Shared symmetric keys are derived with X25519 ECDH followed by HKDF-SHA256
///   with an empty salt and empty shared-info, producing 32 bytes.
/// - Topics are the lowercase hex of `SHA256(symmetricKey)`.
///
/// These are internal building blocks; the transport layer composes them into
/// the pairing/session handshake.
enum WalletConnectV2Crypto {
    // MARK: - Hex helpers

    static func hexString(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    static func data(hexEncoded string: String) -> Data? {
        guard string.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(string.count / 2)
        var index = string.startIndex
        while index < string.endIndex {
            let next = string.index(index, offsetBy: 2)
            guard let byte = UInt8(string[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return Data(bytes)
    }

    // MARK: - Topic derivation

    /// Topic associated with a symmetric key: `SHA256(symKey)` as lowercase hex.
    static func topic(forSymmetricKey symKey: Data) -> String {
        hexString(Data(SHA256.hash(data: symKey)))
    }

    // MARK: - Key agreement (X25519 + HKDF-SHA256)

    struct KeyPair: Sendable {
        let privateKey: Curve25519.KeyAgreement.PrivateKey
        var publicKeyHex: String { WalletConnectV2Crypto.hexString(privateKey.publicKey.rawRepresentation) }
    }

    static func generateKeyPair() -> KeyPair {
        KeyPair(privateKey: Curve25519.KeyAgreement.PrivateKey())
    }

    /// Derives the 32-byte shared symmetric key from a local private key and the
    /// peer's X25519 public key (hex). Matches reown's `deriveSymmetricKey`.
    static func deriveSymmetricKey(privateKey: Curve25519.KeyAgreement.PrivateKey, peerPublicKeyHex: String) throws -> Data {
        guard let peerData = data(hexEncoded: peerPublicKeyHex),
              let peerKey = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerData) else {
            throw WalletConnectionError.cryptographyFailure
        }
        guard let sharedSecret = try? privateKey.sharedSecretFromKeyAgreement(with: peerKey) else {
            throw WalletConnectionError.cryptographyFailure
        }
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: Data(),
            outputByteCount: 32
        )
        return symmetricKey.withUnsafeBytes { Data($0) }
    }

    // MARK: - Symmetric seal / open

    /// Encrypts `plaintext` under `symKey` and returns the sealbox
    /// (`nonce ‖ ciphertext ‖ tag`). A caller-supplied nonce exists for test
    /// vectors only; production callers must let it default to random.
    static func seal(plaintext: Data, symKey: Data, nonce: ChaChaPoly.Nonce = ChaChaPoly.Nonce()) throws -> Data {
        let key = SymmetricKey(data: symKey)
        guard let box = try? ChaChaPoly.seal(plaintext, using: key, nonce: nonce) else {
            throw WalletConnectionError.cryptographyFailure
        }
        return box.combined
    }

    static func open(sealbox: Data, symKey: Data) throws -> Data {
        let key = SymmetricKey(data: symKey)
        guard let box = try? ChaChaPoly.SealedBox(combined: sealbox),
              let plaintext = try? ChaChaPoly.open(box, using: key) else {
            throw WalletConnectionError.cryptographyFailure
        }
        return plaintext
    }
}

/// A WalletConnect v2 typed envelope.
///
/// - type0: `0x00 ‖ sealbox` — symmetric, key already shared (base64).
/// - type1: `0x01 ‖ senderPublicKey(32) ‖ sealbox` — carries the sender's
///   X25519 public key so the peer can derive the shared key (base64).
struct WalletConnectEnvelope: Equatable {
    enum EnvelopeType: Equatable {
        case type0
        case type1(senderPublicKey: Data)

        var byte: UInt8 {
            switch self {
            case .type0: return 0
            case .type1: return 1
            }
        }
    }

    enum Errors: Error, Equatable {
        case malformed
        case unsupportedType(UInt8)
    }

    let type: EnvelopeType
    let sealbox: Data

    init(type: EnvelopeType, sealbox: Data) {
        self.type = type
        self.sealbox = sealbox
    }

    /// Parses a base64-encoded envelope.
    init(base64Encoded string: String) throws {
        guard let data = Data(base64Encoded: string), let typeByte = data.first else {
            throw Errors.malformed
        }
        switch typeByte {
        case 0:
            self.type = .type0
            self.sealbox = data.subdata(in: 1..<data.count)
        case 1:
            guard data.count >= 33 else { throw Errors.malformed }
            self.type = .type1(senderPublicKey: data.subdata(in: 1..<33))
            self.sealbox = data.subdata(in: 33..<data.count)
        default:
            throw Errors.unsupportedType(typeByte)
        }
    }

    func base64EncodedString() -> String {
        var data = Data([type.byte])
        if case .type1(let senderPublicKey) = type {
            data.append(senderPublicKey)
        }
        data.append(sealbox)
        return data.base64EncodedString()
    }
}
