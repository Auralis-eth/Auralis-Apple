// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AuralisApple",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0")
    ],
    products: [
        .library(name: "AuralisFoundation", targets: ["AuralisFoundation"]),
        .library(name: "AuralisRuntime", targets: ["AuralisRuntime"]),
        .library(name: "AuralisContext", targets: ["AuralisContext"]),
        .library(name: "AuralisMemory", targets: ["AuralisMemory"]),
        .library(name: "AuralisPolicy", targets: ["AuralisPolicy"]),
        .library(name: "AuralisReceipts", targets: ["AuralisReceipts"])
    ],
    targets: [
        .target(
            name: "AuralisFoundation",
            path: "Auralis/AuralisFoundation/Sources/AuralisFoundation"
        ),
        .target(
            name: "AuralisRuntime",
            dependencies: ["AuralisFoundation"],
            path: "Auralis/AuralisRuntime/Sources/AuralisRuntime"
        ),
        .target(
            name: "AuralisContext",
            path: "Auralis/AuralisContext/Sources/AuralisContext/Context"
        ),
        .target(
            name: "AuralisMemory",
            path: "Auralis/AuralisContext/Sources/AuralisContext",
            exclude: ["Context"],
            sources: ["Memory", "MemoryStorage", "MemoryRetrieval"]
        ),
        .target(
            name: "AuralisReceipts",
            dependencies: ["AuralisFoundation", "AuralisRuntime"],
            path: "Auralis/AuralisReceipts/Sources/AuralisReceipts"
        ),
        .target(
            name: "AuralisPolicy",
            dependencies: ["AuralisFoundation", "AuralisRuntime", "AuralisReceipts"],
            path: "Auralis/AuralisPolicy/Sources/AuralisPolicy"
        ),
        .testTarget(
            name: "AuralisApplePackageTests",
            dependencies: [
                "AuralisFoundation",
                "AuralisRuntime",
                "AuralisContext",
                "AuralisPolicy",
                "AuralisReceipts"
            ],
            path: "Auralis/Tests/AuralisApplePackageTests"
        )
    ]
)
