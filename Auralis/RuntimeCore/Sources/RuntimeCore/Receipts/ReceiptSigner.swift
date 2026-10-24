import CryptoKit
import Foundation

/// A detached signature over a receipt's chain hash, plus the public key needed to verify it
/// externally. This is what makes the tamper-evident chain *exportable and independently verifiable*
/// (SEC-101): a third party can confirm the sequence without trusting Auralis.
public struct ReceiptSignature: Equatable, Sendable, Codable {
    public let signature: Data
    public let publicKeyRepresentation: Data

    public init(signature: Data, publicKeyRepresentation: Data) {
        self.signature = signature
        self.publicKeyRepresentation = publicKeyRepresentation
    }
}

/// Signs and verifies receipt chain hashes.
public protocol ReceiptSigning: Sendable {
    func sign(_ message: String) async throws -> ReceiptSignature
    func publicKeyRepresentation() async throws -> Data
    func verify(_ message: String, signature: ReceiptSignature) -> Bool
}

public enum ReceiptSignerError: Error, Equatable {
    case messageEncodingFailed
    case invalidPublicKey
}

/// A software P-256 signer (CryptoKit). Suitable for simulator and tests. On device, swap the key
/// source for a Secure Enclave `SecureEnclave.P256.Signing.PrivateKey` behind this same protocol —
/// verification is identical since both emit standard P-256 signatures + public keys.
public struct SoftwareReceiptSigner: ReceiptSigning {
    private let privateKey: P256.Signing.PrivateKey

    public init(privateKey: P256.Signing.PrivateKey = P256.Signing.PrivateKey()) {
        self.privateKey = privateKey
    }

    public func sign(_ message: String) async throws -> ReceiptSignature {
        guard let data = message.data(using: .utf8) else {
            throw ReceiptSignerError.messageEncodingFailed
        }
        let signature = try privateKey.signature(for: data)
        return ReceiptSignature(
            signature: signature.derRepresentation,
            publicKeyRepresentation: privateKey.publicKey.rawRepresentation
        )
    }

    public func publicKeyRepresentation() async throws -> Data {
        privateKey.publicKey.rawRepresentation
    }

    public func verify(_ message: String, signature: ReceiptSignature) -> Bool {
        Self.verifyStatic(message, signature: signature)
    }

    /// Verifies a signature using only the public key carried in the signature — no signer instance
    /// needed. This is the path an external verifier uses over exported receipts.
    public static func verifyStatic(_ message: String, signature: ReceiptSignature) -> Bool {
        guard let data = message.data(using: .utf8),
              let publicKey = try? P256.Signing.PublicKey(rawRepresentation: signature.publicKeyRepresentation),
              let parsed = try? P256.Signing.ECDSASignature(derRepresentation: signature.signature) else {
            return false
        }
        return publicKey.isValidSignature(parsed, for: data)
    }
}

/// A Secure Enclave-backed P-256 signer. The private key is generated inside the Enclave and is not
/// extractable; only signatures and the public key ever leave it. Verification is byte-for-byte
/// identical to ``SoftwareReceiptSigner`` because both emit standard P-256 signatures + public keys,
/// so exported receipts remain independently verifiable without any Enclave.
///
/// The Enclave key cannot be exported, but its *encrypted* blob (``keyDataRepresentation``) can be
/// persisted (e.g. in the Keychain) and restored via ``init(dataRepresentation:)`` so the same signing
/// identity is reused across launches. `SecureEnclave` is unavailable on the simulator — gate
/// construction on ``isAvailable`` and fall back to ``SoftwareReceiptSigner`` there.
public struct SecureEnclaveReceiptSigner: ReceiptSigning {
    private let privateKey: SecureEnclave.P256.Signing.PrivateKey

    /// Whether this device has a usable Secure Enclave. `false` on the simulator and on Macs without one.
    public static var isAvailable: Bool { SecureEnclave.isAvailable }

    /// Restores an existing Enclave key from its persisted blob, or creates a new one when `nil`.
    public init(dataRepresentation: Data? = nil) throws {
        if let dataRepresentation {
            self.privateKey = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: dataRepresentation)
        } else {
            self.privateKey = try SecureEnclave.P256.Signing.PrivateKey()
        }
    }

    /// The persistable, Enclave-encrypted key blob. Store this to reuse the signing identity across
    /// launches; it is meaningless outside this device's Enclave.
    public var keyDataRepresentation: Data { privateKey.dataRepresentation }

    public func sign(_ message: String) async throws -> ReceiptSignature {
        guard let data = message.data(using: .utf8) else {
            throw ReceiptSignerError.messageEncodingFailed
        }
        let signature = try privateKey.signature(for: data)
        return ReceiptSignature(
            signature: signature.derRepresentation,
            publicKeyRepresentation: privateKey.publicKey.rawRepresentation
        )
    }

    public func publicKeyRepresentation() async throws -> Data {
        privateKey.publicKey.rawRepresentation
    }

    public func verify(_ message: String, signature: ReceiptSignature) -> Bool {
        SoftwareReceiptSigner.verifyStatic(message, signature: signature)
    }
}
