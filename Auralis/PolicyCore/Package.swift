// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PolicyCore",
    platforms: [
        .iOS(.v18),
    ],
    products: [
        .library(
            name: "PolicyCore",
            targets: ["PolicyCore"]
        ),
    ],
    dependencies: [
        .package(path: "../CapabilitiesCore"),
        .package(path: "../ReceiptsCore"),
    ],
    targets: [
        .target(
            name: "PolicyCore",
            dependencies: [
                "CapabilitiesCore",
                "ReceiptsCore",
            ]
        ),
    ]
)
