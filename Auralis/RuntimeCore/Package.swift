// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "RuntimeCore",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0")
    ],
    products: [
        .library(
            name: "RuntimeCore",
            targets: ["RuntimeCore"]
        ),
        .library(name: "IntentCore", targets: ["IntentCore"]),
        .library(name: "CommitmentCore", targets: ["CommitmentCore"]),
        .library(name: "OutcomeVerification", targets: ["OutcomeVerification"]),
        .library(name: "OperatorRegistry", targets: ["OperatorRegistry"]),
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
                .product(name: "AuralisFoundation", package: "AuralisFoundation")
            ]
        ),
        .target(
            name: "IntentCore",
            dependencies: [
                .product(name: "AuralisFoundation", package: "AuralisFoundation")
            ]
        ),
        .target(
            name: "CommitmentCore",
            dependencies: [
                "IntentCore",
                "RuntimeCore",
                .product(name: "AuralisFoundation", package: "AuralisFoundation")
            ]
        ),
        .target(
            name: "OutcomeVerification",
            dependencies: ["CommitmentCore", "EvalCore"]
        ),
        .target(
            name: "OperatorRegistry",
            dependencies: ["RuntimeCore"]
        ),
        .target(
            name: "PlannerCore",
            dependencies: [
                .product(name: "AuralisFoundation", package: "AuralisFoundation"),
                "RuntimeCore"
            ]
        ),
        .target(
            name: "PlaybookCore",
            dependencies: [
                .product(name: "AuralisFoundation", package: "AuralisFoundation"),
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
        .testTarget(name: "IntentCoreTests", dependencies: ["IntentCore"]),
        .testTarget(
            name: "CommitmentCoreTests",
            dependencies: ["CommitmentCore", "IntentCore", "RuntimeCore"]
        ),
        .testTarget(
            name: "OutcomeVerificationTests",
            dependencies: ["OutcomeVerification", "CommitmentCore", "IntentCore", "RuntimeCore", "EvalCore"]
        ),
        .testTarget(name: "OperatorRegistryTests", dependencies: ["OperatorRegistry", "RuntimeCore"]),
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
