// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AuralisOperators",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0")
    ],
    products: [
        .library(
            name: "AuralisOperators",
            targets: ["AuralisOperators"]
        )
    ],
    dependencies: [
        .package(path: "../AuralisRuntime"),
        .package(path: "../AuralisReceipts"),
        .package(path: "../AuraUI"),
        .package(path: "../AccountsCore"),
        .package(path: "../AuralisTestSupport"),
        .package(path: "../AuraPlayEngines"),
        .package(path: "../AuralisFoundation"),
        // web3.swift 1.6.1 still references the pre-rename `secp256k1` product.
        .package(url: "https://github.com/GigaBitcoin/secp256k1.swift.git", exact: "0.6.0")
    ],
    targets: [
        .target(
            name: "AuralisOperators",
            dependencies: [
                .product(name: "AccountsCore", package: "AccountsCore"),
                .product(name: "AuralisPrimaryModels", package: "AccountsCore"),
                .product(name: "AuralisPrimaryPersistence", package: "AccountsCore"),
                .product(name: "NFTKit", package: "AccountsCore"),
                .product(name: "ExplorerAdapter", package: "AccountsCore"),
                .product(name: "AuraPlayMediaCore", package: "AuraPlayEngines"),
                .product(name: "AuralisFoundation", package: "AuralisFoundation"),
                .product(name: "AuralisRuntime", package: "AuralisRuntime"),
                .product(name: "AuralisReceipts", package: "AuralisReceipts"),
                "AuraUI"
            ]
        ),
        .testTarget(
            name: "AuralisOperatorsTests",
            dependencies: [
                "AuralisOperators",
                "AuralisTestSupport",
                .product(name: "AccountsCore", package: "AccountsCore"),
                .product(name: "AuralisPrimaryPersistence", package: "AccountsCore"),
                .product(name: "PrimaryModelsTestSupport", package: "AccountsCore"),
                .product(name: "ExplorerAdapter", package: "AccountsCore"),
                .product(name: "AuralisReceipts", package: "AuralisReceipts")
            ],
            // Baselines live beside the suite that records them, so the path moved with the
            // test sources into the merged target.
            exclude: ["Music/__Snapshots__"]
        )
    ]
)
