// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PolicyCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "PolicyCore",
            targets: ["PolicyCore"]
        )
    ],
    dependencies: [
        .package(path: "../AuralisPrimaryModels"),
        .package(path: "../AuralisFoundation"),
        .package(path: "../ReceiptsCore"),
        .package(path: "../RuntimeCore")
    ],
    targets: [
        .target(
            name: "PolicyCore",
            dependencies: [
                "AuralisPrimaryModels",
                .product(name: "CapabilitiesCore", package: "AuralisFoundation"),
                "ReceiptsCore",
                "RuntimeCore"
            ]
        ),
        .testTarget(
            name: "PolicyCoreTests",
            dependencies: ["PolicyCore"]
        )
    ]
)
