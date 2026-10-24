// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OperatorRuntimeStorage",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "OperatorRuntimeStorage",
            targets: ["OperatorRuntimeStorage"]
        )
    ],
    dependencies: [
        .package(path: "../ArtifactCore"),
        .package(path: "../ArtifactStorage"),
        .package(path: "../RuntimeCore"),
        .package(path: "../SchedulingCore"),
        .package(path: "../EvalCore")
    ],
    targets: [
        .target(
            name: "OperatorRuntimeStorage",
            dependencies: [
                "ArtifactCore",
                // Owns the artifact row and store this package used to duplicate (weakly).
                // The edge points this way because `makeContainer` has to register
                // `StoredArtifact`, and the legacy-row migration needs to see both shapes.
                "ArtifactStorage",
                .product(name: "PlaybookCore", package: "RuntimeCore"),
                .product(name: "PerformanceCore", package: "RuntimeCore"),
                "RuntimeCore",
                "SchedulingCore",
                "EvalCore"
            ]
        ),
        .testTarget(
            name: "OperatorRuntimeStorageTests",
            dependencies: ["OperatorRuntimeStorage"]
        )
    ]
)
