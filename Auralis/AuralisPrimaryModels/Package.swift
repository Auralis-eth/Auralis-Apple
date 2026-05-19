// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AuralisPrimaryModels",
    platforms: [
        .iOS(.v18),
    ],
    products: [
        .library(
            name: "AuralisPrimaryModels",
            targets: [
                "AuralisPrimaryModels",
                "AuralisPrimaryPersistence",
            ]
        ),
        .library(
            name: "AuralisPrimaryPersistence",
            targets: ["AuralisPrimaryPersistence"]
        ),
    ],
    targets: [
        .target(
            name: "AuralisPrimaryModels"
        ),
        .target(
            name: "AuralisPrimaryPersistence",
            dependencies: ["AuralisPrimaryModels"]
        ),
    ]
)
