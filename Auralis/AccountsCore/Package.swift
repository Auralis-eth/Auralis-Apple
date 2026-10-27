// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AccountsCore",
    platforms: [
        // AccountsFeature imports AuraUI, whose supported platform floor is OS 26.
        // SwiftPM platform declarations apply to the complete package, not individual targets.
        .iOS("26.0"),
        .macOS("26.0")
    ],
    products: [
        .library(name: "AuralisPrimaryModels", targets: ["AuralisPrimaryModels"]),
        .library(name: "AuralisPrimaryPersistence", targets: ["AuralisPrimaryPersistence"]),
        .library(name: "PrimaryModelsTestSupport", targets: ["PrimaryModelsTestSupport"]),
        .library(
            name: "AccountsCore",
            targets: ["AccountsCore"]
        ),
        .library(
            name: "AccountStorage",
            targets: ["AccountStorage"]
        ),
        .library(
            name: "TokenStorage",
            targets: ["TokenStorage"]
        ),
        .library(
            name: "AccountsFeature",
            targets: ["AccountsFeature"]
        ),
        .library(name: "ProviderKit", targets: ["ProviderKit"]),
        .library(name: "ChainProviders", targets: ["ChainProviders"]),
        .library(name: "ExplorerAdapter", targets: ["ExplorerAdapter"]),
        .library(name: "ENS", targets: ["ENS"]),
        .library(name: "NFTKit", targets: ["NFTKit"]),
        .library(name: "NFTDomain", targets: ["NFTDomain"]),
        .library(name: "NFTProviderAdapters", targets: ["NFTProviderAdapters"]),
        .library(name: "NFTPersistence", targets: ["NFTPersistence"]),
        .library(name: "NFTPresentation", targets: ["NFTPresentation"]),
        .library(name: "WalletConnectorKit", targets: ["WalletConnectorKit"]),
        .library(name: "WalletConnectorKitReownAdapter", targets: ["WalletConnectorKitReownAdapter"]),
        .library(name: "WalletConnectorKitCoinbaseAdapter", targets: ["WalletConnectorKitCoinbaseAdapter"]),
        .library(name: "WalletConnectorKitMetaMaskAdapter", targets: ["WalletConnectorKitMetaMaskAdapter"]),
        .library(name: "WalletConnectorKitPrivyAdapter", targets: ["WalletConnectorKitPrivyAdapter"]),
        .library(name: "WalletConnectorKitDynamicAdapter", targets: ["WalletConnectorKitDynamicAdapter"]),
        .library(name: "WalletConnectorKitSolanaAdapter", targets: ["WalletConnectorKitSolanaAdapter"])
    ],
    dependencies: [
        .package(path: "../AuralisReceipts"),
        .package(path: "../AuralisRuntime"),
        .package(path: "../AuralisFoundation"),
        .package(path: "../AuralisTestSupport"),
        .package(path: "../AuraUI"),
        .package(path: "../CodeScanner"),
        .package(url: "https://github.com/reown-com/reown-swift", .upToNextMajor(from: "2.3.0")),
        .package(url: "https://github.com/MobileWalletProtocol/wallet-mobile-sdk", .upToNextMajor(from: "1.1.2")),
        .package(url: "https://github.com/privy-io/privy-ios", .upToNextMajor(from: "2.14.0")),
        .package(url: "https://github.com/dynamic-labs/swift-sdk-and-sample-app", .upToNextMajor(from: "1.2.0")),
        .package(url: "https://github.com/argentlabs/web3.swift", from: "1.6.1"),
        // web3.swift 1.6.1 still names the pre-rename secp256k1 product.,
        .package(url: "https://github.com/GigaBitcoin/secp256k1.swift.git", exact: "0.6.0")
    ],
    targets: [
        .target(name: "AuralisPrimaryModels"),
        .target(
            name: "AuralisPrimaryPersistence",
            dependencies: [
                .product(name: "AuralisFoundation", package: "AuralisFoundation"),
                "AuralisPrimaryModels"
            ]
        ),
        .target(
            name: "PrimaryModelsTestSupport",
            dependencies: [
                "AuralisPrimaryModels",
                "AuralisPrimaryPersistence",
                .product(name: "AuralisFoundation", package: "AuralisFoundation")
            ]
        ),
        .target(
            name: "AccountsCore",
            dependencies: [
                "AuralisPrimaryModels",
                "AuralisPrimaryPersistence",
                .product(name: "AuralisRuntime", package: "AuralisRuntime")
            ]
        ),
        .target(
            name: "AccountStorage",
            dependencies: [
                "AuralisPrimaryModels",
                "AuralisPrimaryPersistence",
                "AccountsCore",
                .product(name: "AuralisReceipts", package: "AuralisReceipts"),
                .product(name: "AuralisFoundation", package: "AuralisFoundation"),
                "TokenStorage",
                "NFTPersistence"
            ]
        ),
        .target(
            name: "TokenStorage",
            dependencies: [
                "AuralisPrimaryModels",
                "AuralisPrimaryPersistence",
                "ProviderKit",
                .product(name: "AuralisFoundation", package: "AuralisFoundation")
            ]
        ),
        .target(
            name: "AccountsFeature",
            dependencies: [
                "AccountsCore",
                "AuralisPrimaryModels",
                "AuralisPrimaryPersistence",
                "AuraUI",
                .product(name: "CodeScanner", package: "CodeScanner")
            ],
            sources: [
                "Domain",
                "Presentation",
                "Support"
            ]
        ),
        .target(
            name: "ProviderKit",
            dependencies: [
                .product(name: "AuralisFoundation", package: "AuralisFoundation"),
                "AuralisPrimaryModels",
                "AuralisPrimaryPersistence"
            ]
        ),
        .target(name: "ChainProviders", dependencies: ["AuralisPrimaryModels", "ProviderKit"]),
        .target(name: "ExplorerAdapter", dependencies: ["AuralisPrimaryModels"]),
        .target(
            name: "ENS",
            dependencies: [
                "AuralisPrimaryModels",
                "ProviderKit",
                .product(name: "web3.swift", package: "web3.swift")
            ]
        ),
        .target(
            name: "NFTDomain",
            dependencies: [
                .product(name: "AuralisFoundation", package: "AuralisFoundation"),
                "AuralisPrimaryModels"
            ]
        ),
        .target(
            name: "NFTProviderAdapters",
            dependencies: ["NFTDomain", "ChainProviders", "ExplorerAdapter", "ProviderKit"]
        ),
        .target(
            name: "NFTPersistence",
            dependencies: [
                .product(name: "AuralisFoundation", package: "AuralisFoundation"),
                "NFTDomain",
                "AuralisPrimaryPersistence",
                .product(name: "AuralisReceipts", package: "AuralisReceipts")
            ]
        ),
        .target(
            name: "NFTPresentation",
            dependencies: [
                .product(name: "AuralisFoundation", package: "AuralisFoundation"),
                "NFTDomain",
                "NFTProviderAdapters",
                "NFTPersistence",
                "AuralisPrimaryPersistence"
            ]
        ),
        .target(
            name: "NFTKit",
            dependencies: ["NFTDomain", "NFTProviderAdapters", "NFTPersistence", "NFTPresentation"]
        ),
        .target(name: "WalletConnectorKit"),
        .target(
            name: "WalletConnectorKitReownAdapter",
            dependencies: [
                "WalletConnectorKit",
                .product(name: "ReownAppKit", package: "reown-swift", condition: .when(platforms: [.iOS]))
            ]
        ),
        .target(
            name: "WalletConnectorKitCoinbaseAdapter",
            dependencies: [
                "WalletConnectorKit",
                .product(name: "CoinbaseWalletSDK", package: "wallet-mobile-sdk", condition: .when(platforms: [.iOS]))
            ]
        ),
        .target(name: "WalletConnectorKitMetaMaskAdapter", dependencies: ["WalletConnectorKit"]),
        .target(
            name: "WalletConnectorKitPrivyAdapter",
            dependencies: [
                "WalletConnectorKit",
                .product(name: "Privy", package: "privy-ios", condition: .when(platforms: [.iOS]))
            ]
        ),
        .target(
            name: "WalletConnectorKitDynamicAdapter",
            dependencies: [
                "WalletConnectorKit",
                .product(name: "DynamicSDKSwift", package: "swift-sdk-and-sample-app", condition: .when(platforms: [.iOS]))
            ]
        ),
        .target(name: "WalletConnectorKitSolanaAdapter", dependencies: ["WalletConnectorKit"]),
        .testTarget(
            name: "AccountsCoreTests",
            dependencies: [
                "AccountsCore",
                .product(name: "AuralisFoundation", package: "AuralisFoundation"),
                .product(name: "AuralisRuntime", package: "AuralisRuntime")
            ]
        ),
        .testTarget(
            name: "AccountStorageTests",
            dependencies: [
                "AccountStorage",
                "AuralisPrimaryPersistence"
            ]
        ),
        .testTarget(
            name: "TokenStorageTests",
            dependencies: [
                "AuralisPrimaryModels",
                "AuralisPrimaryPersistence",
                "ProviderKit",
                "TokenStorage"
            ]
        ),
        .testTarget(
            name: "AccountsFeatureTests",
            dependencies: [
                "AccountsFeature",
                "AuralisPrimaryModels",
                "AuralisPrimaryPersistence"
            ]
        ),
        .testTarget(name: "ProviderKitTests", dependencies: ["ProviderKit", "AuralisTestSupport"]),
        .testTarget(
            name: "ChainProvidersTests",
            dependencies: ["AuralisPrimaryModels", "ChainProviders", "ProviderKit", "AuralisTestSupport"]
        ),
        .testTarget(name: "ExplorerAdapterTests", dependencies: ["ExplorerAdapter"]),
        .testTarget(name: "ENSTests", dependencies: ["ENS", "AuralisTestSupport"]),
        .testTarget(
            name: "NFTKitTests",
            dependencies: [
                .product(name: "AuralisFoundation", package: "AuralisFoundation"),
                "AuralisPrimaryPersistence",
                "PrimaryModelsTestSupport",
                "AuralisTestSupport",
                "NFTDomain",
                "NFTKit",
                "NFTPersistence",
                "NFTPresentation",
                "NFTProviderAdapters",
                "ProviderKit",
                .product(name: "AuralisReceipts", package: "AuralisReceipts")
            ]
        ),
        .testTarget(
            name: "WalletConnectorKitTests",
            dependencies: [
                "WalletConnectorKit",
                "WalletConnectorKitReownAdapter",
                "WalletConnectorKitCoinbaseAdapter",
                "WalletConnectorKitMetaMaskAdapter",
                "WalletConnectorKitPrivyAdapter",
                "WalletConnectorKitDynamicAdapter",
                "WalletConnectorKitSolanaAdapter"
            ]
        ),
        .testTarget(
            name: "AuralisPrimaryModelsTests",
            dependencies: ["AuralisPrimaryModels", "AuralisPrimaryPersistence"]
        )
    ]
)
