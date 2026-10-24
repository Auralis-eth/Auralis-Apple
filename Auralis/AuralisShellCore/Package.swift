// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AuralisShellCore",
    platforms: [
        .iOS(.v18),
        // Matches `AuralisPrimaryModels`, which declares `.macOS(.v15)`. Without a macOS floor this
        // package inherits SPM's default (12.0), which is *below* that dependency's floor, so
        // `swift test` could not build here at all — and because `AuralisShellCoreTests` is in no
        // `.xctestplan` and no CI scheme, that left the routing suite executing nowhere. The library
        // itself ships to iOS; this only makes the package testable on a macOS host.
        .macOS(.v15)
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
