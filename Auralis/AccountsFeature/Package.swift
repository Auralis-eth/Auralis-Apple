// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AccountsFeature",
    platforms: [
        .iOS(.v18),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "AccountsFeature",
            targets: ["AccountsFeature"]
        ),
    ],
    dependencies: [
        .package(path: "../AccountsCore"),
        .package(path: "../AuralisPrimaryModels"),
        .package(path: "../AuraUI"),
        .package(url: "https://github.com/twoStraws/CodeScanner", from: "2.5.2"),
    ],
    targets: [
        .target(
            name: "AccountsFeature",
            dependencies: [
                "AccountsCore",
                "AuralisPrimaryModels",
                .product(name: "AuralisPrimaryPersistence", package: "AuralisPrimaryModels"),
                "AuraUI",
                .product(name: "CodeScanner", package: "CodeScanner"),
            ],
            sources: [
                "Domain",
                "Presentation",
                "Support"
            ]
        ),
        .testTarget(
            name: "AccountsFeatureTests",
            dependencies: [
                "AccountsFeature",
                "AuralisPrimaryModels",
                .product(name: "AuralisPrimaryPersistence", package: "AuralisPrimaryModels"),
            ]
        ),
    ]
)
