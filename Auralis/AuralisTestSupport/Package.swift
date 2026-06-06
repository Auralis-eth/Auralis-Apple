// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AuralisTestSupport",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "AuralisTestSupport",
            targets: ["AuralisTestSupport"]
        ),
    ],
    dependencies: [
        .package(path: "../AuralisPrimaryModels"),
        .package(path: "../ReceiptStorage"),
    ],
    targets: [
        .target(
            name: "AuralisTestSupport",
            dependencies: [
                "AuralisPrimaryModels",
                .product(name: "AuralisPrimaryPersistence", package: "AuralisPrimaryModels"),
                "ReceiptStorage",
            ]
        ),
    ]
)
