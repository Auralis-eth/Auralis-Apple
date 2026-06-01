// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "NFTLibraryFeature",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0"),
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
        .package(path: "../AuralisTestSupport"),
    ],
    targets: [
        .target(
            name: "NFTLibraryFeature",
            dependencies: [
                "AuralisPrimaryModels",
                .product(name: "AuralisPrimaryPersistence", package: "AuralisPrimaryModels"),
                "AuraUI",
                "NFTKit",
                "OperatorCore",
                "ExplorerAdapter",
            ]
        ),
        .testTarget(
            name: "NFTLibraryFeatureTests",
            dependencies: [
                "NFTLibraryFeature",
                "AuralisTestSupport",
            ]
        ),
    ]
)
