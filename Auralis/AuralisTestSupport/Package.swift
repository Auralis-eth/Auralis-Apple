// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AuralisTestSupport",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "AuralisTestSupport",
            targets: ["AuralisTestSupport"]
        ),
    ],
    dependencies: [
        .package(path: "../AuralisFoundation"),
        .package(path: "../AuralisPrimaryModels"),
    ],
    targets: [
        .target(
            name: "AuralisTestSupport",
            dependencies: [
                .product(name: "AuralisFoundation", package: "AuralisFoundation"),
                "AuralisPrimaryModels",
                .product(name: "AuralisPrimaryPersistence", package: "AuralisPrimaryModels"),
            ]
        ),
    ]
)
