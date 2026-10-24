// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TrustedUIKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "TrustedUIKit",
            targets: ["TrustedUIKit"]
        )
    ],
    dependencies: [
        .package(path: "../RuntimeCore"),
        .package(path: "../AuralisFoundation")
    ],
    targets: [
        .target(
            name: "TrustedUIKit",
            dependencies: [
                "RuntimeCore",
                .product(name: "CapabilitiesCore", package: "AuralisFoundation")
            ]
        ),
        .testTarget(
            name: "TrustedUIKitTests",
            dependencies: [
                "TrustedUIKit",
                "RuntimeCore",
                .product(name: "CapabilitiesCore", package: "AuralisFoundation")
            ]
        )
    ]
)
