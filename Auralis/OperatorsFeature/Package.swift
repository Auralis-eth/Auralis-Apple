// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OperatorsFeature",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "OperatorsFeature",
            targets: ["OperatorsFeature"]
        )
    ],
    dependencies: [
        .package(path: "../RuntimeCore"),
        .package(path: "../ArtifactCore")
    ],
    targets: [
        .target(
            name: "OperatorsFeature",
            dependencies: [
                "RuntimeCore",
                "ArtifactCore"
            ]
        ),
        .testTarget(
            name: "OperatorsFeatureTests",
            dependencies: ["OperatorsFeature"]
        )
    ]
)
