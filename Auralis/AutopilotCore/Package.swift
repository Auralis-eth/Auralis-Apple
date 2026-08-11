// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AutopilotCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "AutopilotCore",
            targets: ["AutopilotCore"]
        ),
    ],
    dependencies: [
        .package(path: "../CapabilitiesCore"),
        .package(path: "../PolicyCore"),
        .package(path: "../PlannerCore"),
    ],
    targets: [
        .target(
            name: "AutopilotCore",
            dependencies: [
                "CapabilitiesCore",
                "PolicyCore",
                "PlannerCore",
            ]
        ),
        .testTarget(
            name: "AutopilotCoreTests",
            dependencies: ["AutopilotCore"]
        ),
    ]
)
