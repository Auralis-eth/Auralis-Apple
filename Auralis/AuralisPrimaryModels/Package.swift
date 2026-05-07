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
            targets: ["AuralisPrimaryModels"]
        ),
    ],
    targets: [
        .target(
            name: "AuralisPrimaryModels"
        ),
    ]
)
