// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AccountStorage",
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
            name: "AccountStorage",
            targets: ["AccountStorage"]
        ),
    ],
    dependencies: [
        .package(path: "../AuralisPrimaryModels"),
        .package(path: "../AccountsCore"),
        .package(path: "../ReceiptsCore"),
        .package(path: "../AuralisFoundation"),
        .package(path: "../TokenStorage"),
        .package(path: "../NFTKit"),
    ],
    targets: [
        .target(
            name: "AccountStorage",
            dependencies: [
                "AuralisPrimaryModels",
                .product(name: "AuralisPrimaryPersistence", package: "AuralisPrimaryModels"),
                "AccountsCore",
                .product(name: "ReceiptStorage", package: "ReceiptsCore"),
                .product(name: "SwiftDataAdapters", package: "AuralisFoundation"),
                "TokenStorage",
                .product(name: "NFTPersistence", package: "NFTKit"),
            ]
        ),
        .testTarget(
            name: "AccountStorageTests",
            dependencies: [
                "AccountStorage",
                // Declared explicitly because the suite names `AuralisPrimaryPersistence.Tag`: the
                // bare `Tag` resolves to Swift Testing's own `Tag` type, which is not a
                // `PersistentModel`, so the fetch failed to compile.
                .product(name: "AuralisPrimaryPersistence", package: "AuralisPrimaryModels"),
            ]
        ),
    ]
)
