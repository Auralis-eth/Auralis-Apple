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
        .package(path: "../ENS"),
        .package(url: "https://github.com/GigaBitcoin/secp256k1.swift.git", exact: "0.6.0"),
    ],
    targets: [
        .target(
            name: "AgentIdentityCore",
            dependencies: [
                "ENS",
            ]
        ),
    ]
)
