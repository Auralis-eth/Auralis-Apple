// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AccountStorage",
    platforms: [
        .iOS(.v18),
    ],
    products: [
        .library(
            name: "AccountStorage",
            targets: ["AccountStorage"]
        ),
    ],
    dependencies: [
        .package(path: "../AuralisPrimaryModels"),
        .package(path: "../AccountsCore"),
        .package(path: "../SwiftDataAdapters"),
    ],
    targets: [
        .target(
            name: "AccountStorage",
            dependencies: [
                "AuralisPrimaryModels",
                "AccountsCore",
                "SwiftDataAdapters",
            ]
        ),
        .testTarget(
            name: "AccountStorageTests",
            dependencies: [
                "AccountStorage",
            ]
        ),
    ]
)
