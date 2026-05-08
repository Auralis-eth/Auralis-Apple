// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AgentIdentityCore",
    platforms: [
        .iOS(.v18),
    ],
    products: [
        .library(
            name: "AgentIdentityCore",
            targets: ["AgentIdentityCore"]
        ),
    ],
    dependencies: [
        .package(path: "../AuralisPrimaryModels"),
        .package(url: "https://github.com/argentlabs/web3.swift", from: "1.6.1"),
    ],
    targets: [
        .target(
            name: "AgentIdentityCore",
            dependencies: [
                "AuralisPrimaryModels",
                .product(name: "web3.swift", package: "web3.swift"),
            ]
        ),
    ]
)
