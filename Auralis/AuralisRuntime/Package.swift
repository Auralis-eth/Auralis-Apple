// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AuralisRuntime",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0")
    ],
    products: [
        .library(
            name: "AuralisRuntime",
            targets: ["AuralisRuntime"]
        )
    ],
    dependencies: [
        .package(path: "../AuralisFoundation")
    ],
    targets: [
        .target(
            name: "AuralisRuntime",
            dependencies: [
                .product(name: "AuralisFoundation", package: "AuralisFoundation")
            ]
        ),
        .testTarget(
            name: "AuralisRuntimeTests",
            dependencies: ["AuralisRuntime"]
        )
    ]
)
