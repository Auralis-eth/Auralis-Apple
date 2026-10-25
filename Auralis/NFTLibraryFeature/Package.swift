// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "NFTLibraryFeature",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0"),
    ],
    products: [
        .library(
            name: "NFTLibraryFeature",
            targets: ["NFTLibraryFeature"]
        ),
    ],
    dependencies: [
        .package(path: "../AuralisPrimaryModels"),
        .package(path: "../AuraUI"),
        .package(path: "../NFTKit"),
        .package(path: "../OperatorsFeature"),
        .package(path: "../ProviderKit"),
        .package(path: "../AuralisTestSupport"),
        // web3.swift 1.6.1 still references the pre-rename `secp256k1` product.
        // Keep the compatible product version visible at this graph root because
        // target-based dependency resolution prunes ProviderKit's unused ENS edge.
        .package(url: "https://github.com/GigaBitcoin/secp256k1.swift.git", exact: "0.6.0"),
    ],
    targets: [
        .target(
            name: "NFTLibraryFeature",
            dependencies: [
                "AuralisPrimaryModels",
                .product(name: "AuralisPrimaryPersistence", package: "AuralisPrimaryModels"),
                "AuraUI",
                "NFTKit",
                .product(name: "OperatorCore", package: "OperatorsFeature"),
                .product(name: "ExplorerAdapter", package: "ProviderKit"),
            ]
        ),
        .testTarget(
            name: "NFTLibraryFeatureTests",
            dependencies: [
                "NFTLibraryFeature",
                "AuralisTestSupport",
                // The external-link policy tests validate URLs the builders produce against the
                // narrowed policies, so they need both the policy types and the builders directly.
                .product(name: "OperatorCore", package: "OperatorsFeature"),
                .product(name: "ExplorerAdapter", package: "ProviderKit"),
            ]
        ),
    ]
)
