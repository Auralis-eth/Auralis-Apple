// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ENS",
    platforms: [
        .iOS(.v18),
    ],
    products: [
        .library(
            name: "ENS",
            targets: ["ENS"]
        ),
    ],
    dependencies: [
        .package(path: "../AuralisPrimaryModels"),
        .package(path: "../ProviderKit"),
        .package(url: "https://github.com/argentlabs/web3.swift", from: "1.6.1"),
    ],
    targets: [
        .target(
            name: "ENS",
            dependencies: [
                "AuralisPrimaryModels",
                "ProviderKit",
                .product(name: "web3.swift", package: "web3.swift"),
            ]
        ),
        .testTarget(
            name: "ENSTests",
            dependencies: ["ENS"]
        ),
    ]
)
