// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AuraUI",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0"),
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
