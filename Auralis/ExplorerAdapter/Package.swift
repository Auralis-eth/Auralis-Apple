// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ExplorerAdapter",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "ExplorerAdapter",
            targets: ["ExplorerAdapter"]
        ),
    ],
    dependencies: [
        .package(path: "../AuralisPrimaryModels"),
    ],
    targets: [
        .target(
            name: "ExplorerAdapter",
            dependencies: [
                "AuralisPrimaryModels",
            ]
        ),
        .testTarget(
            name: "ExplorerAdapterTests",
            dependencies: ["ExplorerAdapter"]
        ),
    ]
)
