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

        guard unprefixedCandidate.count == 40,
              unprefixedCandidate.allSatisfy(\.isHexDigit) else {
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
