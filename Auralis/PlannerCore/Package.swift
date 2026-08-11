// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PlannerCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "PlannerCore",
            targets: ["PlannerCore"]
        ),
    ],
    dependencies: [
        .package(path: "../CapabilitiesCore"),
    ],
    targets: [
        .target(
            name: "PlannerCore",
            dependencies: [
                "CapabilitiesCore",
            ]
        ),
        .testTarget(
            name: "PlannerCoreTests",
            dependencies: ["PlannerCore"]
        ),
    ]
)
