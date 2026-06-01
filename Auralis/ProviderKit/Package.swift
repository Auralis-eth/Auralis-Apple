// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ProviderKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "ProviderKit",
            targets: ["ProviderKit"]
        ),
    ],
    dependencies: [
        .package(path: "../AuralisPrimaryModels"),
        .package(path: "../AuralisTestSupport"),
    ],
    targets: [
        .target(
            name: "ProviderKit",
            dependencies: [
                "AuralisPrimaryModels",
                .product(name: "AuralisPrimaryPersistence", package: "AuralisPrimaryModels"),
            ]
        ),
        .testTarget(
            name: "ProviderKitTests",
            dependencies: [
                "ProviderKit",
                "AuralisTestSupport",
            ]
        ),
    ]
)
