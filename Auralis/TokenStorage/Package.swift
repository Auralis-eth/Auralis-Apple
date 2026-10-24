// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TokenStorage",
    // `.macOS` is declared so the test target can build on a macOS destination. Without it SPM
    // assumes an ancient macOS floor and the dependency graph fails to resolve — `ProviderKit`
    // declares `.macOS(.v15)`, so resolution reported "requires minimum platform version 15.0 ...
    // but this target supports 12.0". That made the suite unbuildable rather than merely unrun, and
    // it went unnoticed because this package has no CI lane.
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
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
        .package(path: "../AuralisFoundation"),
    ],
    targets: [
        .target(
            name: "TokenStorage",
            dependencies: [
                "AuralisPrimaryModels",
                .product(name: "AuralisPrimaryPersistence", package: "AuralisPrimaryModels"),
                "ProviderKit",
                .product(name: "SwiftDataAdapters", package: "AuralisFoundation"),
            ]
        ),
        .testTarget(
            name: "TokenStorageTests",
            dependencies: [
                "AuralisPrimaryModels",
                .product(name: "AuralisPrimaryPersistence", package: "AuralisPrimaryModels"),
                "ProviderKit",
                "TokenStorage",
            ]
        ),
    ]
)
