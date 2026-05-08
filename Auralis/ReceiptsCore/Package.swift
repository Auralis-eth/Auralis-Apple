// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ReceiptsCore",
    platforms: [
        .iOS(.v18),
    ],
    products: [
        .library(
            name: "ReceiptsCore",
            targets: ["ReceiptsCore"]
        ),
    ],
    dependencies: [
        .package(path: "../AuralisPrimaryModels"),
    ],
    targets: [
        .target(
            name: "ReceiptsCore",
            dependencies: [
                "AuralisPrimaryModels",
            ]
        ),
    ]
)
