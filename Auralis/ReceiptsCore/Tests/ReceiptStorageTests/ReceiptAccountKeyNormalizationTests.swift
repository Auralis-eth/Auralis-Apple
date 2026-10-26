import Foundation
@testable import ReceiptStorage
import Testing

/// F-107: the explicit account-address branch of `ReceiptAccountAddress.resolve` lowercased without
/// prefixing, while the payload branch has always normalized through `AuralisEthereumAddress` and
/// emits `"0x" + 40hex`. A caller passing a valid but unprefixed address therefore wrote a row keyed
/// `"abc…"` that every fetch predicate — all built from `accountKey`, which normalizes — searched for
/// as `"0xabc…"`, so the receipt was excluded from its own account's timeline permanently.
///
/// The Round 18 mitigation was a `#if DEBUG` assertion, which is compiled out of precisely the
/// configuration users run; this pins the release-safe behaviour instead.
struct ReceiptAccountKeyNormalizationTests {
    private static let unprefixed = "abcdef0123456789abcdef0123456789abcdef01"

    /// The defect itself. Pre-fix this returned the bare 40-hex string.
    @Test("a valid but unprefixed account address is stored in the form the readers search for")
    func unprefixedAddressIsNormalized() {
        #expect(ReceiptAccountAddress.normalizedAccountKey(Self.unprefixed) == "0x\(Self.unprefixed)")
    }

    /// The agreement that was broken: the stored key has to equal what the readers compute, because a
    /// predicate can only narrow and never recover a row it dropped.
    @Test("the stored key agrees with the fetch predicate's key for an unprefixed address")
    func storedKeyMatchesPredicateKeyForUnprefixedAddress() {
        let stored = ReceiptAccountAddress.normalizedAccountKey(Self.unprefixed)
        let searched = "0x" + Self.unprefixed.lowercased()
        #expect(stored == searched)
    }

    /// The hash-neutrality claim the fix rests on, asserted rather than reasoned: for every shape a
    /// writer actually emits, the new expression returns exactly what the old one did, so no receipt
    /// currently on disk is re-interpreted and nothing currently writable re-hashes.
    @Test("normalization is byte-identical to the previous behaviour for already-prefixed addresses")
    func prefixedAddressesAreUnchanged() {
        for input in [
            "0xabcdef0123456789abcdef0123456789abcdef01",
            "0xABCDEF0123456789ABCDEF0123456789ABCDEF01",
            "0xAbCdEf0123456789aBcDeF0123456789AbCdEf01"
        ] {
            #expect(
                ReceiptAccountAddress.normalizedAccountKey(input) == input.lowercased(),
                "prefixed address \(input) changed its stored key"
            )
        }
    }

    /// The control, and the reason `AuralisEthereumAddress` is used as a normalizer and not as a
    /// validator: a non-address account key has to survive as itself. Turning it into `nil` would move
    /// that receipt onto the "global" chain; turning it into an address would be worse.
    @Test("a non-address account key is lowercased and otherwise left alone")
    func nonAddressKeysSurviveAsThemselves() {
        for input in ["vitalik.eth", "Vitalik.ETH", "global", "0xnot-an-address"] {
            #expect(
                ReceiptAccountAddress.normalizedAccountKey(input) == input.lowercased(),
                "non-address key \(input) was not preserved"
            )
        }
    }
}
