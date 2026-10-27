// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AuralisMissionControl",
    defaultLocalization: "en",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0")
    ],
    products: [
        .library(
            name: "AuralisMissionControl",
            targets: ["AuralisMissionControl"]
        )
    ],
    dependencies: [
        .package(path: "../AuralisAppShell"),
        .package(path: "../AuralisRuntime"),
        .package(path: "../AuralisPolicy"),
        .package(path: "../AuralisReceipts"),
        .package(path: "../AuralisFoundation"),
        .package(path: "../AuralisCrypto"),
        .package(path: "../AuralisOperators"),
        .package(path: "../AuraUI"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0")
    ],
    targets: [
        .target(
            name: "AuralisMissionControl",
            dependencies: [
                .product(name: "AuralisAppShell", package: "AuralisAppShell"),
                .product(name: "AuralisRuntime", package: "AuralisRuntime"),
                .product(name: "AuralisPolicy", package: "AuralisPolicy"),
                .product(name: "AuralisReceipts", package: "AuralisReceipts"),
                .product(name: "AuralisFoundation", package: "AuralisFoundation"),
                .product(name: "AuralisCrypto", package: "AuralisCrypto"),
                .product(name: "AuralisOperators", package: "AuralisOperators"),
                "AuraUI"
            ],
            // NOTE: this catalog is a *staged extraction*, not live localization. Every string in
            // this target is a bare literal (`Text("…")`, `Label`, `LabeledContent`, `Section("…")`)
            // and SwiftUI's `Text(_:tableName:bundle:comment:)` defaults `bundle` to nil — which
            // means the **main** bundle, not this package's. No call site passes `bundle: .module`
            // so nothing here resolves against this catalog at runtime and every string renders as
            // its key. That is deliberate: Mission Control is not localized piecemeal, and the
            // `bundle: .module` wiring lands together with the translations in the localization pass.
            // The catalog stays a processed resource in the meantime so Xcode keeps extracting new
            // keys into it, and that pass starts from an up-to-date file.
            resources: [
                .process("MissionControl/Resources/Localizable.xcstrings")
            ]
        ),
        .testTarget(
            name: "AuralisMissionControlTests",
            dependencies: [
                "AuralisMissionControl",
                .product(name: "AuralisAppShell", package: "AuralisAppShell"),
                .product(name: "AuralisRuntime", package: "AuralisRuntime"),
                .product(name: "AuralisPolicy", package: "AuralisPolicy"),
                .product(name: "AuralisReceipts", package: "AuralisReceipts"),
                .product(name: "AuralisFoundation", package: "AuralisFoundation"),
                .product(name: "AuralisOperators", package: "AuralisOperators"),
                // Imported/used directly by the test sources. Declared explicitly rather than
                // relying on SPM's transitive module search path, which is not a contract.
                .product(name: "AuralisCrypto", package: "AuralisCrypto"),
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing")
            ],
            // Baselines live beside the suite that records them, so the path moved with the
            // test sources into the merged target.
            exclude: ["MissionControl/__Snapshots__"]
        )
    ]
)
