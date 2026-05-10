// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "NFTKit",
    platforms: [
        .iOS(.v18),
    ],
    products: [
        .library(
            name: "NFTKit",
            targets: ["NFTKit"]
        ),
    ],
    dependencies: [
        .package(path: "../AuralisPrimaryModels"),
        .package(path: "../ChainProviders"),
        .package(path: "../ExplorerAdapter"),
        .package(path: "../ProviderKit"),
        .package(path: "../ReceiptsCore"),
        .package(path: "../ReceiptStorage"),
    ],
    targets: [
        .target(
            name: "NFTKit",
            dependencies: [
                "AuralisPrimaryModels",
                "ChainProviders",
                "ExplorerAdapter",
                "ProviderKit",
                "ReceiptsCore",
                "ReceiptStorage",
            ]
        ),
    ]
)
