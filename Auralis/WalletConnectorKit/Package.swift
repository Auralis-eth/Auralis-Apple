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
        // Coinbase Mobile Wallet Protocol SDK backing the live Coinbase adapter.
        .package(url: "https://github.com/MobileWalletProtocol/wallet-mobile-sdk", .upToNextMajor(from: "1.1.2")),
        // Privy embedded-wallet SDK (binary XCFramework distribution) backing the
        // live Privy adapter.
        .package(url: "https://github.com/privy-io/privy-ios", .upToNextMajor(from: "2.14.0")),
        // Dynamic embedded-wallet SDK backing the live Dynamic adapter.
        .package(url: "https://github.com/dynamic-labs/swift-sdk-and-sample-app", .upToNextMajor(from: "1.2.0")),
        // NOTE: The MetaMask and Solana adapters still ship only protocol shims +
        // `Unconfigured…` stubs; neither links a vendor SDK. MetaMask's native iOS
        // SDK (metamask-ios-sdk) was archived read-only on 2026-02-26, and Solana
        // has no native-Swift SPM Mobile Wallet Adapter SDK for dApps — route both
        // through WalletConnect/Reown instead.
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
                "WalletConnectorKitSolanaAdapter",
            ]
        ),
    ]
)
