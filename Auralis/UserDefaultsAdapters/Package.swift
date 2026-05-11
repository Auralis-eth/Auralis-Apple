// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "UserDefaultsAdapters",
    platforms: [
        .iOS(.v18),
    ],
    products: [
        .library(
            name: "UserDefaultsAdapters",
            targets: ["UserDefaultsAdapters"]
        ),
    ],
    targets: [
        .target(name: "UserDefaultsAdapters"),
        .testTarget(
            name: "UserDefaultsAdaptersTests",
            dependencies: ["UserDefaultsAdapters"]
        ),
    ]
)
