// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AccountsCore",
    platforms: [
        // AccountsFeature imports AuraUI, whose supported platform floor is OS 26.
        // SwiftPM platform declarations apply to the complete package, not individual targets.
        .iOS("26.0"),
        .macOS("26.0")
    ],
    products: [
        .library(
            name: "AccountsCore",
            targets: ["AccountsCore"]
        ),
        .library(
            name: "AccountStorage",
            targets: ["AccountStorage"]
        ),
        .library(
            name: "TokenStorage",
            targets: ["TokenStorage"]
        ),
        .library(
            name: "AccountsFeature",
            targets: ["AccountsFeature"]
        )
    ],
    dependencies: [
        .package(path: "../AuralisPrimaryModels"),
        .package(path: "../ReceiptsCore"),
        .package(path: "../AuralisFoundation"),
        .package(path: "../ProviderKit"),
        .package(path: "../NFTKit"),
        .package(path: "../AuraUI"),
        .package(path: "../CodeScanner")
    ],
    targets: [
        .target(
            name: "AccountsCore",
            dependencies: [
                "AuralisPrimaryModels",
                .product(name: "AuralisPrimaryPersistence", package: "AuralisPrimaryModels")
            ]
        ),
        .target(
            name: "AccountStorage",
            dependencies: [
                "AuralisPrimaryModels",
                .product(name: "AuralisPrimaryPersistence", package: "AuralisPrimaryModels"),
                "AccountsCore",
                .product(name: "ReceiptStorage", package: "ReceiptsCore"),
                .product(name: "SwiftDataAdapters", package: "AuralisFoundation"),
                "TokenStorage",
                .product(name: "NFTPersistence", package: "NFTKit")
            ]
        ),
        .target(
            name: "TokenStorage",
            dependencies: [
                "AuralisPrimaryModels",
                .product(name: "AuralisPrimaryPersistence", package: "AuralisPrimaryModels"),
                "ProviderKit",
                .product(name: "SwiftDataAdapters", package: "AuralisFoundation")
            ]
        ),
        .target(
            name: "AccountsFeature",
            dependencies: [
                "AccountsCore",
                "AuralisPrimaryModels",
                .product(name: "AuralisPrimaryPersistence", package: "AuralisPrimaryModels"),
                "AuraUI",
                .product(name: "CodeScanner", package: "CodeScanner")
            ],
            sources: [
                "Domain",
                "Presentation",
                "Support"
            ]
        ),
        .testTarget(
            name: "AccountsCoreTests",
            dependencies: ["AccountsCore"]
        ),
        .testTarget(
            name: "AccountStorageTests",
            dependencies: [
                "AccountStorage",
                .product(name: "AuralisPrimaryPersistence", package: "AuralisPrimaryModels")
            ]
        ),
        .testTarget(
            name: "TokenStorageTests",
            dependencies: [
                "AuralisPrimaryModels",
                .product(name: "AuralisPrimaryPersistence", package: "AuralisPrimaryModels"),
                "ProviderKit",
                "TokenStorage"
            ]
        ),
        .testTarget(
            name: "AccountsFeatureTests",
            dependencies: [
                "AccountsFeature",
                "AuralisPrimaryModels",
                .product(name: "AuralisPrimaryPersistence", package: "AuralisPrimaryModels")
            ]
        )
    ]
)
