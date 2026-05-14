// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AuraUI",
    platforms: [
        .iOS(.v18),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "AuraUI",
            targets: ["AuraUI"]
        ),
    ],
    targets: [
        .target(
            name: "AuraUI"
        ),
        .testTarget(
            name: "AuraUITests",
            dependencies: ["AuraUI"]
        ),
    ]
)
