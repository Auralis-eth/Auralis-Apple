// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AuralisCrypto",
    platforms: [
        // AccountsUI imports AuraUI, whose supported platform floor is OS 26.
        // SwiftPM platform declarations apply to the complete package, not individual targets.
        .iOS("26.0"),
        .macOS("26.0")
    ],
    products: [
        .library(name: "AuralisCrypto", targets: ["AuralisCrypto"]),
        // The vendor wallet adapters stay a separate module on purpose. SwiftPM conditions
        // *dependencies* per platform but not *source files*, so folding the iOS-only adapter
        // sources into AuralisCrypto would compile them on macOS against SDKs that are not linked
        // there. Keeping them apart also stops every consumer of a plain `Chain` or `EOAccount`
        // from linking five wallet SDKs.
        .library(name: "WalletAdapters", targets: ["WalletAdapters"]),
        // Fixture-only. Vended because AuralisOperators' tests build NFT values with it; it must
        // not be linked into production, which is why it is not folded into AuralisCrypto.
        .library(name: "AuralisCryptoTestSupport", targets: ["AuralisCryptoTestSupport"])
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
        // web3.swift 1.6.1 still names the pre-rename secp256k1 product.
        .package(url: "https://github.com/GigaBitcoin/secp256k1.swift.git", exact: "0.6.0")
    ],
    targets: [
        .target(
            name: "AuralisCrypto",
            dependencies: [
                .product(name: "AuralisFoundation", package: "AuralisFoundation"),
                .product(name: "AuralisRuntime", package: "AuralisRuntime"),
                .product(name: "AuralisReceipts", package: "AuralisReceipts"),
                .product(name: "web3.swift", package: "web3.swift"),
                "AuraUI",
                .product(name: "CodeScanner", package: "CodeScanner")
            ]
        ),
        .target(
            name: "WalletAdapters",
            dependencies: [
                .product(name: "ReownAppKit", package: "reown-swift", condition: .when(platforms: [.iOS])),
                .product(name: "CoinbaseWalletSDK", package: "wallet-mobile-sdk", condition: .when(platforms: [.iOS])),
                .product(name: "Privy", package: "privy-ios", condition: .when(platforms: [.iOS])),
                .product(name: "DynamicSDKSwift", package: "swift-sdk-and-sample-app", condition: .when(platforms: [.iOS]))
            ]
        ),
        .target(
            name: "AuralisCryptoTestSupport",
            dependencies: [
                "AuralisCrypto",
                .product(name: "AuralisFoundation", package: "AuralisFoundation")
            ]
        ),
        .testTarget(
            name: "AuralisCryptoTests",
            dependencies: [
                "AuralisCrypto",
                "WalletAdapters",
                "AuralisCryptoTestSupport",
                .product(name: "AuralisFoundation", package: "AuralisFoundation"),
                .product(name: "AuralisRuntime", package: "AuralisRuntime"),
                .product(name: "AuralisReceipts", package: "AuralisReceipts"),
                .product(name: "AuralisTestSupport", package: "AuralisTestSupport")
            ]
        )
    ]
)
