// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ReceiptStorage",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "ReceiptStorage",
            targets: ["ReceiptStorage"]
        )
    ],
    dependencies: [
        .package(path: "../AuralisFoundation"),
        .package(path: "../AuralisPrimaryModels"),
        .package(path: "../ReceiptsCore"),
        .package(path: "../RuntimeCore")
    ],
    targets: [
        .target(
            name: "ReceiptStorage",
            dependencies: [
                "AuralisFoundation",
                "AuralisPrimaryModels",
                "ReceiptsCore",
                .product(name: "SwiftDataAdapters", package: "AuralisFoundation"),
                "RuntimeCore"
            ]
        ),
        .testTarget(
            name: "ReceiptStorageTests",
            dependencies: [
                "ReceiptStorage",
                .product(name: "AuralisFoundation", package: "AuralisFoundation")
            ]
        )
    ]
)
