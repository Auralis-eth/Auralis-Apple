// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ChainProviders",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "ChainProviders",
            targets: ["ChainProviders"]
        ),
    ],
    dependencies: [
        .package(path: "../AuralisPrimaryModels"),
        .package(path: "../ProviderKit"),
        .package(path: "../AuralisTestSupport"),
    ],
    targets: [
        .target(
            name: "ChainProviders",
            dependencies: [
                "AuralisPrimaryModels",
                "ProviderKit",
            ]
        ),
        .testTarget(
            name: "ChainProvidersTests",
            dependencies: [
                "AuralisPrimaryModels",
                "ChainProviders",
                "ProviderKit",
                "AuralisTestSupport",
            ]
        ),
    ]
)
