// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AccountsCore",
    platforms: [
        .iOS(.v18),
        // Required because this package depends on `AuralisPrimaryModels`, which declares
        // `.macOS(.v15)`. Without a matching floor SPM assumes macOS 12.0 here and refuses to
        // resolve that dependency on a macOS host, which also blocked every downstream package
        // (notably `AuralisShellCore`) from running `swift test` locally or in CI.
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "AccountsCore",
            targets: ["AccountsCore"]
        ),
        .library(
            name: "AccountStorage",
            targets: ["AccountStorage"]
        ),
        .library(
            name: "TokenStorage",
            targets: ["TokenStorage"]
        )
    ],
    dependencies: [
        .package(path: "../AuralisPrimaryModels"),
        .package(path: "../ReceiptsCore"),
        .package(path: "../AuralisFoundation"),
        .package(path: "../ProviderKit"),
        .package(path: "../NFTKit")
    ],
    targets: [
        .target(
            name: "AccountsCore",
            dependencies: [
                "AuralisPrimaryModels",
                .product(name: "AuralisPrimaryPersistence", package: "AuralisPrimaryModels")
            ]
        ),
        .target(
            name: "AccountStorage",
            dependencies: [
                "AuralisPrimaryModels",
                .product(name: "AuralisPrimaryPersistence", package: "AuralisPrimaryModels"),
                "AccountsCore",
                .product(name: "ReceiptStorage", package: "ReceiptsCore"),
                .product(name: "SwiftDataAdapters", package: "AuralisFoundation"),
                "TokenStorage",
                .product(name: "NFTPersistence", package: "NFTKit")
            ]
        ),
        .target(
            name: "TokenStorage",
            dependencies: [
                "AuralisPrimaryModels",
                .product(name: "AuralisPrimaryPersistence", package: "AuralisPrimaryModels"),
                "ProviderKit",
                .product(name: "SwiftDataAdapters", package: "AuralisFoundation")
            ]
        ),
        .testTarget(
            name: "AccountsCoreTests",
            dependencies: ["AccountsCore"]
        ),
        .testTarget(
            name: "AccountStorageTests",
            dependencies: [
                "AccountStorage",
                .product(name: "AuralisPrimaryPersistence", package: "AuralisPrimaryModels")
            ]
        ),
        .testTarget(
            name: "TokenStorageTests",
            dependencies: [
                "AuralisPrimaryModels",
                .product(name: "AuralisPrimaryPersistence", package: "AuralisPrimaryModels"),
                "ProviderKit",
                "TokenStorage"
            ]
        )
    ]
)
