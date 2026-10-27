// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AuralisTestSupport",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0")
    ],
    products: [
        .library(
            name: "AuralisTestSupport",
            targets: ["AuralisTestSupport"]
        ),
    ],
    dependencies: [
        .package(path: "../AuralisFoundation"),
    ],
    targets: [
        .target(
            name: "AuralisTestSupport",
            dependencies: [
                .product(name: "AuralisFoundation", package: "AuralisFoundation"),
            ]
        ),
    ]
)
