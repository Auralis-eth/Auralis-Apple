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
        .package(path: "../ReceiptsCore"),
        .package(path: "../RuntimeCore"),
        .package(path: "../SchedulingCore")
    ],
    targets: [
        .target(
            name: "OperatorRuntimeStorage",
            dependencies: [
                .product(name: "ArtifactCore", package: "ReceiptsCore"),
                // Owns the artifact row and store this package used to duplicate (weakly).
                // The edge points this way because `makeContainer` has to register
                // `StoredArtifact`, and the legacy-row migration needs to see both shapes.
                .product(name: "ArtifactStorage", package: "ReceiptsCore"),
                .product(name: "PlaybookCore", package: "RuntimeCore"),
                .product(name: "PerformanceCore", package: "RuntimeCore"),
                "RuntimeCore",
                "SchedulingCore",
                .product(name: "EvalCore", package: "RuntimeCore")
            ]
        ),
        .testTarget(
            name: "OperatorRuntimeStorageTests",
            dependencies: ["OperatorRuntimeStorage"]
        )
    ]
)
