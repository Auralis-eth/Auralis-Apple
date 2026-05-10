import AuralisPrimaryModels
import Foundation

public struct ExplorerCatalog: Sendable {
    public struct Entry: Equatable, Sendable {
        public let label: String
        public let baseURL: URL

        public init(label: String, baseURL: URL) {
            self.label = label
            self.baseURL = baseURL
        }
    }

    private let entries: [Chain: Entry]

    public init(entries: [Chain: Entry]) {
        self.entries = entries
    }

    public func entry(for chain: Chain) -> Entry? {
        entries[chain]
    }

    public static let `default` = ExplorerCatalog(entries: [
        .ethMainnet: Entry(label: "Etherscan", baseURL: URL(string: "https://etherscan.io")!),
        .ethSepoliaTestnet: Entry(label: "Etherscan", baseURL: URL(string: "https://sepolia.etherscan.io")!),
        .baseMainnet: Entry(label: "BaseScan", baseURL: URL(string: "https://basescan.org")!),
        .baseSepoliaTestnet: Entry(label: "BaseScan", baseURL: URL(string: "https://sepolia.basescan.org")!),
        .arbMainnet: Entry(label: "Arbiscan", baseURL: URL(string: "https://arbiscan.io")!),
        .arbSepoliaTestnet: Entry(label: "Arbiscan", baseURL: URL(string: "https://sepolia.arbiscan.io")!),
        .arbNovaMainnet: Entry(label: "Arbiscan", baseURL: URL(string: "https://nova.arbiscan.io")!),
        .optMainnet: Entry(label: "Optimistic Etherscan", baseURL: URL(string: "https://optimistic.etherscan.io")!),
        .optSepoliaTestnet: Entry(label: "Optimistic Etherscan", baseURL: URL(string: "https://sepolia-optimism.etherscan.io")!),
        .polygonMainnet: Entry(label: "PolygonScan", baseURL: URL(string: "https://polygonscan.com")!),
        .polygonAmoyTestnet: Entry(label: "PolygonScan", baseURL: URL(string: "https://amoy.polygonscan.com")!),
    ])
}
