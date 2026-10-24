// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MusicFeature",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0")
    ],
    products: [
        .library(
            name: "MusicFeature",
            targets: ["MusicFeature"]
        )
    ],
    dependencies: [
        .package(path: "../AuralisPrimaryModels"),
        .package(path: "../AuralisTestSupport"),
        .package(path: "../AuraPlayEngines"),
        .package(path: "../AuraUI"),
        .package(path: "../AuralisFoundation"),
        .package(path: "../ReceiptsCore")
    ],
    targets: [
        .target(
            name: "MusicFeature",
            dependencies: [
                "AuralisPrimaryModels",
                .product(name: "AuralisPrimaryPersistence", package: "AuralisPrimaryModels"),
                .product(name: "AuraPlayMediaCore", package: "AuraPlayEngines"),
                "AuraUI",
                .product(name: "AuralisFoundation", package: "AuralisFoundation"),
                .product(name: "CapabilitiesCore", package: "AuralisFoundation"),
                .product(name: "SwiftDataAdapters", package: "AuralisFoundation"),
                "ReceiptsCore"
            ]
        ),
        .testTarget(
            name: "MusicFeatureTests",
            dependencies: [
                "MusicFeature",
                "AuralisTestSupport",
                .product(name: "AuralisPrimaryPersistence", package: "AuralisPrimaryModels"),
                .product(name: "ReceiptStorage", package: "ReceiptsCore")
            ],
            exclude: ["__Snapshots__"]
        )
    ]
)
