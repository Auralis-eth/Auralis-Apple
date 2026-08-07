// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WalletConnectorKit",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0"),
    ],
    products: [
        .library(
            name: "WalletConnectorKit",
            targets: ["WalletConnectorKit"]
        ),
        .library(
            name: "WalletConnectorKitReownAdapter",
            targets: ["WalletConnectorKitReownAdapter"]
        ),
        .library(
            name: "WalletConnectorKitCoinbaseAdapter",
            targets: ["WalletConnectorKitCoinbaseAdapter"]
        ),
        .library(
            name: "WalletConnectorKitMetaMaskAdapter",
            targets: ["WalletConnectorKitMetaMaskAdapter"]
        ),
        .library(
            name: "WalletConnectorKitPrivyAdapter",
            targets: ["WalletConnectorKitPrivyAdapter"]
        ),
        .library(
            name: "WalletConnectorKitDynamicAdapter",
            targets: ["WalletConnectorKitDynamicAdapter"]
        ),
        .library(
            name: "WalletConnectorKitSolanaAdapter",
            targets: ["WalletConnectorKitSolanaAdapter"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/reown-com/reown-swift", .upToNextMajor(from: "2.3.0")),
        .package(url: "https://github.com/MobileWalletProtocol/wallet-mobile-sdk", .upToNextMajor(from: "1.1.2")),
        .package(url: "https://github.com/MetaMask/metamask-ios-sdk", branch: "main"),
        .package(url: "https://github.com/privy-io/privy-ios", .upToNextMajor(from: "2.14.0")),
        .package(url: "https://github.com/dynamic-labs-oss/swift-sdk-and-sample-app", .upToNextMajor(from: "1.0.11")),
        .package(url: "https://github.com/p2p-org/solana-swift", .upToNextMajor(from: "5.0.0")),
    ],
    targets: [
        .target(
            name: "WalletConnectorKit"
        ),
        .target(
            name: "WalletConnectorKitReownAdapter",
            dependencies: [
                "WalletConnectorKit",
                .product(name: "ReownAppKit", package: "reown-swift", condition: .when(platforms: [.iOS])),
            ]
        ),
        .target(
            name: "WalletConnectorKitCoinbaseAdapter",
            dependencies: [
                "WalletConnectorKit",
                .product(name: "CoinbaseWalletSDK", package: "wallet-mobile-sdk", condition: .when(platforms: [.iOS])),
            ]
        ),
        .target(
            name: "WalletConnectorKitMetaMaskAdapter",
            dependencies: [
                "WalletConnectorKit",
                .product(name: "metamask-ios-sdk", package: "metamask-ios-sdk", condition: .when(platforms: [.iOS])),
            ]
        ),
        .target(
            name: "WalletConnectorKitPrivyAdapter",
            dependencies: [
                "WalletConnectorKit",
                .product(name: "Privy", package: "privy-ios", condition: .when(platforms: [.iOS])),
            ]
        ),
        .target(
            name: "WalletConnectorKitDynamicAdapter",
            dependencies: [
                "WalletConnectorKit",
                .product(name: "DynamicSDKSwift", package: "swift-sdk-and-sample-app", condition: .when(platforms: [.iOS])),
            ]
        ),
        .target(
            name: "WalletConnectorKitSolanaAdapter",
            dependencies: [
                "WalletConnectorKit",
                .product(name: "SolanaSwift", package: "solana-swift", condition: .when(platforms: [.iOS])),
            ]
        ),
        .testTarget(
            name: "WalletConnectorKitTests",
            dependencies: [
                "WalletConnectorKit",
            ]
        ),
    ]
)
