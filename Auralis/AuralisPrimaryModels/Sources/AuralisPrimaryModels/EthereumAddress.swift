import Foundation

public struct AuralisEthereumAddress: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init?(_ value: String?) {
        guard let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmedValue.isEmpty else {
            return nil
        }

        let candidate = trimmedValue.lowercased()
        let unprefixedCandidate: String
        if candidate.hasPrefix("0x") {
            unprefixedCandidate = String(candidate.dropFirst(2))
        } else {
            unprefixedCandidate = candidate
        }

        // ASCII-restricted deliberately. `Character.isHexDigit` is true for the fullwidth digit forms
        // (`０`–`９`, U+FF10…) and other Unicode digit variants, so a 40-character string of
        // fullwidth digits used to construct successfully here. Because it carries no cased letters,
        // `checksumState(of:)` then classified it `.unchecksummed` — a warning, not a failure — and a
        // confusable address cleared the governance checks that gate the high-risk signing path.
        // Every real Ethereum address is ASCII hex; nothing legitimate is lost by requiring it.
        guard unprefixedCandidate.count == 40,
              unprefixedCandidate.allSatisfy({ $0.isASCII && $0.isHexDigit }) else {
            return nil
        }

        self.rawValue = "0x" + unprefixedCandidate
    }

    public init?(rawValue: String) {
        self.init(rawValue as String?)
    }

    public var description: String {
        rawValue
    }

    public static func normalized(_ value: String?) -> String? {
        AuralisEthereumAddress(value)?.rawValue
    }
}
