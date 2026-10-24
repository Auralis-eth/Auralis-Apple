// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ENS",
    platforms: [
        .iOS(.v18),
        // Required because this package depends on `AuralisPrimaryModels` and `ProviderKit`, which
        // both declare `.macOS(.v15)`. Without a matching floor SPM assumes macOS 12.0 here and
        // refuses to resolve either dependency on a macOS host, so `swift build`/`swift test` for
        // this package could not run locally or in CI. Same fix, same reason, as `AccountsCore`.
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "ENS",
            targets: ["ENS"]
        ),
    ],
    dependencies: [
        .package(path: "../AuralisTestSupport"),
        .package(path: "../AuralisPrimaryModels"),
        .package(path: "../ProviderKit"),
        .package(url: "https://github.com/argentlabs/web3.swift", from: "1.6.1"),
        .package(url: "https://github.com/GigaBitcoin/secp256k1.swift.git", exact: "0.6.0"),
    ],
    targets: [
        .target(
            name: "ENS",
            dependencies: [
                "AuralisPrimaryModels",
                "ProviderKit",
                .product(name: "web3.swift", package: "web3.swift"),
            ]
        ),
        .testTarget(
            name: "ENSTests",
            dependencies: [
                "ENS",
                "AuralisTestSupport",
            ]
        ),
    ]
)
