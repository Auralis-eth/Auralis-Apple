// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MusicFeature",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0"),
    ],
    products: [
        .library(
            name: "MusicFeature",
            targets: ["MusicFeature"]
        ),
    ],
    dependencies: [
        .package(path: "../AuralisPrimaryModels"),
        .package(path: "../AuraUI"),
        .package(path: "../CapabilitiesCore"),
        .package(path: "../ReceiptStorage"),
        .package(path: "../ReceiptsCore"),
    ],
    targets: [
        .target(
            name: "MusicFeature",
            dependencies: [
                "AuralisPrimaryModels",
                .product(name: "AuralisPrimaryPersistence", package: "AuralisPrimaryModels"),
                "AuraUI",
                "CapabilitiesCore",
                "ReceiptsCore",
            ]
        ),
        .testTarget(
            name: "MusicFeatureTests",
            dependencies: [
                "MusicFeature",
                .product(name: "AuralisPrimaryPersistence", package: "AuralisPrimaryModels"),
                "ReceiptStorage",
            ]
        ),
    ]
)
