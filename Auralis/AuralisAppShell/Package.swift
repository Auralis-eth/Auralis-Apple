// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AuralisAppShell",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0")
    ],
    products: [
        .library(
            name: "AuralisAppShell",
            targets: ["AuralisAppShell"]
        )
    ],
    dependencies: [
        .package(path: "../AuralisRuntime"),
        .package(path: "../AuralisReceipts"),
        .package(path: "../AuralisOperators"),
        .package(path: "../AuralisPolicy"),
        .package(path: "../AuralisFoundation"),
        .package(path: "../AuralisCrypto"),
        // web3.swift 1.6.1 still references the pre-rename `secp256k1` product.
        // Keep the compatible constraint visible at this AppShell graph root.
        .package(url: "https://github.com/GigaBitcoin/secp256k1.swift.git", exact: "0.6.0")
    ],
    targets: [
        .target(
            name: "AuralisAppShell",
            dependencies: [
                .product(name: "AuralisRuntime", package: "AuralisRuntime"),
                .product(name: "AuralisPolicy", package: "AuralisPolicy"),
                .product(name: "AuralisReceipts", package: "AuralisReceipts"),
                .product(name: "AuralisOperators", package: "AuralisOperators"),
                .product(name: "AuralisFoundation", package: "AuralisFoundation"),
                .product(name: "AuralisCrypto", package: "AuralisCrypto")
            ]
        ),
        .testTarget(
            name: "AuralisAppShellTests",
            dependencies: [
                "AuralisAppShell",
                .product(name: "AuralisCrypto", package: "AuralisCrypto"),
                .product(name: "AuralisReceipts", package: "AuralisReceipts"),
                .product(name: "AuralisRuntime", package: "AuralisRuntime")
            ]
        )
    ]
)
