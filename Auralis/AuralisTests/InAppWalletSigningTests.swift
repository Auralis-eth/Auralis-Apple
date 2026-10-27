@testable import Auralis
import Foundation
import Testing
import web3

/// Pins EIP-191 message signing — the step between a cleared action and a real signature.
///
/// It had no coverage. `personalSign`'s prefix length is `message.count` on `Data` (the UTF-8 **byte**
/// count); a refactor to a `String`'s `count` (characters) or a UTF-16 length would silently produce a
/// signature that ecrecovers to a *different* address — valid-looking, accepted locally, and rejected
/// only by the counterparty or the chain.
///
/// `WalletActionExecutor` coverage is intentionally absent here and not yet written: driving it needs
/// `ToolCallArtifact`'s type metadata, and AuralisRuntime is not in the `AuralisTests` Frameworks build
/// phase, so the test bundle fails to link. Adding that package product to the target is a project-file
/// change; the executor tests land with it.
@MainActor
struct InAppWalletSigningTests {
    // MARK: - EIP-191 personal_sign

    /// Recovers the signer from the signature using a digest this test builds **independently** of the
    /// implementation, so the assertion is a cross-check rather than a tautology: if `personalSign`
    /// changed its prefix bytes or its length semantics, the two digests would diverge and recovery
    /// would land on a different address.
    @Test("a personal_sign signature recovers to the signing address")
    func personalSignRecoversToSigningAddress() throws {
        let privateKey = try Self.abandonPrivateKey()
        let message = Data("Hello, Auralis".utf8)

        let signature = try Self.signature(of: message, privateKey: privateKey)
        let recovered = try KeyUtil.recoverPublicKey(
            message: Self.eip191Digest(message, length: message.count),
            signature: signature
        )

        #expect(recovered.lowercased() == Self.abandonAddress)
    }

    /// The load-bearing one. For a multi-byte message the prefix must carry the **byte** count; using
    /// the character count yields a different digest and therefore a different recovered address.
    /// Asserting both directions is what makes this a real guard: byte-count recovery must match, and
    /// character-count recovery must *not*.
    @Test("the EIP-191 prefix counts UTF-8 bytes, not characters")
    func personalSignPrefixCountsBytes() throws {
        let privateKey = try Self.abandonPrivateKey()
        // 5 characters, 6 UTF-8 bytes — so the two spellings of "length" disagree.
        let message = Data("héllo".utf8)
        #expect(message.count == 6)
        #expect("héllo".count == 5)

        let signature = try Self.signature(of: message, privateKey: privateKey)

        let byteCountRecovery = try KeyUtil.recoverPublicKey(
            message: Self.eip191Digest(message, length: message.count),
            signature: signature
        )
        #expect(byteCountRecovery.lowercased() == Self.abandonAddress)

        let characterCountRecovery = try? KeyUtil.recoverPublicKey(
            message: Self.eip191Digest(message, length: "héllo".count),
            signature: signature
        )
        #expect(characterCountRecovery?.lowercased() != Self.abandonAddress)
    }

    /// Wallets expect `v` in the 27/28 convention; secp256k1 hands back a 0/1 recovery id.
    @Test("the recovery byte is normalized to the 27/28 convention")
    func personalSignNormalizesRecoveryByte() throws {
        let privateKey = try Self.abandonPrivateKey()

        let signature = try Self.signature(of: Data("Hello, Auralis".utf8), privateKey: privateKey)

        #expect(signature.count == 65)
        let recoveryByte = try #require(signature.last)
        #expect(recoveryByte == 27 || recoveryByte == 28)
    }

    @Test("an empty message still signs and recovers")
    func personalSignHandlesEmptyMessage() throws {
        let privateKey = try Self.abandonPrivateKey()

        let signature = try Self.signature(of: Data(), privateKey: privateKey)
        let recovered = try KeyUtil.recoverPublicKey(
            message: Self.eip191Digest(Data(), length: 0),
            signature: signature
        )

        #expect(recovered.lowercased() == Self.abandonAddress)
    }

    // MARK: - Helpers

    /// `m/44'/60'/0'/0/0` of the canonical all-`abandon` BIP-39 seed.
    private static let abandonAddress = "0x9858effd232b4033e47d90003d41ec34ecaeda94"

    private static let abandonSeed = """
        5eb00bbddcf069084889a8ab9155568165f5c453ccb85e70811aaed6f6da5fc1\
        9a5ac40b389cd370d086206dec8aa6c43daea6690f20ad3d8d48b2d2ce9e38e4
        """

    private static func abandonPrivateKey() throws -> Data {
        try InAppWalletDerivation.ethereumPrivateKey(seed: data(hex: abandonSeed))
    }

    private static func signature(of message: Data, privateKey: Data) throws -> Data {
        let hex = try InAppWalletCrypto.personalSign(message: message, privateKey: privateKey)
        return try #require(Data(hex: hex))
    }

    /// Builds the EIP-191 digest with an explicitly supplied `length`, so a test can assert which
    /// notion of "length" the implementation used.
    private static func eip191Digest(_ message: Data, length: Int) -> Data {
        var prefixed = Data("\u{19}Ethereum Signed Message:\n\(length)".utf8)
        prefixed.append(message)
        return prefixed.web3.keccak256
    }

    private static func data(hex: String) -> Data {
        var bytes = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex, let next = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) {
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return Data() }
            bytes.append(byte)
            index = next
        }
        return bytes
    }
}
