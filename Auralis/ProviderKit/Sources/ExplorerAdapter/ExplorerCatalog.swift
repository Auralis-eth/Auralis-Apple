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
        .ethMainnet: Entry(label: "Etherscan", baseURL: validatedBaseURL("https://etherscan.io")),
        .ethSepoliaTestnet: Entry(label: "Etherscan", baseURL: validatedBaseURL("https://sepolia.etherscan.io")),
        .baseMainnet: Entry(label: "BaseScan", baseURL: validatedBaseURL("https://basescan.org")),
        .baseSepoliaTestnet: Entry(label: "BaseScan", baseURL: validatedBaseURL("https://sepolia.basescan.org")),
        .arbMainnet: Entry(label: "Arbiscan", baseURL: validatedBaseURL("https://arbiscan.io")),
        .arbSepoliaTestnet: Entry(label: "Arbiscan", baseURL: validatedBaseURL("https://sepolia.arbiscan.io")),
        .arbNovaMainnet: Entry(label: "Arbiscan", baseURL: validatedBaseURL("https://nova.arbiscan.io")),
        .optMainnet: Entry(label: "Optimistic Etherscan", baseURL: validatedBaseURL("https://optimistic.etherscan.io")),
        .optSepoliaTestnet: Entry(label: "Optimistic Etherscan", baseURL: validatedBaseURL("https://sepolia-optimism.etherscan.io")),
        .polygonMainnet: Entry(label: "PolygonScan", baseURL: validatedBaseURL("https://polygonscan.com")),
        .polygonAmoyTestnet: Entry(label: "PolygonScan", baseURL: validatedBaseURL("https://amoy.polygonscan.com")),
        .worldchainMainnet: Entry(label: "WorldScan", baseURL: validatedBaseURL("https://worldscan.org")),
        .worldchainSepoliaTestnet: Entry(label: "WorldScan", baseURL: validatedBaseURL("https://sepolia.worldscan.org")),
        .shapeMainnet: Entry(label: "ShapeScan", baseURL: validatedBaseURL("https://shapescan.xyz")),
        .shapeSepoliaTestnet: Entry(label: "ShapeScan", baseURL: validatedBaseURL("https://sepolia.shapescan.xyz")),
        .inkMainnet: Entry(label: "Ink Explorer", baseURL: validatedBaseURL("https://explorer.inkonchain.com")),
        .inkSepoliaTestnet: Entry(label: "Ink Explorer", baseURL: validatedBaseURL("https://explorer-sepolia.inkonchain.com")),
        .unichainMainnet: Entry(label: "Uniscan", baseURL: validatedBaseURL("https://uniscan.xyz")),
        .unichainSepoliaTestnet: Entry(label: "Uniscan", baseURL: validatedBaseURL("https://sepolia.uniscan.xyz")),
        .soneiumMainnet: Entry(label: "Soneium Blockscout", baseURL: validatedBaseURL("https://soneium.blockscout.com")),
        .soneiumMinatoTestnet: Entry(label: "Soneium Blockscout", baseURL: validatedBaseURL("https://soneium-minato.blockscout.com")),
        .berachainMainnet: Entry(label: "BeraScan", baseURL: validatedBaseURL("https://berascan.com")),
        .zoraMainnet: Entry(label: "Zora Explorer", baseURL: validatedBaseURL("https://explorer.zora.energy")),
        .zoraSepoliaTestnet: Entry(label: "Zora Explorer", baseURL: validatedBaseURL("https://sepolia.explorer.zora.energy")),
        .polynomialMainnet: Entry(label: "PolynomialScan", baseURL: validatedBaseURL("https://polynomialscan.io")),
        .polynomialSepoliaTestnet: Entry(label: "PolynomialScan", baseURL: validatedBaseURL("https://sepolia.polynomialscan.io")),
    ])

    private static func validatedBaseURL(_ rawValue: String) -> URL {
        guard
            let url = URL(string: rawValue),
            url.scheme == "https",
            url.host?.isEmpty == false,
            url.path.isEmpty,
            url.query == nil,
            url.fragment == nil
        else {
            preconditionFailure("Invalid ExplorerCatalog base URL literal: \(rawValue)")
        }

        return url
    }
}
