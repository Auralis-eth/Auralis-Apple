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
        ),
        .library(
            name: "SocialCore",
            targets: ["SocialCore"]
        )
    ],
    dependencies: [
        .package(path: "../RuntimeCore"),
        .package(path: "../AuralisPrimaryModels"),
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
        .target(
            name: "SocialCore",
            dependencies: [
                "AuralisPrimaryModels",
                "RuntimeCore",
                .product(name: "PlaybookCore", package: "RuntimeCore")
            ]
        ),
        .testTarget(
            name: "OperatorsFeatureTests",
            dependencies: ["OperatorsFeature"]
        ),
        .testTarget(
            name: "SocialCoreTests",
            dependencies: ["SocialCore"]
        )
    ]
)
