// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AuralisFoundation",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "AuralisFoundation",
            targets: ["AuralisFoundation"]
        ),
        .library(
            name: "CapabilitiesCore",
            targets: ["CapabilitiesCore"]
        ),
        .library(
            name: "SwiftDataAdapters",
            targets: ["SwiftDataAdapters"]
        ),
        .library(
            name: "UserDefaultsAdapters",
            targets: ["UserDefaultsAdapters"]
        )
    ],
    targets: [
        .target(
            name: "AuralisFoundation"
        ),
        .target(
            name: "CapabilitiesCore"
        ),
        .target(
            name: "SwiftDataAdapters"
        ),
        .target(
            name: "UserDefaultsAdapters"
        ),
        .testTarget(
            name: "AuralisFoundationTests",
            dependencies: ["AuralisFoundation"]
        ),
        .testTarget(
            name: "CapabilitiesCoreTests",
            dependencies: ["CapabilitiesCore"]
        ),
        .testTarget(
            name: "SwiftDataAdaptersTests",
            dependencies: ["SwiftDataAdapters"]
        ),
        .testTarget(
            name: "UserDefaultsAdaptersTests",
            dependencies: ["UserDefaultsAdapters"]
        )
    ]
)
