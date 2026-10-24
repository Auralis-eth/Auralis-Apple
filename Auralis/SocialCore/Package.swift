// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SocialCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "SocialCore",
            targets: ["SocialCore"]
        )
    ],
    dependencies: [
        .package(path: "../AuralisPrimaryModels"),
        .package(path: "../RuntimeCore")
    ],
    targets: [
        .target(
            name: "SocialCore",
            dependencies: [
                // Already in the graph transitively through `RuntimeCore`; named explicitly so the
                // CAIP-10 identity binding in `SocialSync` can reuse the one EIP-55 implementation
                // (`AuralisEthereumAddress`) rather than growing a second address comparison.
                "AuralisPrimaryModels",
                "RuntimeCore",
                .product(name: "PlaybookCore", package: "RuntimeCore")
            ]
        ),
        .testTarget(
            name: "SocialCoreTests",
            dependencies: ["SocialCore"]
        )
    ]
)
