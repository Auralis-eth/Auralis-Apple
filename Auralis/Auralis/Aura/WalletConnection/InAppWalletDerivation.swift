import CryptoKit
import Foundation
import secp256k1
import web3

/// BIP-32 / BIP-44 hierarchical-deterministic key derivation for Auralis's own self-custodial wallet.
///
/// Operates on a **raw binary seed**, not a BIP-39 mnemonic — the 2048-word list only exists to encode
/// entropy as a human-writable phrase, and we deliberately omit that layer (see the wallet design notes).
/// The tradeoff is no exportable seed phrase / cross-wallet restore; recovery is the device-bound,
/// Secure-Enclave-wrapped seed.
///
/// A mnemonic **cannot** be layered on later without changing the derived addresses, and anything built
/// here should assume that. BIP-39 does not hand its entropy to BIP-32: it stretches the *phrase* into a
/// 64-byte seed via `PBKDF2-HMAC-SHA512(mnemonic, "mnemonic" + passphrase, 2048)`. Encoding this wallet's
/// 32 random bytes as 24 words and importing them elsewhere therefore yields a completely different
/// BIP-32 root and a completely different address — so an "export your recovery phrase" feature bolted
/// on top of the current seed would send users to an empty account and look exactly like lost funds.
/// Adopting BIP-39 means generating the seed through it from the start, which is a migration for existing
/// wallets, not an additive change.
///
/// Correctness-critical: every derivation step delegates the elliptic-curve math to `swift-secp256k1`
/// (`PrivateKey.add(_:)` is exactly BIP-32 CKDpriv, `parse256(I_L) + k_par mod n`, with the library
/// validating the result is a valid scalar) and HMAC-SHA512 to CryptoKit. Address derivation reuses
/// web3.swift's keccak/EIP-55 via `KeyUtil` rather than re-implementing hashing.
enum InAppWalletDerivation {
    /// One node of the HD tree: a 32-byte private key and its 32-byte chain code.
    struct ExtendedKey {
        var key: Data
        var chainCode: Data

        /// Overwrites this node's key material in place.
        ///
        /// `Data` is copy-on-write, so this only clears buffers this value uniquely owns — which is the
        /// case for every intermediate node, since each is produced fresh by `deriveChild`. The returned
        /// leaf key is deliberately *not* wiped here; its lifetime belongs to the caller.
        mutating func wipe() {
            key.resetBytes(in: 0..<key.count)
            chainCode.resetBytes(in: 0..<chainCode.count)
        }
    }

    enum DerivationError: Error, Equatable {
        case invalidSeedLength
        case derivationFailed
        case indexOutOfRange
    }

    /// Indices at or above this are BIP-32 *hardened* derivations.
    static let hardenedOffset: UInt32 = 0x8000_0000

    /// The BIP-44 Ethereum path `m/44'/60'/account'/0/addressIndex`.
    ///
    /// Both indices are range-checked rather than wrapped. `accountIndex &+ hardenedOffset` silently
    /// wrapped for any index ≥ 2³¹: `0x8000_0000` produced `m/44'/60'/0/0/x`, a **non-hardened** account,
    /// where the account-level extended public key plus any one child private key reveals the account
    /// private key. `addressIndex` is checked for the mirror reason — a value ≥ 2³¹ would hardened the
    /// leaf that callers and tooling expect to be normal, yielding a different address than the path
    /// string implies. Only index 0 is used today, so neither hazard was reachable; both fail loudly now.
    static func ethereumPath(accountIndex: UInt32 = 0, addressIndex: UInt32 = 0) throws -> [UInt32] {
        guard accountIndex < hardenedOffset, addressIndex < hardenedOffset else {
            throw DerivationError.indexOutOfRange
        }
        return [
            44 + hardenedOffset,
            60 + hardenedOffset,
            accountIndex + hardenedOffset,
            0,
            addressIndex
        ]
    }

    /// BIP-32 root key from a seed: `I = HMAC-SHA512("Bitcoin seed", seed)`, split into key ‖ chain code.
    static func rootKey(seed: Data) throws -> ExtendedKey {
        // BIP-32 allows 128–512 bit seeds.
        guard (16...64).contains(seed.count) else { throw DerivationError.invalidSeedLength }
        let mac = HMAC<SHA512>.authenticationCode(
            for: seed,
            using: SymmetricKey(data: Data("Bitcoin seed".utf8))
        )
        let material = Data(mac)
        let key = Data(material.prefix(32))
        let chainCode = Data(material.suffix(32))
        // Reject the astronomically-unlikely invalid root key (I_L ≥ n or 0) by constructing the scalar.
        guard (try? secp256k1.Signing.PrivateKey(dataRepresentation: key)) != nil else {
            throw DerivationError.derivationFailed
        }
        return ExtendedKey(key: key, chainCode: chainCode)
    }

    /// BIP-32 CKDpriv: derives the child at `index` from a parent extended key.
    static func deriveChild(_ parent: ExtendedKey, index: UInt32) throws -> ExtendedKey {
        var data = Data()
        if index >= hardenedOffset {
            // Hardened: 0x00 ‖ ser256(k_par)
            data.append(0x00)
            data.append(parent.key)
        } else {
            // Normal: serP(point(k_par)) — the 33-byte compressed public key.
            guard let parentKey = try? secp256k1.Signing.PrivateKey(dataRepresentation: parent.key) else {
                throw DerivationError.derivationFailed
            }
            data.append(parentKey.publicKey.dataRepresentation)
        }
        var bigEndianIndex = index.bigEndian
        withUnsafeBytes(of: &bigEndianIndex) { data.append(contentsOf: $0) }

        let mac = HMAC<SHA512>.authenticationCode(for: data, using: SymmetricKey(data: parent.chainCode))
        let material = Data(mac)
        let tweak = Array(material.prefix(32))
        let childChainCode = Data(material.suffix(32))

        // child k = parse256(I_L) + k_par (mod n); the library throws if the result is invalid.
        guard let parentKey = try? secp256k1.Signing.PrivateKey(dataRepresentation: parent.key),
              let childKey = try? parentKey.add(tweak) else {
            throw DerivationError.derivationFailed
        }
        return ExtendedKey(key: childKey.dataRepresentation, chainCode: childChainCode)
    }

    /// Derives the private key at an arbitrary BIP-32 path from `seed`.
    ///
    /// Each intermediate node is wiped as soon as the next one is derived. Without this, every ancestor
    /// key along `m/44'/60'/0'/0/0` is left in freed heap memory; an attacker reading a core dump who
    /// misses the 32-byte seed window would still recover a parent key, which is equivalent to the
    /// spending key for everything beneath it.
    static func derivePrivateKey(seed: Data, path: [UInt32]) throws -> Data {
        var node = try rootKey(seed: seed)
        for index in path {
            var child = try deriveChild(node, index: index)
            node.wipe()
            swap(&node, &child)
        }
        // The leaf is intentionally left intact — it is the return value. Only the master key and the
        // intermediate nodes above it are wiped, which is what the loop does.
        return node.key
    }

    /// The Ethereum EOA private key at `m/44'/60'/account'/0/addressIndex`.
    static func ethereumPrivateKey(seed: Data, accountIndex: UInt32 = 0, addressIndex: UInt32 = 0) throws -> Data {
        try derivePrivateKey(
            seed: seed,
            path: ethereumPath(accountIndex: accountIndex, addressIndex: addressIndex)
        )
    }

    /// The lowercased `0x…` Ethereum address for the derived EOA.
    static func ethereumAddress(seed: Data, accountIndex: UInt32 = 0, addressIndex: UInt32 = 0) throws -> String {
        let privateKey = try ethereumPrivateKey(seed: seed, accountIndex: accountIndex, addressIndex: addressIndex)
        let publicKey = try KeyUtil.generatePublicKey(from: privateKey)
        return KeyUtil.generateAddress(from: publicKey).asString()
    }
}
