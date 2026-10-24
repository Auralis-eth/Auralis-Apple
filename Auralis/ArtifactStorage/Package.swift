// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ArtifactStorage",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "ArtifactStorage",
            targets: ["ArtifactStorage"]
        )
    ],
    dependencies: [
        .package(path: "../ArtifactCore"),
        .package(path: "../RuntimeCore"),
        .package(path: "../AuralisFoundation")
    ],
    targets: [
        .target(
            name: "ArtifactStorage",
            dependencies: [
                "ArtifactCore",
                // AGENTS.md: `SwiftDataAdapters/` owns the shared rollback-safe mutation mechanics.
                // The write path here consumes `performRollbackSafeMutation` rather than keeping a
                // private second copy of the same do/catch/rollback.
                .product(name: "SwiftDataAdapters", package: "AuralisFoundation")
            ]
        ),
        .testTarget(
            name: "ArtifactStorageTests",
            dependencies: [
                "ArtifactStorage",
                // The suites build artifacts out of `ActorRef`, so they import RuntimeCore
                // directly. Declaring it keeps them off ArtifactCore's transitive re-export.
                .product(name: "RuntimeCore", package: "RuntimeCore")
            ]
        )
    ]
)
