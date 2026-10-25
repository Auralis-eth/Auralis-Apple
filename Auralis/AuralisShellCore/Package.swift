// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AuralisShellCore",
    platforms: [
        // AccountsCore now contains AccountsFeature and therefore shares AuraUI's OS 26 floor.
        // SwiftPM requires every direct consumer to declare a compatible platform version.
        .iOS("26.0"),
        .macOS("26.0")
    ],
    products: [
        .library(
            name: "AuralisShellCore",
            targets: ["AuralisShellCore"]
        )
    ],
    dependencies: [
        .package(path: "../AuralisPrimaryModels"),
        .package(path: "../AccountsCore")
    ],
    targets: [
        .target(
            name: "AuralisShellCore",
            dependencies: [
                "AuralisPrimaryModels",
                .product(name: "AuralisPrimaryPersistence", package: "AuralisPrimaryModels"),
                "AccountsCore"
            ]
        ),
        .testTarget(
            name: "AuralisShellCoreTests",
            dependencies: [
                "AuralisShellCore",
                "AccountsCore",
                .product(name: "AuralisPrimaryPersistence", package: "AuralisPrimaryModels")
            ]
        )
    ]
)
