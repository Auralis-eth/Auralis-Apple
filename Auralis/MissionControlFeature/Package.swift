// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MissionControlFeature",
    defaultLocalization: "en",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0")
    ],
    products: [
        .library(
            name: "MissionControlFeature",
            targets: ["MissionControlFeature"]
        )
    ],
    dependencies: [
        .package(path: "../RuntimeKit"),
        .package(path: "../RuntimeCore"),
        .package(path: "../PolicyCore"),
        .package(path: "../ReceiptsCore"),
        .package(path: "../AuralisFoundation"),
        .package(path: "../AuralisPrimaryModels"),
        .package(path: "../ArtifactCore"),
        .package(path: "../OperatorsFeature"),
        .package(path: "../SchedulingCore"),
        .package(path: "../EvalCore"),
        .package(path: "../SocialCore"),
        .package(path: "../TrustedUIKit"),
        .package(path: "../AuraUI"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0")
    ],
    targets: [
        .target(
            name: "MissionControlFeature",
            dependencies: [
                "RuntimeKit",
                "RuntimeCore",
                .product(name: "PlannerCore", package: "RuntimeCore"),
                "PolicyCore",
                "ReceiptsCore",
                .product(name: "CapabilitiesCore", package: "AuralisFoundation"),
                "AuralisPrimaryModels",
                .product(name: "PlaybookCore", package: "RuntimeCore"),
                "ArtifactCore",
                "OperatorsFeature",
                "SchedulingCore",
                .product(name: "PerformanceCore", package: "RuntimeCore"),
                "EvalCore",
                "SocialCore",
                "TrustedUIKit",
                "AuraUI"
            ],
            // NOTE: this catalog is a *staged extraction*, not live localization. Every string in
            // this target is a bare literal (`Text("…")`, `Label`, `LabeledContent`, `Section("…")`),
            // and SwiftUI's `Text(_:tableName:bundle:comment:)` defaults `bundle` to nil — which
            // means the **main** bundle, not this package's. No call site passes `bundle: .module`,
            // so nothing here resolves against this catalog at runtime and every string renders as
            // its key. That is deliberate: Mission Control is not localized piecemeal, and the
            // `bundle: .module` wiring lands together with the translations in the localization pass.
            // The catalog stays a processed resource in the meantime so Xcode keeps extracting new
            // keys into it, and that pass starts from an up-to-date file.
            resources: [
                .process("Resources/Localizable.xcstrings")
            ]
        ),
        .testTarget(
            name: "MissionControlFeatureTests",
            dependencies: [
                "MissionControlFeature",
                "RuntimeKit",
                "RuntimeCore",
                "PolicyCore",
                "ReceiptsCore",
                .product(name: "PlaybookCore", package: "RuntimeCore"),
                .product(name: "CapabilitiesCore", package: "AuralisFoundation"),
                .product(name: "PerformanceCore", package: "RuntimeCore"),
                "EvalCore",
                "SchedulingCore",
                "OperatorsFeature",
                // Imported/used directly by the test sources. Declared explicitly rather than
                // relying on SPM's transitive module search path, which is not a contract.
                "ArtifactCore",
                "SocialCore",
                "TrustedUIKit",
                "AuralisPrimaryModels",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing")
            ],
            exclude: ["__Snapshots__"]
        )
    ]
)
