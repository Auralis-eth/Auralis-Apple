import Foundation

public struct WalletAccount: Hashable, Codable, Sendable {
    public let caip10: String

    public init(caip10: String) {
        self.caip10 = caip10
    }
}

public struct WalletBlockchain: Hashable, Codable, Sendable {
    public let namespace: String
    public let reference: String

    public init(namespace: String, reference: String) {
        self.namespace = namespace
        self.reference = reference
    }

    public init?(caip2: String) {
        let parts = caip2.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            return nil
        }
        self.init(namespace: String(parts[0]), reference: String(parts[1]))
    }

    public var caip2: String {
        "\(namespace):\(reference)"
    }

    public var knownChain: WalletChain? {
        WalletChain(caip2: caip2)
    }
}

public struct ParsedWalletAccount: Hashable, Codable, Sendable {
    public let blockchain: WalletBlockchain
    public let address: String

    public init(blockchain: WalletBlockchain, address: String) {
        self.blockchain = blockchain
        self.address = address
    }

    public var caip10: String {
        "\(blockchain.caip2):\(address)"
    }
}

public enum WalletAccountParser {
    public static func parse(_ caip10: String) -> ParsedWalletAccount? {
        let parts = caip10.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3, !parts[0].isEmpty, !parts[1].isEmpty, !parts[2].isEmpty else {
            return nil
        }

        let blockchain = WalletBlockchain(namespace: String(parts[0]), reference: String(parts[1]))
        let address = String(parts[2])
        guard blockchain.knownChain != nil, isValid(address: address, on: blockchain) else {
            return nil
        }
        return ParsedWalletAccount(blockchain: blockchain, address: address)
    }

    private static func isValid(address: String, on blockchain: WalletBlockchain) -> Bool {
        switch blockchain.namespace {
        case "eip155":
            address.count == 42 && address.hasPrefix("0x") && address.dropFirst(2).allSatisfy(\.isHexDigit)
        case "solana":
            isValidBase58(address, lengthRange: 32...44)
        default:
            false
        }
    }

    private static func isValidBase58(_ value: String, lengthRange: ClosedRange<Int>) -> Bool {
        guard lengthRange.contains(value.count) else { return false }
        let alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
        return value.allSatisfy { alphabet.contains($0) }
    }
}

public extension WalletAccount {
    init(blockchain: WalletBlockchain, address: String) {
        self.init(caip10: ParsedWalletAccount(blockchain: blockchain, address: address).caip10)
    }

    var parsed: ParsedWalletAccount? {
        WalletAccountParser.parse(caip10)
    }
}
