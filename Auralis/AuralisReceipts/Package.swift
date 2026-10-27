// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AuralisReceipts",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0")
    ],
    products: [
        .library(
            name: "AuralisReceipts",
            targets: ["AuralisReceipts"]
        )
    ],
    dependencies: [
        .package(path: "../AuralisFoundation"),
        .package(path: "../AuralisRuntime")
    ],
    targets: [
        .target(
            name: "AuralisReceipts",
            dependencies: [
                .product(name: "AuralisFoundation", package: "AuralisFoundation"),
                .product(name: "AuralisRuntime", package: "AuralisRuntime")
            ]
        ),
        .testTarget(
            name: "AuralisReceiptsTests",
            dependencies: [
                "AuralisReceipts",
                .product(name: "AuralisFoundation", package: "AuralisFoundation"),
                .product(name: "AuralisRuntime", package: "AuralisRuntime")
            ]
        )
    ]
)
