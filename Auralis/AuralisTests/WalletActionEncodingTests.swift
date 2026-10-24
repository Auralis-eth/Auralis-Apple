@testable import Auralis
import AuralisPrimaryModels
import Foundation
import Testing
import WalletConnectorKit

/// Pins the invariants that stand between a cleared Operate-mode action and the chain.
///
/// Every assertion here guards a path where a silent wrong answer spends real funds: the ABI encoding
/// of an approval, the refusal of an unbounded allowance, and the chain a transaction is routed on.
/// None of these had coverage before — a regression in any of them would have shipped green.
@MainActor
struct WalletActionEncodingTests {
    // MARK: - approve(address,uint256) ABI encoding

    /// A known-good vector: selector, 24 zero nibbles of left-pad, the lowercased address, then the
    /// amount as a 32-byte big-endian word.
    @Test("approve calldata matches the ABI layout for a known vector")
    func approveCallDataMatchesKnownVector() throws {
        let data = try ERC20ApproveCallData.encode(
            spender: "0x1111111111111111111111111111111111111111",
            amount: "1"
        )

        #expect(data == "0x095ea7b3"
            + "0000000000000000000000001111111111111111111111111111111111111111"
            + "0000000000000000000000000000000000000000000000000000000000000001")
    }

    @Test("the approve selector is the published keccak prefix")
    func selectorIsPublishedValue() {
        #expect(ERC20ApproveCallData.selector == "095ea7b3")
    }

    @Test("a 0x-prefixed amount encodes identically to its decimal spelling")
    func hexAndDecimalAmountsAgree() throws {
        let spender = "0x2222222222222222222222222222222222222222"

        let fromHex = try ERC20ApproveCallData.encode(spender: spender, amount: "0xff")
        let fromDecimal = try ERC20ApproveCallData.encode(spender: spender, amount: "255")

        #expect(fromHex == fromDecimal)
    }

    @Test("a mixed-case address is left-padded and lowercased, not rejected")
    func mixedCaseAddressIsNormalized() throws {
        let data = try ERC20ApproveCallData.encode(
            spender: "0xAbCdEf0123456789aBcDeF0123456789AbCdEf01",
            amount: "1"
        )

        #expect(data.contains("000000000000000000000000abcdef0123456789abcdef0123456789abcdef01"))
    }

    // MARK: - The infinite-approval refusal

    /// The load-bearing one: max-uint256 is the classic allowance-drain vector, and this project
    /// deliberately refuses it rather than merely warning.
    @Test("max-uint256 is refused in both hex and decimal spellings", arguments: [
        "0x" + String(repeating: "f", count: 64),
        "0x" + String(repeating: "F", count: 64),
        "115792089237316195423570985008687907853269984665640564039457584007913129639935"
    ])
    func infiniteApprovalIsRefused(amount: String) {
        #expect(throws: ERC20ApproveCallData.EncodingError.infiniteApprovalRefused) {
            try ERC20ApproveCallData.encode(
                spender: "0x3333333333333333333333333333333333333333",
                amount: amount
            )
        }
    }

    /// One below max-uint256 is a real (if enormous) allowance and must still encode — the refusal is
    /// specifically of the sentinel value, not of large numbers.
    @Test("max-uint256 minus one is permitted")
    func oneBelowMaxIsPermitted() throws {
        let amount = "0x" + String(repeating: "f", count: 63) + "e"

        let data = try ERC20ApproveCallData.encode(
            spender: "0x4444444444444444444444444444444444444444",
            amount: amount
        )

        #expect(data.hasSuffix(String(repeating: "f", count: 63) + "e"))
    }

    @Test("an amount above 2^256-1 fails closed instead of wrapping")
    func overflowingAmountIsRefused() {
        // 2^256, one past the representable maximum.
        let amount = "115792089237316195423570985008687907853269984665640564039457584007913129639936"

        #expect(throws: ERC20ApproveCallData.EncodingError.amountTooLarge) {
            try ERC20ApproveCallData.encode(
                spender: "0x5555555555555555555555555555555555555555",
                amount: amount
            )
        }
    }

    // MARK: - Malformed input fails closed

    @Test("a fullwidth digit is refused rather than silently encoding a different amount", arguments: [
        "１００",           // fullwidth decimal digits
        "0xＦＦ"            // fullwidth hex digits
    ])
    func fullwidthDigitsAreRefused(amount: String) {
        #expect(throws: (any Error).self) {
            try ERC20ApproveCallData.encode(
                spender: "0x6666666666666666666666666666666666666666",
                amount: amount
            )
        }
    }

    @Test("a malformed spender is refused", arguments: [
        "",
        "0x",
        "0x123",                                          // too short
        "0x11111111111111111111111111111111111111112",    // too long
        "0xzzzz111111111111111111111111111111111111",     // non-hex
        "0xＡ111111111111111111111111111111111111111"      // fullwidth hex character
    ])
    func malformedSpenderIsRefused(spender: String) {
        #expect(throws: (any Error).self) {
            try ERC20ApproveCallData.encode(spender: spender, amount: "1")
        }
    }

    @Test("an empty or non-numeric amount is refused", arguments: ["", "   ", "abc", "0x", "-1", "1.5"])
    func malformedAmountIsRefused(amount: String) {
        #expect(throws: (any Error).self) {
            try ERC20ApproveCallData.encode(
                spender: "0x7777777777777777777777777777777777777777",
                amount: amount
            )
        }
    }

    // MARK: - Chain resolution fails closed

    /// The connector routes only nine EVM chains while the app's `Chain` enum covers thirty. Resolving
    /// an unroutable id to Ethereum mainnet would re-point an approved testnet or L2 transfer at
    /// mainnet with the same `to`, `value`, and calldata — so it must return `nil`, not a default.
    @Test("an unroutable chain id resolves to nil rather than mainnet", arguments: [
        "11155111",         // Ethereum Sepolia
        "84532",            // Base Sepolia
        "eip155:11155111",
        "0xaa36a7",         // Sepolia in hex
        "7777777",          // Zora
        "999999999"
    ])
    func unroutableChainResolvesToNil(chainID: String) {
        #expect(AuralisWalletConnectionService.resolveChain(chainID) == nil)
    }

    @Test("a routable chain id still resolves", arguments: [
        ("1", "1"),
        ("0x1", "1"),
        ("eip155:1", "1"),
        ("8453", "8453"),
        ("0x2105", "8453"),
        ("137", "137")
    ])
    func routableChainResolves(chainID: String, expectedReference: String) throws {
        let chain = try #require(AuralisWalletConnectionService.resolveChain(chainID))

        #expect(chain.chainReference == expectedReference)
    }

    @Test("malformed chain ids resolve to nil", arguments: ["", "   ", "abc", "0xzz", "eip155:", "1.5"])
    func malformedChainResolvesToNil(chainID: String) {
        #expect(AuralisWalletConnectionService.resolveChain(chainID) == nil)
    }

    /// A transaction must always name a chain it can actually route; only `personal_sign` may fall back,
    /// because EIP-191 binds no chain and the value is used solely to select a session namespace.
    @Test("requireChain throws for a transaction on an unroutable chain")
    func requireChainThrowsForTransaction() {
        #expect(throws: WalletConnectionError.invalidChain("11155111")) {
            try AuralisWalletConnectionService.requireChain("11155111", allowingUnspecified: false)
        }
    }

    @Test("requireChain throws for a missing chain when the caller is a transaction")
    func requireChainThrowsForMissingTransactionChain() {
        #expect(throws: (any Error).self) {
            try AuralisWalletConnectionService.requireChain(nil, allowingUnspecified: false)
        }
    }

    @Test("requireChain allows an absent chain only when unspecified is permitted", arguments: [nil, "", "  "])
    func requireChainAllowsUnspecifiedForSigning(chainID: String?) throws {
        let chain = try AuralisWalletConnectionService.requireChain(chainID, allowingUnspecified: true)

        #expect(chain == .ethereum)
    }

    /// Permitting an *absent* chain must not also permit a *present but unroutable* one — the caller
    /// named a specific chain, and routing it elsewhere is the bug this guards.
    @Test("requireChain still throws for a present but unroutable chain when signing")
    func requireChainThrowsForPresentUnroutableChainWhenSigning() {
        #expect(throws: (any Error).self) {
            try AuralisWalletConnectionService.requireChain("11155111", allowingUnspecified: true)
        }
    }

    // MARK: - Address shape validation

    /// web3.swift's RLP encoder falls back to UTF-8 bytes for a non-hex address rather than failing, so
    /// a malformed `to` would RLP-encode as arbitrary bytes. The signer checks shape before the RPC
    /// round-trip so the failure names the field instead of surfacing an opaque node error.
    @Test("a malformed address is rejected by the signer's shape check", arguments: [
        "",
        "0x",
        "0x123",
        "0x11111111111111111111111111111111111111112",
        "vitalik.eth",
        "0xzzzz111111111111111111111111111111111111",
        "0xＡ111111111111111111111111111111111111111",
        "1111111111111111111111111111111111111111"
    ])
    func malformedAddressIsRejected(address: String) {
        #expect(InAppWalletSigner.isHexAddress(address) == false)
    }

    @Test("well-formed addresses pass the shape check regardless of case", arguments: [
        "0x1111111111111111111111111111111111111111",
        "0xAbCdEf0123456789aBcDeF0123456789AbCdEf01",
        "0XABCDEF0123456789ABCDEF0123456789ABCDEF01"
    ])
    func wellFormedAddressPasses(address: String) {
        #expect(InAppWalletSigner.isHexAddress(address))
    }

    // MARK: - EIP-55 checksum enforcement at the executor

    /// A mixed-case address whose capitalization does not match EIP-55 has been mistyped or altered, and
    /// a transposed character is exactly what the checksum exists to catch. This is enforced in
    /// `WalletActionExecutor` rather than the ABI encoder so that `token`, `spender`, `owner`, `from`,
    /// and `to` are all covered — validating only the encoder's `spender` would have been worse than
    /// the original gap.
    /// The four mixed-case vectors from the EIP-55 specification itself.
    @Test("the EIP-55 spec vectors validate", arguments: [
        "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed",
        "0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359",
        "0xdbF03B407c01E7cD3CBea99509d93f8DDDC8C6FB",
        "0xD1220A0cf47c7B9Be7A2E6BA89F429762e7b9aDb"
    ])
    func eip55SpecVectorsValidate(address: String) {
        #expect(AuralisEthereumAddress.checksumState(of: address) == .valid)
    }

    /// A transposed or altered character in a checksummed address is exactly what EIP-55 catches, and
    /// must classify as `.invalid` — materially different from "carries no checksum".
    @Test("a corrupted EIP-55 address is invalid, not merely unchecksummed")
    func eip55MismatchIsDetected() throws {
        let valid = "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed"
        #expect(AuralisEthereumAddress.checksumState(of: valid) == .valid)

        // Flip the case of the first letter that carries checksum information.
        var corrupted = Array(valid)
        let index = try #require(corrupted.indices.first { corrupted[$0].isLetter && $0 > 1 })
        corrupted[index] = corrupted[index].isUppercase
            ? Character(corrupted[index].lowercased())
            : Character(corrupted[index].uppercased())

        #expect(AuralisEthereumAddress.checksumState(of: String(corrupted)) == .invalid)
    }

    /// Single-case addresses carry no checksum and must keep working — lowercase is the form most
    /// tooling emits, and refusing it would break ordinary use.
    @Test("single-case addresses are unchecksummed rather than invalid", arguments: [
        "0xabc0000000000000000000000000000000000001",
        "0xABC0000000000000000000000000000000000001"
    ])
    func singleCaseAddressesAreUnchecksummed(address: String) {
        #expect(AuralisEthereumAddress.checksumState(of: address) == .unchecksummed)
    }
}
