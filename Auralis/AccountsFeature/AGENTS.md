# AccountsFeature Project Memory

## Project Overview

AccountsFeature is the wallet-entry and account presentation package for Auralis. It owns guest pass account data, home account summary presentation, address entry validation, QR scanning UI, and account-related presenters that can be tested outside the app target.

## Architecture Decisions

- Keep domain values under `Sources/AccountsFeature/Domain`.
- Keep SwiftUI account-entry surfaces under `Sources/AccountsFeature/Presentation`.
- Keep presenter and validation helpers under `Sources/AccountsFeature/Support`.
- Depend on `AccountsCore` for account protocols and shared account behavior.
- Depend on `AuralisPrimaryModels` for foundational model types.
- Depend on `AuraUI` for shared visual system pieces.
- Depend on the remote `CodeScanner` package for QR scanning.

## Important Conventions

- Prefer SwiftUI-first, state-driven views.
- Prefer Swift Concurrency over callback-heavy APIs.
- Prefer instance methods and injected collaborators over `static` convenience helpers.
- Keep presentation formatting in presenters so it can be covered by focused Swift Testing tests.
- Keep package dependencies accurate in `Package.swift`; local dependencies should point to sibling packages that actually exist on disk.

## Build And Run

- Open `AccountsFeature/Package.swift` directly in Xcode to work on the package by itself.
- Build with Xcode or the MCP `BuildProject` tool.
- Run package tests from the `AccountsFeature` package scheme when Xcode has resolved dependencies.

## Quirks And Gotchas

- `CodeScanner` is a remote package used by `AddressTextField.swift`, not a local sibling package.
- Opening `.swiftpm/xcode` directly exposes generated workspace metadata. The real package root is `AccountsFeature/`.
- If Xcode shows no package scheme, check whether `Package.swift` has a missing local dependency path before debugging target settings.
