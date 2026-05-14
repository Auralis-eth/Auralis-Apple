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

    public var allowedHosts: Set<String> {
        Set(entries.compactMap { $0.value.baseURL.host?.lowercased() })
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
        .worldchainMainnet: Entry(label: "WorldScan", baseURL: URL(string: "https://worldscan.org")!),
        .worldchainSepoliaTestnet: Entry(label: "WorldScan", baseURL: URL(string: "https://sepolia.worldscan.org")!),
        .shapeMainnet: Entry(label: "ShapeScan", baseURL: URL(string: "https://shapescan.xyz")!),
        .shapeSepoliaTestnet: Entry(label: "ShapeScan", baseURL: URL(string: "https://sepolia.shapescan.xyz")!),
        .inkMainnet: Entry(label: "Ink Explorer", baseURL: URL(string: "https://explorer.inkonchain.com")!),
        .inkSepoliaTestnet: Entry(label: "Ink Explorer", baseURL: URL(string: "https://explorer-sepolia.inkonchain.com")!),
        .unichainMainnet: Entry(label: "Uniscan", baseURL: URL(string: "https://uniscan.xyz")!),
        .unichainSepoliaTestnet: Entry(label: "Uniscan", baseURL: URL(string: "https://sepolia.uniscan.xyz")!),
        .soneiumMainnet: Entry(label: "Soneium Blockscout", baseURL: URL(string: "https://soneium.blockscout.com")!),
        .soneiumMinatoTestnet: Entry(label: "Soneium Blockscout", baseURL: URL(string: "https://soneium-minato.blockscout.com")!),
        .berachainMainnet: Entry(label: "BeraScan", baseURL: URL(string: "https://berascan.com")!),
        .zoraMainnet: Entry(label: "Zora Explorer", baseURL: URL(string: "https://explorer.zora.energy")!),
        .zoraSepoliaTestnet: Entry(label: "Zora Explorer", baseURL: URL(string: "https://sepolia.explorer.zora.energy")!),
        .polynomialMainnet: Entry(label: "PolynomialScan", baseURL: URL(string: "https://polynomialscan.io")!),
        .polynomialSepoliaTestnet: Entry(label: "PolynomialScan", baseURL: URL(string: "https://sepolia.polynomialscan.io")!),
    ])
}
