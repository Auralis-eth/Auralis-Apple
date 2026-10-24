// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AutopilotCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "AutopilotCore",
            targets: ["AutopilotCore"]
        )
    ],
    dependencies: [
        .package(path: "../AuralisFoundation"),
        .package(path: "../PolicyCore"),
        .package(path: "../RuntimeCore")
    ],
    targets: [
        .target(
            name: "AutopilotCore",
            dependencies: [
                .product(name: "CapabilitiesCore", package: "AuralisFoundation"),
                "PolicyCore",
                .product(name: "PlannerCore", package: "RuntimeCore"),
                "RuntimeCore"
            ]
        ),
        .testTarget(
            name: "AutopilotCoreTests",
            dependencies: ["AutopilotCore"]
        )
    ]
)
