// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "NFTLibraryFeature",
    platforms: [
        .iOS(.v18),
    ],
    products: [
        .library(
            name: "NFTLibraryFeature",
            targets: ["NFTLibraryFeature"]
        ),
    ],
    dependencies: [
        .package(path: "../AuralisPrimaryModels"),
        .package(path: "../AuraUI"),
        .package(path: "../NFTKit"),
        .package(path: "../OperatorCore"),
        .package(path: "../ExplorerAdapter"),
    ],
    targets: [
        .target(
            name: "NFTLibraryFeature",
            dependencies: [
                "AuralisPrimaryModels",
                "AuraUI",
                "NFTKit",
                "OperatorCore",
                "ExplorerAdapter",
            ]
        ),
        .testTarget(
            name: "NFTLibraryFeatureTests",
            dependencies: ["NFTLibraryFeature"]
        ),
    ]
)
