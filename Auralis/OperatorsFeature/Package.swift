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
        .package(path: "../ReceiptsCore")
    ],
    targets: [
        .target(
            name: "OperatorsFeature",
            dependencies: [
                "RuntimeCore",
                .product(name: "ArtifactCore", package: "ReceiptsCore")
            ]
        ),
        .testTarget(
            name: "OperatorsFeatureTests",
            dependencies: ["OperatorsFeature"]
        )
    ]
)
