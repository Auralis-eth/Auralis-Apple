import Foundation

/// What an address's capitalization says about its EIP-55 checksum.
///
/// EIP-55 encodes a checksum in the *case* of an address's hex letters, so an address that is
/// entirely lower- or uppercase carries no checksum to verify — it is well-formed but unverifiable,
/// which is a materially different answer from "the checksum is wrong". Callers that gate on
/// checksums need to tell those apart: rejecting unchecksummed addresses would reject the lowercase
/// form most tooling emits, while accepting invalid ones defeats the point of the checksum.
public enum AuralisEthereumAddressChecksumState: Equatable, Sendable {
    /// Not a 0x-prefixed 40-hex address at all.
    case malformed
    /// Well-formed, but single-case — there is no checksum to verify.
    case unchecksummed
    /// Mixed-case and the capitalization matches the EIP-55 checksum.
    case valid
    /// Mixed-case and the capitalization does *not* match the EIP-55 checksum.
    case invalid
}

public extension AuralisEthereumAddress {
    /// The EIP-55 mixed-case checksum form of this address.
    var checksummed: String {
        let hex = String(rawValue.dropFirst(2))
        let digest = AuralisKeccak256.hash(Data(hex.utf8))
        var result = "0x"
        for (index, character) in hex.enumerated() {
            guard character.isLetter else {
                result.append(character)
                continue
            }
            // EIP-55: uppercase the nibble when the corresponding hash nibble is >= 8.
            let nibble = index.isMultiple(of: 2)
                ? digest[index / 2] >> 4
                : digest[index / 2] & 0x0f
            result.append(nibble >= 8 ? Character(character.uppercased()) : character)
        }
        return result
    }

    /// Classifies `value` against EIP-55 without normalizing away the capitalization that carries the
    /// checksum. Use this rather than ``init(_:)`` when the case of the input is the thing under test:
    /// the initializer lowercases as it normalizes, which discards the checksum.
    static func checksumState(of value: String?) -> AuralisEthereumAddressChecksumState {
        guard let value, let normalized = AuralisEthereumAddress(value) else {
            return .malformed
        }
        let hex = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "0x", with: "", options: [.anchored, .caseInsensitive])
        let letters = hex.filter(\.isLetter)
        guard letters.contains(where: \.isUppercase), letters.contains(where: \.isLowercase) else {
            return .unchecksummed
        }
        return String(normalized.checksummed.dropFirst(2)) == hex ? .valid : .invalid
    }
}

/// Keccak-256 (the pre-NIST padding Ethereum uses, *not* SHA3-256), needed here because EIP-55
/// checksums are defined over it.
///
/// Deliberately duplicated from `WalletConnectorKit`'s provider rather than shared: this module is a
/// leaf that the runtime and its deterministic checks depend on, and `WalletConnectorKit` sits far
/// above it in the graph. Both copies are pinned to the standard Ethereum test vectors.
enum AuralisKeccak256 {
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
            18, 2, 61, 56, 14
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
            0x0000000080000001, 0x8000000080008008
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
