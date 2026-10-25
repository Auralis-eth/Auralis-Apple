// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ProviderKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "ProviderKit",
            targets: ["ProviderKit"]
        ),
        .library(
            name: "ChainProviders",
            targets: ["ChainProviders"]
        ),
        .library(
            name: "ExplorerAdapter",
            targets: ["ExplorerAdapter"]
        ),
        .library(
            name: "ENS",
            targets: ["ENS"]
        )
    ],
    dependencies: [
        .package(path: "../AuralisFoundation"),
        .package(path: "../AuralisPrimaryModels"),
        .package(path: "../AuralisTestSupport"),
        .package(url: "https://github.com/argentlabs/web3.swift", from: "1.6.1"),
        // web3.swift 1.6.1 still references the pre-rename `secp256k1` product.
        .package(url: "https://github.com/GigaBitcoin/secp256k1.swift.git", exact: "0.6.0")
    ],
    targets: [
        .target(
            name: "ProviderKit",
            dependencies: [
                .product(name: "AuralisFoundation", package: "AuralisFoundation"),
                "AuralisPrimaryModels",
                .product(name: "AuralisPrimaryPersistence", package: "AuralisPrimaryModels")
            ]
        ),
        .target(
            name: "ChainProviders",
            dependencies: [
                "AuralisPrimaryModels",
                "ProviderKit"
            ]
        ),
        .target(
            name: "ExplorerAdapter",
            dependencies: ["AuralisPrimaryModels"]
        ),
        .target(
            name: "ENS",
            dependencies: [
                "AuralisPrimaryModels",
                "ProviderKit",
                .product(name: "web3.swift", package: "web3.swift")
            ]
        ),
        .testTarget(
            name: "ProviderKitTests",
            dependencies: [
                "ProviderKit",
                "AuralisTestSupport"
            ]
        ),
        .testTarget(
            name: "ChainProvidersTests",
            dependencies: [
                "AuralisPrimaryModels",
                "ChainProviders",
                "ProviderKit",
                "AuralisTestSupport"
            ]
        ),
        .testTarget(
            name: "ExplorerAdapterTests",
            dependencies: ["ExplorerAdapter"]
        ),
        .testTarget(
            name: "ENSTests",
            dependencies: [
                "ENS",
                "AuralisTestSupport"
            ]
        )
    ]
)
