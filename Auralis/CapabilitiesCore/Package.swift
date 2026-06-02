// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CapabilitiesCore",
    platforms: [
        .iOS(.v18),
    ],
    products: [
        .library(
            name: "CapabilitiesCore",
            targets: ["CapabilitiesCore"]
        ),
    ],
    targets: [
        .target(name: "CapabilitiesCore"),
        .testTarget(
            name: "CapabilitiesCoreTests",
            dependencies: ["CapabilitiesCore"]
        ),
    ]
)
