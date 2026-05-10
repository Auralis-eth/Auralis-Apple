// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SwiftDataAdapters",
    platforms: [
        .iOS(.v18),
    ],
    products: [
        .library(
            name: "SwiftDataAdapters",
            targets: ["SwiftDataAdapters"]
        ),
    ],
    targets: [
        .target(name: "SwiftDataAdapters"),
        .testTarget(
            name: "SwiftDataAdaptersTests",
            dependencies: ["SwiftDataAdapters"]
        ),
    ]
)
