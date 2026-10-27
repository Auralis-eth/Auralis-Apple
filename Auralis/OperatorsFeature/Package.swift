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
        .package(path: "../RuntimeCore"),
        .package(path: "../ReceiptsCore"),
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
                "RuntimeCore",
                .product(name: "OperatorRegistry", package: "RuntimeCore"),
                .product(name: "ArtifactCore", package: "ReceiptsCore")
            ]
        ),
        .target(
            name: "SocialCore",
            dependencies: [
                .product(name: "AuralisPrimaryModels", package: "AccountsCore"),
                "RuntimeCore",
                .product(name: "PlaybookCore", package: "RuntimeCore")
            ]
        ),
        .target(
            name: "OperatorCore",
            dependencies: [
                .product(name: "AuralisPrimaryModels", package: "AccountsCore"),
                "ReceiptsCore"
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
                "ReceiptsCore"
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
                "ReceiptsCore"
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
                .product(name: "ReceiptStorage", package: "ReceiptsCore")
            ],
            exclude: ["__Snapshots__"]
        )
    ]
)
