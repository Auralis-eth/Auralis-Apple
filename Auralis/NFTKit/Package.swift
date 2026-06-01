// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "NFTKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "NFTKit",
            targets: ["NFTKit"]
        ),
        .library(
            name: "NFTDomain",
            targets: ["NFTDomain"]
        ),
        .library(
            name: "NFTProviderAdapters",
            targets: ["NFTProviderAdapters"]
        ),
        .library(
            name: "NFTPersistence",
            targets: ["NFTPersistence"]
        ),
        .library(
            name: "NFTPresentation",
            targets: ["NFTPresentation"]
        ),
    ],
    dependencies: [
        .package(path: "../AuralisPrimaryModels"),
        .package(path: "../ChainProviders"),
        .package(path: "../ExplorerAdapter"),
        .package(path: "../ProviderKit"),
        .package(path: "../ReceiptsCore"),
    ],
    targets: [
        .target(
            name: "NFTDomain",
            dependencies: [
                "AuralisPrimaryModels",
            ]
        ),
        .target(
            name: "NFTProviderAdapters",
            dependencies: [
                "NFTDomain",
                "ChainProviders",
                "ExplorerAdapter",
                "ProviderKit",
            ]
        ),
        .target(
            name: "NFTPersistence",
            dependencies: [
                "NFTDomain",
                .product(name: "AuralisPrimaryPersistence", package: "AuralisPrimaryModels"),
                "ReceiptsCore",
            ]
        ),
        .target(
            name: "NFTPresentation",
            dependencies: [
                "NFTDomain",
                "NFTProviderAdapters",
                "NFTPersistence",
                .product(name: "AuralisPrimaryPersistence", package: "AuralisPrimaryModels"),
            ]
        ),
        .target(
            name: "NFTKit",
            dependencies: [
                "NFTDomain",
                "NFTProviderAdapters",
                "NFTPersistence",
                "NFTPresentation",
            ]
        ),
    ]
)
