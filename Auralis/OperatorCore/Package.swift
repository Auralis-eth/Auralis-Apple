// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OperatorCore",
    platforms: [
        .iOS(.v18),
    ],
    products: [
        .library(
            name: "OperatorCore",
            targets: ["OperatorCore"]
        ),
    ],
    dependencies: [
        .package(path: "../AuralisPrimaryModels"),
        .package(path: "../ReceiptsCore"),
    ],
    targets: [
        .target(
            name: "OperatorCore",
            dependencies: [
                "AuralisPrimaryModels",
                "ReceiptsCore",
            ]
        ),
    ]
)
