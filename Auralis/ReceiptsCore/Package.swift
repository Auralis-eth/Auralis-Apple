// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ReceiptsCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "ReceiptsCore",
            targets: ["ReceiptsCore"]
        )
    ],
    dependencies: [
        .package(path: "../AuralisFoundation"),
        .package(path: "../AuralisPrimaryModels"),
        .package(path: "../RuntimeCore")
    ],
    targets: [
        .target(
            name: "ReceiptsCore",
            dependencies: [
                "AuralisFoundation",
                "AuralisPrimaryModels",
                .product(name: "CapabilitiesCore", package: "AuralisFoundation"),
                "RuntimeCore"
            ]
        ),
        .testTarget(
            name: "ReceiptsCoreTests",
            dependencies: [
                "ReceiptsCore",
                .product(name: "AuralisFoundation", package: "AuralisFoundation"),
                .product(name: "AuralisPrimaryModels", package: "AuralisPrimaryModels"),
                .product(name: "CapabilitiesCore", package: "AuralisFoundation"),
                .product(name: "RuntimeCore", package: "RuntimeCore")
            ]
        )
    ]
)
