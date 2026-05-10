// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ReceiptStorage",
    platforms: [
        .iOS(.v18),
    ],
    products: [
        .library(
            name: "ReceiptStorage",
            targets: ["ReceiptStorage"]
        ),
    ],
    dependencies: [
        .package(path: "../AuralisPrimaryModels"),
        .package(path: "../ReceiptsCore"),
        .package(path: "../SwiftDataAdapters"),
    ],
    targets: [
        .target(
            name: "ReceiptStorage",
            dependencies: [
                "AuralisPrimaryModels",
                "ReceiptsCore",
                "SwiftDataAdapters",
            ]
        ),
        .testTarget(
            name: "ReceiptStorageTests",
            dependencies: [
                "ReceiptStorage",
            ]
        ),
    ]
)
