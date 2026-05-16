# AccountsFeature Journal

## The Big Picture

AccountsFeature is the front door for wallet identity in Auralis. It is the part of the app that asks, "Who are you in wallet-land?" and then turns the answer into tidy, Aura-flavored UI pieces the rest of the app can trust.

## Architecture Deep Dive

Think of the package like a small reception desk. The domain files are the guest list, the presentation views are the desk and scanner, and the support presenters are the staff translating raw account details into something readable before anyone walks farther into the building.

The package stays intentionally narrow: it does not own the whole app shell, persistence stack, or NFT loading. It prepares account entry and account summaries so larger app modules can compose them.

## The Codebase Map

- `Sources/AccountsFeature/Domain/` holds account-facing values such as guest passes and home summary inputs.
- `Sources/AccountsFeature/Presentation/` holds SwiftUI views for address entry, guest pass cards, carousels, and QR scanning.
- `Sources/AccountsFeature/Support/` holds presenter and validation helpers.
- `Tests/AccountsFeatureTests/` verifies presenter behavior, validation states, account switching copy, and guest pass data.

## Tech Stack & Why

- Swift Package Manager keeps this feature modular and testable away from the main app target.
- SwiftUI fits the package because the surfaces are state-driven account entry and selection flows.
- Swift Testing keeps presenter and domain tests light, direct, and fast.
- `CodeScanner` handles QR scanning so the package can spend its complexity budget on wallet/account behavior instead of camera plumbing.

## The Journey

### 2026-05-15: The Missing Scanner Package

Xcode was not even getting as far as loading dependency packages or offering a useful build scheme. The culprit was hiding in plain sight: `Package.swift` pointed at `../CodeScanner` as if `CodeScanner` were a local sibling package, but no such folder existed.

The main app project already knew the truth: `CodeScanner` comes from `https://github.com/twoStraws/CodeScanner` at version `2.5.2`. The package manifest now matches that remote dependency. Moral of the story: when SwiftPM cannot build the graph, Xcode may look like it has forgotten how packages work, but often the graph just has a broken road sign.

Once the scanner road sign was fixed, SwiftPM found the next speed bump: package tests build on macOS, and without an explicit macOS platform the package quietly inherited macOS 10.13. That was too old for `AuraUI` and `CodeScanner`, so the manifest now declares macOS 14 alongside iOS 18.

## Engineer's Wisdom

When a package has no scheme or dependencies appear not to load, inspect `Package.swift` before blaming Xcode. A single missing local path can prevent SwiftPM from constructing the package graph, which means every downstream symptom is just fallout.

## If I Were Starting Over...

I would keep third-party dependencies declared the same way in both the app project and extracted feature packages from the moment the feature package is created. Duplicated dependency knowledge tends to drift unless the package owns its own manifest truth.
