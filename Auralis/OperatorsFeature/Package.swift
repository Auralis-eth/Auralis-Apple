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
        )
    ],
    dependencies: [
        .package(path: "../RuntimeCore"),
        .package(path: "../AuralisPrimaryModels"),
        .package(path: "../ReceiptsCore"),
        .package(path: "../AuraUI"),
        .package(path: "../NFTKit"),
        .package(path: "../ProviderKit"),
        .package(path: "../AuralisTestSupport"),
        // web3.swift 1.6.1 still references the pre-rename `secp256k1` product.
        .package(url: "https://github.com/GigaBitcoin/secp256k1.swift.git", exact: "0.6.0")
    ],
    targets: [
        .target(
            name: "OperatorsFeature",
            dependencies: [
                "RuntimeCore",
                .product(name: "ArtifactCore", package: "ReceiptsCore")
            ]
        ),
        .target(
            name: "SocialCore",
            dependencies: [
                "AuralisPrimaryModels",
                "RuntimeCore",
                .product(name: "PlaybookCore", package: "RuntimeCore")
            ]
        ),
        .target(
            name: "OperatorCore",
            dependencies: [
                "AuralisPrimaryModels",
                "ReceiptsCore"
            ]
        ),
        .target(
            name: "NFTLibraryFeature",
            dependencies: [
                "AuralisPrimaryModels",
                .product(name: "AuralisPrimaryPersistence", package: "AuralisPrimaryModels"),
                "AuraUI",
                "NFTKit",
                "OperatorCore",
                .product(name: "ExplorerAdapter", package: "ProviderKit")
            ]
        ),
        .testTarget(
            name: "OperatorsFeatureTests",
            dependencies: ["OperatorsFeature"]
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
                .product(name: "ExplorerAdapter", package: "ProviderKit")
            ]
        )
    ]
)
