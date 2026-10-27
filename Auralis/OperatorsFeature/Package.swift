// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OperatorsFeature",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0")
    ],
    products: [
        .library(
            name: "OperatorsFeature",
            targets: ["OperatorsFeature"]
        ),
        .library(
            name: "SocialCore",
            targets: ["SocialCore"]
        ),
        .library(
            name: "OperatorCore",
            targets: ["OperatorCore"]
        ),
        .library(
            name: "NFTLibraryFeature",
            targets: ["NFTLibraryFeature"]
        ),
        .library(
            name: "MusicFeature",
            targets: ["MusicFeature"]
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
        // web3.swift 1.6.1 still references the pre-rename `secp256k1` product.,
        .package(url: "https://github.com/GigaBitcoin/secp256k1.swift.git", exact: "0.6.0")
    ],
    targets: [
        .target(
            name: "OperatorsFeature",
            dependencies: [
                .product(name: "AccountsCore", package: "AccountsCore"),
                .product(name: "AuralisRuntime", package: "AuralisRuntime"),
                .product(name: "AuralisReceipts", package: "AuralisReceipts")
            ]
        ),
        .target(
            name: "SocialCore",
            dependencies: [
                .product(name: "AuralisPrimaryModels", package: "AccountsCore"),
                .product(name: "AuralisRuntime", package: "AuralisRuntime")
            ]
        ),
        .target(
            name: "OperatorCore",
            dependencies: [
                .product(name: "AuralisPrimaryModels", package: "AccountsCore"),
                .product(name: "AuralisReceipts", package: "AuralisReceipts")
            ]
        ),
        .target(
            name: "NFTLibraryFeature",
            dependencies: [
                .product(name: "AuralisPrimaryModels", package: "AccountsCore"),
                .product(name: "AuralisPrimaryPersistence", package: "AccountsCore"),
                "AuraUI",
                .product(name: "NFTKit", package: "AccountsCore"),
                "OperatorCore",
                .product(name: "ExplorerAdapter", package: "AccountsCore")
            ]
        ),
        .target(
            name: "MusicFeature",
            dependencies: [
                .product(name: "AuralisPrimaryModels", package: "AccountsCore"),
                .product(name: "AuralisPrimaryPersistence", package: "AccountsCore"),
                .product(name: "AuraPlayMediaCore", package: "AuraPlayEngines"),
                "AuraUI",
                .product(name: "AuralisFoundation", package: "AuralisFoundation"),
                .product(name: "AuralisReceipts", package: "AuralisReceipts")
            ]
        ),
        .testTarget(
            name: "OperatorsFeatureTests",
            dependencies: [
                .product(name: "AccountsCore", package: "AccountsCore"),
                "OperatorsFeature"
            ]
        ),
        .testTarget(
            name: "SocialCoreTests",
            dependencies: ["SocialCore"]
        ),
        .testTarget(
            name: "OperatorCoreTests",
            dependencies: [
                "OperatorCore",
                .product(name: "AuralisReceipts", package: "AuralisReceipts")
            ]
        ),
        .testTarget(
            name: "NFTLibraryFeatureTests",
            dependencies: [
                "NFTLibraryFeature",
                "AuralisTestSupport",
                "OperatorCore",
                .product(name: "ExplorerAdapter", package: "AccountsCore")
            ]
        ),
        .testTarget(
            name: "MusicFeatureTests",
            dependencies: [
                "MusicFeature",
                "AuralisTestSupport",
                .product(name: "AuralisPrimaryPersistence", package: "AccountsCore"),
                .product(name: "PrimaryModelsTestSupport", package: "AccountsCore"),
                .product(name: "AuralisReceipts", package: "AuralisReceipts")
            ],
            exclude: ["__Snapshots__"]
        )
    ]
)
