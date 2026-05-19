// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AuralisShellCore",
    platforms: [
        .iOS(.v18),
    ],
    products: [
        .library(
            name: "AuralisShellCore",
            targets: ["AuralisShellCore"]
        ),
    ],
    dependencies: [
        .package(path: "../AuralisPrimaryModels"),
        .package(path: "../AccountsCore"),
    ],
    targets: [
        .target(
            name: "AuralisShellCore",
            dependencies: [
                "AuralisPrimaryModels",
                .product(name: "AuralisPrimaryPersistence", package: "AuralisPrimaryModels"),
                "AccountsCore",
            ]
        ),
        .testTarget(
            name: "AuralisShellCoreTests",
            dependencies: [
                "AuralisShellCore",
                "AccountsCore",
                .product(name: "AuralisPrimaryPersistence", package: "AuralisPrimaryModels"),
            ]
        ),
    ]
)
