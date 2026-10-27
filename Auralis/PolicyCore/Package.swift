// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PolicyCore",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0")
    ],
    products: [
        .library(
            name: "PolicyCore",
            targets: ["PolicyCore"]
        ),
        .library(
            name: "AutopilotCore",
            targets: ["AutopilotCore"]
        )
    ],
    dependencies: [
        .package(path: "../AuralisFoundation"),
        .package(path: "../ReceiptsCore"),
        .package(path: "../AuralisRuntime")
    ],
    targets: [
        .target(
            name: "PolicyCore",
            dependencies: [
                .product(name: "AuralisFoundation", package: "AuralisFoundation"),
                "ReceiptsCore",
                .product(name: "AuralisRuntime", package: "AuralisRuntime")
            ]
        ),
        .target(
            name: "AutopilotCore",
            dependencies: [
                .product(name: "AuralisFoundation", package: "AuralisFoundation"),
                "PolicyCore",
                .product(name: "AuralisRuntime", package: "AuralisRuntime")
            ]
        ),
        .testTarget(
            name: "PolicyCoreTests",
            dependencies: ["PolicyCore"]
        ),
        .testTarget(
            name: "AutopilotCoreTests",
            dependencies: ["AutopilotCore"]
        )
    ]
)
