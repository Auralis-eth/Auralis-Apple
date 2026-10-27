// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ReceiptsCore",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0")
    ],
    products: [
        .library(
            name: "ReceiptsCore",
            targets: ["ReceiptsCore"]
        ),
        .library(
            name: "ArtifactCore",
            targets: ["ArtifactCore"]
        ),
        .library(
            name: "ArtifactStorage",
            targets: ["ArtifactStorage"]
        ),
        .library(
            name: "ReceiptStorage",
            targets: ["ReceiptStorage"]
        )
    ],
    dependencies: [
        .package(path: "../AuralisFoundation"),
        .package(path: "../RuntimeCore")
    ],
    targets: [
        .target(
            name: "ReceiptsCore",
            dependencies: [
                .product(name: "AuralisFoundation", package: "AuralisFoundation"),
                "RuntimeCore"
            ]
        ),
        .target(
            name: "ArtifactCore",
            dependencies: ["RuntimeCore"]
        ),
        .target(
            name: "ArtifactStorage",
            dependencies: [
                "ArtifactCore",
                .product(name: "AuralisFoundation", package: "AuralisFoundation")
            ]
        ),
        .target(
            name: "ReceiptStorage",
            dependencies: [
                .product(name: "AuralisFoundation", package: "AuralisFoundation"),
                "ReceiptsCore",
                "RuntimeCore"
            ]
        ),
        .testTarget(
            name: "ReceiptsCoreTests",
            dependencies: [
                "ReceiptsCore",
                .product(name: "AuralisFoundation", package: "AuralisFoundation"),
                .product(name: "RuntimeCore", package: "RuntimeCore")
            ]
        ),
        .testTarget(
            name: "ArtifactCoreTests",
            dependencies: ["ArtifactCore"]
        ),
        .testTarget(
            name: "ArtifactStorageTests",
            dependencies: [
                "ArtifactStorage",
                .product(name: "RuntimeCore", package: "RuntimeCore")
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
