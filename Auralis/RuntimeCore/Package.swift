// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "RuntimeCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "RuntimeCore",
            targets: ["RuntimeCore"]
        ),
        .library(
            name: "PlannerCore",
            targets: ["PlannerCore"]
        ),
        .library(
            name: "PlaybookCore",
            targets: ["PlaybookCore"]
        ),
        .library(
            name: "PerformanceCore",
            targets: ["PerformanceCore"]
        ),
        .library(
            name: "EvalCore",
            targets: ["EvalCore"]
        ),
        .library(
            name: "SchedulingCore",
            targets: ["SchedulingCore"]
        )
    ],
    dependencies: [
        .package(path: "../AuralisFoundation")
    ],
    targets: [
        .target(
            name: "RuntimeCore",
            dependencies: [
                .product(name: "CapabilitiesCore", package: "AuralisFoundation")
            ]
        ),
        .target(
            name: "PlannerCore",
            dependencies: [
                .product(name: "CapabilitiesCore", package: "AuralisFoundation"),
                "RuntimeCore"
            ]
        ),
        .target(
            name: "PlaybookCore",
            dependencies: [
                .product(name: "CapabilitiesCore", package: "AuralisFoundation"),
                "RuntimeCore"
            ]
        ),
        .target(name: "PerformanceCore"),
        .target(
            name: "EvalCore",
            dependencies: [
                "RuntimeCore",
                "PerformanceCore"
            ]
        ),
        .target(
            name: "SchedulingCore",
            dependencies: [
                "PlaybookCore",
                "PerformanceCore",
                "RuntimeCore"
            ]
        ),
        .testTarget(
            name: "RuntimeCoreTests",
            dependencies: ["RuntimeCore"]
        ),
        .testTarget(
            name: "PlannerCoreTests",
            dependencies: [
                "PlannerCore",
                "RuntimeCore"
            ]
        ),
        .testTarget(
            name: "PlaybookCoreTests",
            dependencies: ["PlaybookCore"]
        ),
        .testTarget(
            name: "PerformanceCoreTests",
            dependencies: ["PerformanceCore"]
        ),
        .testTarget(
            name: "EvalCoreTests",
            dependencies: [
                "EvalCore",
                "RuntimeCore",
                "PerformanceCore"
            ]
        ),
        .testTarget(
            name: "SchedulingCoreTests",
            dependencies: ["SchedulingCore", "RuntimeCore"]
        )
    ]
)
