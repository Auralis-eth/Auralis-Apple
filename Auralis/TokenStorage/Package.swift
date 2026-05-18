// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TokenStorage",
    platforms: [
        .iOS(.v18),
    ],
    products: [
        .library(
            name: "TokenStorage",
            targets: ["TokenStorage"]
        ),
    ],
    dependencies: [
        .package(path: "../AuralisPrimaryModels"),
        .package(path: "../ProviderKit"),
        .package(path: "../SwiftDataAdapters"),
    ],
    targets: [
        .target(
            name: "TokenStorage",
            dependencies: [
                "AuralisPrimaryModels",
                "ProviderKit",
                "SwiftDataAdapters",
            ]
        ),
        .testTarget(
            name: "TokenStorageTests",
            dependencies: [
                "AuralisPrimaryModels",
                "ProviderKit",
                "TokenStorage",
            ]
        ),
    ]
)
