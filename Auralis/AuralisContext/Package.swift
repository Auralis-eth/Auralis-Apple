// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AuralisContext",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0")
    ],
    products: [
        .library(
            name: "AuralisContext",
            targets: ["AuralisContext"]
        )
    ],
    targets: [
        .target(
            name: "AuralisContext"
        ),
        .testTarget(
            name: "AuralisContextTests",
            dependencies: ["AuralisContext"]
        )
    ]
)
