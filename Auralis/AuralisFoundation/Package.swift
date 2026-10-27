// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AuralisFoundation",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0")
    ],
    products: [
        .library(
            name: "AuralisFoundation",
            targets: ["AuralisFoundation"]
        )
    ],
    targets: [
        .target(
            name: "AuralisFoundation"
        ),
        .testTarget(
            name: "AuralisFoundationTests",
            dependencies: ["AuralisFoundation"]
        )
    ]
)
