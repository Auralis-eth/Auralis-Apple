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
            name: "ContextCore",
            targets: ["ContextCore"]
        ),
        .library(name: "MemoryCore", targets: ["MemoryCore"]),
        .library(name: "MemoryStorage", targets: ["MemoryStorage"]),
        .library(name: "MemoryRetrieval", targets: ["MemoryRetrieval"])
    ],
    targets: [
        .target(
            name: "ContextCore"
        ),
        .target(name: "MemoryCore"),
        .target(name: "MemoryStorage", dependencies: ["MemoryCore"]),
        .target(name: "MemoryRetrieval", dependencies: ["MemoryCore"]),
        .testTarget(
            name: "ContextCoreTests",
            dependencies: ["ContextCore"]
        ),
        .testTarget(name: "MemoryCoreTests", dependencies: ["MemoryCore"]),
        .testTarget(name: "MemoryStorageTests", dependencies: ["MemoryCore", "MemoryStorage"]),
        .testTarget(name: "MemoryRetrievalTests", dependencies: ["MemoryCore", "MemoryRetrieval"])
    ]
)
