// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AuralisPrimaryModels",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "AuralisPrimaryModels",
            targets: [
                "AuralisPrimaryModels",
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
        .testTarget(
            name: "AuralisPrimaryModelsTests",
            dependencies: [
                "AuralisPrimaryModels",
                "AuralisPrimaryPersistence",
            ]
        ),
    ]
)
