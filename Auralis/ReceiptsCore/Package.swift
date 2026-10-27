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
        .package(path: "../AuralisRuntime")
    ],
    targets: [
        .target(
            name: "ReceiptsCore",
            dependencies: [
                .product(name: "AuralisFoundation", package: "AuralisFoundation"),
                .product(name: "AuralisRuntime", package: "AuralisRuntime")
            ]
        ),
        .target(
            name: "ArtifactCore",
            dependencies: [.product(name: "AuralisRuntime", package: "AuralisRuntime")]
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
                .product(name: "AuralisRuntime", package: "AuralisRuntime")
            ]
        ),
        .testTarget(
            name: "ReceiptsCoreTests",
            dependencies: [
                "ReceiptsCore",
                .product(name: "AuralisFoundation", package: "AuralisFoundation"),
                .product(name: "AuralisRuntime", package: "AuralisRuntime")
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
                .product(name: "AuralisRuntime", package: "AuralisRuntime")
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
