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
        .library(name: "WalletConnectorKit", targets: ["WalletConnectorKit"]),
        .library(name: "WalletConnectorKitReownAdapter", targets: ["WalletConnectorKitReownAdapter"]),
        .library(name: "WalletConnectorKitCoinbaseAdapter", targets: ["WalletConnectorKitCoinbaseAdapter"]),
        .library(name: "WalletConnectorKitMetaMaskAdapter", targets: ["WalletConnectorKitMetaMaskAdapter"]),
        .library(name: "WalletConnectorKitPrivyAdapter", targets: ["WalletConnectorKitPrivyAdapter"]),
        .library(name: "WalletConnectorKitDynamicAdapter", targets: ["WalletConnectorKitDynamicAdapter"]),
        .library(name: "WalletConnectorKitSolanaAdapter", targets: ["WalletConnectorKitSolanaAdapter"])
    ],
    dependencies: [
        .package(path: "../AuralisPrimaryModels"),
        .package(path: "../ReceiptsCore"),
        .package(path: "../AuralisFoundation"),
        .package(path: "../ProviderKit"),
        .package(path: "../NFTKit"),
        .package(path: "../AuraUI"),
        .package(path: "../CodeScanner"),
        .package(url: "https://github.com/reown-com/reown-swift", .upToNextMajor(from: "2.3.0")),
        .package(url: "https://github.com/MobileWalletProtocol/wallet-mobile-sdk", .upToNextMajor(from: "1.1.2")),
        .package(url: "https://github.com/privy-io/privy-ios", .upToNextMajor(from: "2.14.0")),
        .package(url: "https://github.com/dynamic-labs/swift-sdk-and-sample-app", .upToNextMajor(from: "1.2.0")),
        // web3.swift 1.6.1 still names the pre-rename secp256k1 product.
        .package(url: "https://github.com/GigaBitcoin/secp256k1.swift.git", exact: "0.6.0")
    ],
    targets: [
        .target(
            name: "AccountsCore",
            dependencies: [
                "AuralisPrimaryModels",
                .product(name: "AuralisPrimaryPersistence", package: "AuralisPrimaryModels")
            ]
        ),
        .target(
            name: "AccountStorage",
            dependencies: [
                "AuralisPrimaryModels",
                .product(name: "AuralisPrimaryPersistence", package: "AuralisPrimaryModels"),
                "AccountsCore",
                .product(name: "ReceiptStorage", package: "ReceiptsCore"),
                .product(name: "SwiftDataAdapters", package: "AuralisFoundation"),
                "TokenStorage",
                .product(name: "NFTPersistence", package: "NFTKit")
            ]
        ),
        .target(
            name: "TokenStorage",
            dependencies: [
                "AuralisPrimaryModels",
                .product(name: "AuralisPrimaryPersistence", package: "AuralisPrimaryModels"),
                "ProviderKit",
                .product(name: "SwiftDataAdapters", package: "AuralisFoundation")
            ]
        ),
        .target(
            name: "AccountsFeature",
            dependencies: [
                "AccountsCore",
                "AuralisPrimaryModels",
                .product(name: "AuralisPrimaryPersistence", package: "AuralisPrimaryModels"),
                "AuraUI",
                .product(name: "CodeScanner", package: "CodeScanner")
            ],
            sources: [
                "Domain",
                "Presentation",
                "Support"
            ]
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
            dependencies: ["AccountsCore"]
        ),
        .testTarget(
            name: "AccountStorageTests",
            dependencies: [
                "AccountStorage",
                .product(name: "AuralisPrimaryPersistence", package: "AuralisPrimaryModels")
            ]
        ),
        .testTarget(
            name: "TokenStorageTests",
            dependencies: [
                "AuralisPrimaryModels",
                .product(name: "AuralisPrimaryPersistence", package: "AuralisPrimaryModels"),
                "ProviderKit",
                "TokenStorage"
            ]
        ),
        .testTarget(
            name: "AccountsFeatureTests",
            dependencies: [
                "AccountsFeature",
                "AuralisPrimaryModels",
                .product(name: "AuralisPrimaryPersistence", package: "AuralisPrimaryModels")
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
        )
    ]
)
