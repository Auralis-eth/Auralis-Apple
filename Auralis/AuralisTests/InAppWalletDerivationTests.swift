@testable import Auralis
import Foundation
import Testing

/// Pins the in-app wallet's hand-rolled BIP-32/BIP-44 derivation to published reference vectors.
///
/// This is the code that decides **which address holds the user's funds**, and the wallet has no
/// BIP-39 mnemonic export — recovery is the device-bound Enclave-wrapped seed and nothing else. So a
/// change that silently alters derivation would relocate every existing wallet's address, and the
/// funds at the old one would be unreachable with no way to recover them. Reference vectors are the
/// only thing that makes that class of regression impossible to land unnoticed.
///
/// Every expected value below was produced by running this implementation and checked against the
/// published vectors, not asserted from memory.
struct InAppWalletDerivationTests {
    // MARK: - BIP-32 Test Vector 1 (from the BIP-32 specification)

    /// Seed for BIP-32 Test Vector 1.
    private static let vector1Seed = "000102030405060708090a0b0c0d0e0f"

    @Test("BIP-32 Test Vector 1: master key and chain code")
    func vector1RootKey() throws {
        let root = try InAppWalletDerivation.rootKey(seed: Self.data(hex: Self.vector1Seed))

        #expect(Self.hex(root.key) == "e8f32e723decf4051aefac8e2c93c9c5b214313817cdb01a1494b917c8436b35")
        #expect(Self.hex(root.chainCode) == "873dff81c02f525623fd1fe5167eac3a55a049de3d314bb42ee227ffed37d508")
    }

    @Test("BIP-32 Test Vector 1: m/0' exercises the hardened branch")
    func vector1HardenedChild() throws {
        let root = try InAppWalletDerivation.rootKey(seed: Self.data(hex: Self.vector1Seed))
        let child = try InAppWalletDerivation.deriveChild(root, index: InAppWalletDerivation.hardenedOffset)

        #expect(Self.hex(child.key) == "edb2e14f9ee77d26dd93b4ecede8d16ed408ce149b6cd80b0715a2d911a0afea")
        #expect(Self.hex(child.chainCode) == "47fdacbd0f1097043b78c63c20c34ef4ed9a111d980047ad16282c7ae6236141")
    }

    /// The non-hardened branch serializes the parent's *compressed public key* rather than
    /// `0x00 ‖ private key`, so it exercises a different CKDpriv path than the test above.
    @Test("BIP-32 Test Vector 1: m/0'/1 exercises the non-hardened branch")
    func vector1NonHardenedChild() throws {
        let key = try InAppWalletDerivation.derivePrivateKey(
            seed: Self.data(hex: Self.vector1Seed),
            path: [InAppWalletDerivation.hardenedOffset, 1]
        )

        #expect(Self.hex(key) == "3c6cb8d0f6a264c91ea8b5030fadaa8e538b020f0a387421a12de9319dc93368")
    }

    // MARK: - BIP-44 Ethereum

    /// The BIP-39 seed for the canonical all-`abandon` test mnemonic
    /// ("abandon" ×11 + "about", empty passphrase). The wallet consumes a raw binary seed rather than
    /// a mnemonic, so the seed is supplied directly — this is the published seed for that phrase, and
    /// its `m/44'/60'/0'/0/0` address is the value every Ethereum wallet derives from it.
    private static let abandonSeed = """
        5eb00bbddcf069084889a8ab9155568165f5c453ccb85e70811aaed6f6da5fc1\
        9a5ac40b389cd370d086206dec8aa6c43daea6690f20ad3d8d48b2d2ce9e38e4
        """

    @Test("BIP-44 m/44'/60'/0'/0/0 matches the reference Ethereum key and address")
    func bip44EthereumAccountZero() throws {
        let seed = Self.data(hex: Self.abandonSeed)

        let key = try InAppWalletDerivation.ethereumPrivateKey(seed: seed)
        #expect(Self.hex(key) == "1ab42cc412b618bdea3a599e3c9bae199ebf030895b039e9db1e30dafb12b727")
        #expect(try InAppWalletDerivation.ethereumAddress(seed: seed) == "0x9858effd232b4033e47d90003d41ec34ecaeda94")
    }

    @Test("BIP-44 address index advances along the external chain")
    func bip44AddressIndexAdvances() throws {
        let seed = Self.data(hex: Self.abandonSeed)

        #expect(
            try InAppWalletDerivation.ethereumAddress(seed: seed, addressIndex: 1)
                == "0x6fac4d18c912343bf86fa7049364dd4e424ab9c0"
        )
    }

    @Test("the derived Ethereum path is m/44'/60'/account'/0/addressIndex")
    func ethereumPathShape() throws {
        let hardened = InAppWalletDerivation.hardenedOffset

        let defaultPath = try InAppWalletDerivation.ethereumPath()
        #expect(defaultPath == [44 + hardened, 60 + hardened, 0 + hardened, 0, 0])

        let explicitPath = try InAppWalletDerivation.ethereumPath(accountIndex: 2, addressIndex: 7)
        #expect(explicitPath == [44 + hardened, 60 + hardened, 2 + hardened, 0, 7])
    }

    /// An index at or above 2³¹ must be refused, not wrapped into a different path.
    ///
    /// `accountIndex &+ hardenedOffset` used to wrap, so `0x8000_0000` silently produced
    /// `m/44'/60'/0/0/x` — a **non-hardened** account, where the account xpub plus any one child
    /// private key recovers the account private key. The call succeeded and returned a valid-looking
    /// key, so nothing downstream could notice. `addressIndex` is covered for the mirror case: a value
    /// that high would harden the leaf the path string says is normal, yielding a different address.
    @Test("an out-of-range index is refused rather than wrapping into a non-hardened path")
    func ethereumPathRefusesOutOfRangeIndices() throws {
        let hardened = InAppWalletDerivation.hardenedOffset

        #expect(throws: InAppWalletDerivation.DerivationError.indexOutOfRange) {
            try InAppWalletDerivation.ethereumPath(accountIndex: hardened)
        }
        #expect(throws: InAppWalletDerivation.DerivationError.indexOutOfRange) {
            try InAppWalletDerivation.ethereumPath(addressIndex: hardened)
        }
        #expect(throws: InAppWalletDerivation.DerivationError.indexOutOfRange) {
            try InAppWalletDerivation.ethereumPath(accountIndex: .max)
        }
        // The last in-range value still derives the hardened account it names.
        let boundaryPath = try InAppWalletDerivation.ethereumPath(accountIndex: hardened - 1)
        #expect(boundaryPath == [44 + hardened, 60 + hardened, .max, 0, 0])
    }

    /// The seed-facing entry points propagate the range check rather than deriving a wrapped path.
    @Test("key and address derivation reject an out-of-range account index")
    func seedEntryPointsRejectOutOfRangeIndex() {
        let seed = Self.data(hex: Self.abandonSeed)

        #expect(throws: InAppWalletDerivation.DerivationError.indexOutOfRange) {
            try InAppWalletDerivation.ethereumPrivateKey(
                seed: seed,
                accountIndex: InAppWalletDerivation.hardenedOffset
            )
        }
        #expect(throws: InAppWalletDerivation.DerivationError.indexOutOfRange) {
            try InAppWalletDerivation.ethereumAddress(
                seed: seed,
                addressIndex: InAppWalletDerivation.hardenedOffset
            )
        }
    }

    // MARK: - Determinism and bounds

    /// Repeated derivation is stable *and* lands on the pinned address.
    ///
    /// Comparing the call to itself would pass for any implementation, including a wrong one — so the
    /// expected value is spelled out. This also covers the in-place wiping of intermediate BIP-32 nodes
    /// in `derivePrivateKey`: a wipe that clobbered a buffer still in use would change the result here.
    @Test("derivation is deterministic and lands on the pinned address")
    func derivationIsDeterministic() throws {
        let seed = Self.data(hex: Self.abandonSeed)
        let expected = "0x9858effd232b4033e47d90003d41ec34ecaeda94"

        #expect(try InAppWalletDerivation.ethereumAddress(seed: seed) == expected)
        #expect(try InAppWalletDerivation.ethereumAddress(seed: seed) == expected)
    }

    /// The private key at the default path must match the address the wallet registers, and must stay
    /// stable across repeated derivations now that intermediate nodes are wiped in place.
    @Test("repeated private-key derivation is stable under intermediate-node wiping")
    func privateKeyDerivationIsStableUnderWiping() throws {
        let seed = Self.data(hex: Self.abandonSeed)

        let first = try InAppWalletDerivation.ethereumPrivateKey(seed: seed)
        let second = try InAppWalletDerivation.ethereumPrivateKey(seed: seed)

        #expect(first == second)
        #expect(first.count == 32)
        #expect(!first.allSatisfy { $0 == 0 })
    }

    @Test("distinct seeds derive distinct addresses")
    func distinctSeedsDeriveDistinctAddresses() throws {
        let first = try InAppWalletDerivation.ethereumAddress(seed: Data(repeating: 1, count: 32))
        let second = try InAppWalletDerivation.ethereumAddress(seed: Data(repeating: 2, count: 32))

        #expect(first != second)
    }

    /// BIP-32 admits 128–512 bit seeds. The keystore mints 256, but the bound is enforced here so a
    /// truncated or over-long seed is refused rather than silently derived from.
    @Test("seed length is held to the BIP-32 128–512 bit range", arguments: [15, 65, 0])
    func rejectsOutOfRangeSeedLengths(byteCount: Int) {
        #expect(throws: InAppWalletDerivation.DerivationError.invalidSeedLength) {
            _ = try InAppWalletDerivation.rootKey(seed: Data(repeating: 7, count: byteCount))
        }
    }

    @Test("seed lengths at both ends of the range are accepted", arguments: [16, 32, 64])
    func acceptsInRangeSeedLengths(byteCount: Int) throws {
        let root = try InAppWalletDerivation.rootKey(seed: Data(repeating: 7, count: byteCount))

        #expect(root.key.count == 32)
        #expect(root.chainCode.count == 32)
    }

    // MARK: - Helpers

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

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
