import Foundation

/// ABI-encodes an ERC-20 `approve(address,uint256)` call into `eth_sendTransaction` calldata.
///
/// Pure and dependency-free (no BigInt/web3 types): it parses the `spender`/`amount` the user reviewed on
/// a cleared `approveSpending` payload and produces the `0x`-prefixed calldata to send to the token
/// contract. Fails closed on any malformed input, and — per the exact-amount policy — refuses the
/// max-uint256 "infinite" approval that is the classic allowance-drain vector, so an unbounded approval can
/// never be submitted from a cleared Operate-mode action.
enum ERC20ApproveCallData {
    enum EncodingError: LocalizedError, Equatable {
        case malformedAddress(String)
        case malformedAmount(String)
        case amountTooLarge
        case infiniteApprovalRefused

        var errorDescription: String? {
            switch self {
            case let .malformedAddress(value):
                return "“\(value)” is not a valid spender address."
            case let .malformedAmount(value):
                return "“\(value)” is not a valid approval amount."
            case .amountTooLarge:
                return "The approval amount is larger than a 256-bit integer can hold."
            case .infiniteApprovalRefused:
                return "Unlimited (max-uint256) approvals aren't allowed — specify an exact amount."
            }
        }
    }

    /// The `approve(address,uint256)` function selector: the first 4 bytes of keccak256 of the signature.
    static let selector = "095ea7b3"

    /// Builds the calldata for `approve(spender, amount)`. `amount` may be decimal or `0x`-hex.
    static func encode(spender: String, amount: String) throws -> String {
        let spenderWord = try addressWord(spender)
        let amountWord = try uint256Word(amount)
        return "0x" + selector + spenderWord + amountWord
    }

    /// Left-pads a validated 20-byte address to a 32-byte ABI word (64 lowercase hex chars).
    private static func addressWord(_ address: String) throws -> String {
        let hex = stripHexPrefix(address)
        // ASCII-only for the same reason as the amount: a fullwidth hex character passes
        // `isHexDigit` and would be spliced straight into the calldata string, emitting calldata
        // that is not valid hex at all.
        guard hex.count == 40, hex.allSatisfy(\.isASCIIHexDigit) else {
            throw EncodingError.malformedAddress(address)
        }
        return String(repeating: "0", count: 24) + hex.lowercased()
    }

    /// Encodes the amount as a 32-byte ABI word, refusing the infinite (all-`0xff`) approval.
    private static func uint256Word(_ amount: String) throws -> String {
        let bytes = try uint256BigEndianBytes(amount)
        if bytes.allSatisfy({ $0 == 0xff }) {
            throw EncodingError.infiniteApprovalRefused
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Parses a decimal or `0x`-hex amount into exactly 32 big-endian bytes, failing closed on overflow.
    /// Exposed (not private) so it can be exercised directly by known ABI test vectors.
    static func uint256BigEndianBytes(_ amount: String) throws -> [UInt8] {
        let trimmed = amount.trimmingCharacters(in: .whitespaces)
        var bytes = [UInt8](repeating: 0, count: 32)

        if trimmed.lowercased().hasPrefix("0x") {
            let hex = String(trimmed.dropFirst(2))
            // `isHexDigit`/`isNumber` are Unicode-aware and accept fullwidth forms such as "Ｆ"
            // (U+FF26) and "１" (U+FF11), which `UInt8(_:radix:)` cannot parse. Requiring ASCII is
            // what makes the byte loop below total: the old `?? 0` fallback turned an unparsable
            // digit into a zero byte, so the calldata silently encoded a *different* amount than the
            // one the user reviewed and approved.
            guard !hex.isEmpty, hex.count <= 64, hex.allSatisfy(\.isASCIIHexDigit) else {
                throw EncodingError.malformedAmount(amount)
            }
            let padded = String(repeating: "0", count: 64 - hex.count) + hex.lowercased()
            var index = padded.startIndex
            for position in 0..<32 {
                let next = padded.index(index, offsetBy: 2)
                guard let byte = UInt8(padded[index..<next], radix: 16) else {
                    throw EncodingError.malformedAmount(amount)
                }
                bytes[position] = byte
                index = next
            }
            return bytes
        }

        // Decimal: accumulate digit by digit as value = value * 10 + digit, big-endian, with carry-out
        // detection so anything exceeding 2^256 - 1 fails closed rather than silently wrapping.
        guard !trimmed.isEmpty, trimmed.allSatisfy(\.isASCIIDigit) else {
            throw EncodingError.malformedAmount(amount)
        }
        for character in trimmed {
            guard let digit = character.wholeNumberValue else {
                throw EncodingError.malformedAmount(amount)
            }
            var carry = UInt16(digit)
            var position = 31
            while position >= 0 {
                let product = UInt16(bytes[position]) * 10 + carry
                bytes[position] = UInt8(product & 0xff)
                carry = product >> 8
                position -= 1
            }
            if carry != 0 {
                throw EncodingError.amountTooLarge
            }
        }
        return bytes
    }

    private static func stripHexPrefix(_ value: String) -> String {
        value.lowercased().hasPrefix("0x") ? String(value.dropFirst(2)) : value
    }
}

private extension Character {
    /// ASCII `0`–`9` only — unlike `isNumber`, which also matches fullwidth and other Unicode digits.
    var isASCIIDigit: Bool { isASCII && ("0"..."9").contains(self) }

    /// ASCII `0`–`9`, `a`–`f`, `A`–`F` only — unlike `isHexDigit`, which is Unicode-aware.
    var isASCIIHexDigit: Bool { isASCII && isHexDigit }
}
