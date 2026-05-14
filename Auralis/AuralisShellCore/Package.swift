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
    ],
    targets: [
        .target(
            name: "AuralisShellCore",
            dependencies: [
                "AuralisPrimaryModels",
            ]
        ),
        .testTarget(
            name: "AuralisShellCoreTests",
            dependencies: [
                "AuralisShellCore",
            ]
        ),
    ]
)
