// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AccountsCore",
    platforms: [
        .iOS(.v18),
    ],
    products: [
        .library(
            name: "AccountsCore",
            targets: ["AccountsCore"]
        ),
    ],
    dependencies: [
        .package(path: "../AuralisPrimaryModels"),
    ],
    targets: [
        .target(
            name: "AccountsCore",
            dependencies: [
                "AuralisPrimaryModels",
                .product(name: "AuralisPrimaryPersistence", package: "AuralisPrimaryModels"),
            ]
        ),
    ]
)
