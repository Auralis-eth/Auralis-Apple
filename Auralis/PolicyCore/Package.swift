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
        .package(path: "../RuntimeCore")
    ],
    targets: [
        .target(
            name: "PolicyCore",
            dependencies: [
                .product(name: "AuralisFoundation", package: "AuralisFoundation"),
                "ReceiptsCore",
                "RuntimeCore"
            ]
        ),
        .target(
            name: "AutopilotCore",
            dependencies: [
                .product(name: "AuralisFoundation", package: "AuralisFoundation"),
                "PolicyCore",
                .product(name: "PlannerCore", package: "RuntimeCore"),
                "RuntimeCore"
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
