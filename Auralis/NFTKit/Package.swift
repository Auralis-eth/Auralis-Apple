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
        .package(path: "../ReceiptsCore"),
    ],
    targets: [
        .target(
            name: "NFTKit",
            dependencies: [
                "AuralisPrimaryModels",
                "ReceiptsCore",
            ]
        ),
    ]
)
