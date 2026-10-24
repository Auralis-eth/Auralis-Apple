// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "RuntimeKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "RuntimeKit",
            targets: ["RuntimeKit"]
        )
    ],
    dependencies: [
        .package(path: "../RuntimeCore"),
        .package(path: "../AutopilotCore"),
        .package(path: "../ReceiptsCore"),
        .package(path: "../AuralisPrimaryModels"),
        .package(path: "../SchedulingCore"),
        .package(path: "../OperatorsFeature"),
        .package(path: "../PolicyCore"),
        .package(path: "../AuralisFoundation"),
        .package(path: "../OperatorRuntimeStorage"),
        .package(path: "../SocialCore")
    ],
    targets: [
        .target(
            name: "RuntimeKit",
            dependencies: [
                "RuntimeCore",
                "AutopilotCore",
                .product(name: "PlannerCore", package: "RuntimeCore"),
                "ReceiptsCore",
                "AuralisPrimaryModels",
                .product(name: "PlaybookCore", package: "RuntimeCore"),
                "SchedulingCore",
                .product(name: "PerformanceCore", package: "RuntimeCore"),
                .product(name: "ArtifactCore", package: "ReceiptsCore"),
                // The hardened SwiftData artifact store. Named explicitly rather than taken
                // transitively through OperatorRuntimeStorage, because `PersistentRuntimeHost`
                // constructs it directly and a transitive import is not a dependency.
                .product(name: "ArtifactStorage", package: "ReceiptsCore"),
                "OperatorsFeature",
                "PolicyCore",
                .product(name: "CapabilitiesCore", package: "AuralisFoundation"),
                "OperatorRuntimeStorage",
                "SocialCore",
                .product(name: "EvalCore", package: "RuntimeCore")
            ]
        ),
        .testTarget(
            name: "RuntimeKitTests",
            dependencies: [
                "RuntimeKit",
                "OperatorRuntimeStorage",
                // The persistent-host suite builds the container itself, so it names the artifact
                // row type directly.
                .product(name: "ArtifactStorage", package: "ReceiptsCore"),
                .product(name: "EvalCore", package: "RuntimeCore")
            ]
        )
    ]
)
