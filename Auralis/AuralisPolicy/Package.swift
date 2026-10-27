// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AuralisPolicy",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0")
    ],
    products: [
        .library(
            name: "AuralisPolicy",
            targets: ["AuralisPolicy"]
        )
    ],
    dependencies: [
        .package(path: "../AuralisFoundation"),
        .package(path: "../AuralisReceipts"),
        .package(path: "../AuralisRuntime")
    ],
    targets: [
        .target(
            name: "AuralisPolicy",
            dependencies: [
                .product(name: "AuralisFoundation", package: "AuralisFoundation"),
                .product(name: "AuralisReceipts", package: "AuralisReceipts"),
                .product(name: "AuralisRuntime", package: "AuralisRuntime")
            ]
        ),
        .testTarget(
            name: "AuralisPolicyTests",
            dependencies: ["AuralisPolicy"]
        )
    ]
)
