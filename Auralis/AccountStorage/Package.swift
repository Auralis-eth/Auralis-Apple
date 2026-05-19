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
        .package(path: "../ReceiptStorage"),
        .package(path: "../SwiftDataAdapters"),
        .package(path: "../TokenStorage"),
    ],
    targets: [
        .target(
            name: "AccountStorage",
            dependencies: [
                "AuralisPrimaryModels",
                .product(name: "AuralisPrimaryPersistence", package: "AuralisPrimaryModels"),
                "AccountsCore",
                "ReceiptStorage",
                "SwiftDataAdapters",
                "TokenStorage",
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
