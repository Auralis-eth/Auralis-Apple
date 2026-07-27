// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WalletConnectorKit",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0"),
    ],
    products: [
        .library(
            name: "WalletConnectorKit",
            targets: ["WalletConnectorKit"]
        ),
    ],
    targets: [
        .target(
            name: "WalletConnectorKit"
        ),
        .testTarget(
            name: "WalletConnectorKitTests",
            dependencies: [
                "WalletConnectorKit",
            ]
        ),
    ]
)
