// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AccountsFeature",
    platforms: [
        .iOS(.v18),
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
        .package(path: "../CodeScanner"),
    ],
    targets: [
        .target(
            name: "AccountsFeature",
            dependencies: [
                "AccountsCore",
                "AuralisPrimaryModels",
                "AuraUI",
                "CodeScanner",
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
            ]
        ),
    ]
)
