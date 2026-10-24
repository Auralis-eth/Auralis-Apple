// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "EvalCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "EvalCore",
            targets: ["EvalCore"]
        )
    ],
    dependencies: [
        .package(path: "../RuntimeCore")
    ],
    targets: [
        .target(
            name: "EvalCore",
            dependencies: [
                "RuntimeCore",
                .product(name: "PerformanceCore", package: "RuntimeCore")
            ]
        ),
        .testTarget(
            name: "EvalCoreTests",
            dependencies: [
                "EvalCore",
                "RuntimeCore",
                .product(name: "PerformanceCore", package: "RuntimeCore")
            ]
        )
    ]
)
