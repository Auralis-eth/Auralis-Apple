// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "RuntimeKit",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0")
    ],
    products: [
        .library(
            name: "RuntimeKit",
            targets: ["RuntimeKit"]
        ),
        .library(
            name: "AuralisShellCore",
            targets: ["AuralisShellCore"]
        ),
        .library(
            name: "OperatorRuntimeStorage",
            targets: ["OperatorRuntimeStorage"]
        )
    ],
    dependencies: [
        .package(path: "../AuralisRuntime"),
        .package(path: "../ReceiptsCore"),
        .package(path: "../OperatorsFeature"),
        .package(path: "../PolicyCore"),
        .package(path: "../AuralisFoundation"),
        .package(path: "../AccountsCore"),
        // web3.swift 1.6.1 still references the pre-rename `secp256k1` product.,
        // Keep the compatible constraint visible at this AppShell graph root.,
        .package(url: "https://github.com/GigaBitcoin/secp256k1.swift.git", exact: "0.6.0")
    ],
    targets: [
        .target(
            name: "RuntimeKit",
            dependencies: [
                .product(name: "AuralisRuntime", package: "AuralisRuntime"),
                .product(name: "AutopilotCore", package: "PolicyCore"),
                "ReceiptsCore",
                .product(name: "AuralisPrimaryModels", package: "AccountsCore"),
                .product(name: "ArtifactCore", package: "ReceiptsCore"),
                // The hardened SwiftData artifact store. Named explicitly rather than taken,
                // transitively through OperatorRuntimeStorage, because `PersistentRuntimeHost`,
                // constructs it directly and a transitive import is not a dependency.,
                .product(name: "ArtifactStorage", package: "ReceiptsCore"),
                "OperatorsFeature",
                "PolicyCore",
                .product(name: "AuralisFoundation", package: "AuralisFoundation"),
                "OperatorRuntimeStorage",
                .product(name: "SocialCore", package: "OperatorsFeature")
            ]
        ),
        .target(
            name: "AuralisShellCore",
            dependencies: [
                .product(name: "AuralisPrimaryModels", package: "AccountsCore"),
                .product(name: "AuralisPrimaryPersistence", package: "AccountsCore"),
                "AccountsCore"
            ]
        ),
        .target(
            name: "OperatorRuntimeStorage",
            dependencies: [
                .product(name: "ArtifactCore", package: "ReceiptsCore"),
                .product(name: "ArtifactStorage", package: "ReceiptsCore"),
                .product(name: "AuralisRuntime", package: "AuralisRuntime")
            ]
        ),
        .testTarget(
            name: "RuntimeKitTests",
            dependencies: [
                "RuntimeKit",
                "AccountsCore",
                "OperatorRuntimeStorage",
                // The persistent-host suite builds the container itself, so it names the artifact,
                // row type directly.,
                .product(name: "ArtifactStorage", package: "ReceiptsCore"),
                .product(name: "AuralisRuntime", package: "AuralisRuntime")
            ]
        ),
        .testTarget(
            name: "AuralisShellCoreTests",
            dependencies: [
                "AuralisShellCore",
                "AccountsCore",
                .product(name: "AuralisPrimaryPersistence", package: "AccountsCore")
            ]
        ),
        .testTarget(
            name: "OperatorRuntimeStorageTests",
            dependencies: ["OperatorRuntimeStorage"]
        )
    ]
)
