// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SchedulingCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "SchedulingCore",
            targets: ["SchedulingCore"]
        )
    ],
    dependencies: [
        .package(path: "../ReceiptsCore"),
        .package(path: "../RuntimeCore")
    ],
    targets: [
        .target(
            name: "SchedulingCore",
            dependencies: [
                .product(name: "PlaybookCore", package: "RuntimeCore"),
                .product(name: "PerformanceCore", package: "RuntimeCore"),
                .product(name: "ArtifactCore", package: "ReceiptsCore"),
                "RuntimeCore"
            ]
        ),
        .testTarget(
            name: "SchedulingCoreTests",
            dependencies: ["SchedulingCore", "RuntimeCore"]
        )
    ]
)
