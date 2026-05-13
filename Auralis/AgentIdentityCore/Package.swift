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
