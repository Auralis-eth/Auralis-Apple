# Phase 3 Follow-Up — Package Test Suite Restoration

**Created:** 2026-06-07
**Trigger:** AuraPlay Phase 3 ship validation (June 7, 2026)
**Status:** Not started

## Why This Doc Exists

During AuraPlay Phase 3 ship validation we ran every local package's test suite to confirm "all unit tests testing and passing." Phase 3 itself shipped fully green:

- `AuralisTests/AuraPlayStorageResolutionShipTests` — 3/3 pass
- `MusicFeatureTests/StorageResolutionTests` — 12/12 pass (full P3-006 coverage)
- `MusicFeatureTests` full suite — 28/28 pass
- `AuralisTests` (Auralis-Full plan) — full suite passes

But the broader sweep across 22 local package test suites surfaced **10 packages with broken tests** and **2 packages whose Xcode scheme has the test action disabled**. None of these failures touch Phase 3 storage-resolution code. They are pre-existing debt across the package graph — most likely created when shell features were extracted into their own packages and the corresponding test targets either drifted from current APIs or never linked their full dependency set.

The intent of this doc is to be the single starting point when picking up this restoration work in a fresh session.

## Snapshot Of Sweep Results

Run from each `<package>/` directory:
`xcodebuild test -scheme <package> -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5"`

| Package | Result |
| --- | --- |
| AccountsCore | ✅ PASS |
| AccountsFeature | ✅ PASS |
| CapabilitiesCore | ✅ PASS |
| CodeScanner | ✅ PASS |
| ExplorerAdapter | ✅ PASS |
| OperatorCore | ✅ PASS |
| PolicyCore | ✅ PASS |
| ReceiptsCore | ✅ PASS |
| UserDefaultsAdapters | ✅ PASS |
| MusicFeature | ✅ PASS (fixed during Phase 3 — see below) |
| AccountStorage | ❌ FAIL — API/symbol drift |
| AuraUI | ❌ FAIL — Swift Testing macro pattern |
| AuralisShellCore | ❌ FAIL — Swift Testing macro pattern |
| ChainProviders | ❌ FAIL — missing `LockedValue` import |
| ENS | ❌ FAIL — duplicate declarations |
| NFTLibraryFeature | ❌ FAIL — duplicate declarations + macro pattern |
| ProviderKit | ❌ FAIL — redaction expectation drift |
| ReceiptStorage | ❌ FAIL — `@MainActor` isolation |
| SwiftDataAdapters | ❌ FAIL — `@MainActor` isolation |
| TokenStorage | ❌ FAIL — `@MainActor` isolation |
| AuralisPrimaryModels | ⚠️ Scheme not test-configured |
| NFTKit | ⚠️ Scheme not test-configured |

## What Phase 3 Already Fixed (Reference)

For context, these MusicFeature test fixes were folded into Phase 3 ship validation and should not be re-investigated:

- `MusicFeature/Tests/MusicFeatureTests/MusicReceiptEventLoggerTests.swift` — added `import Foundation`; updated `playlistID` / `affectedMediaIDs` assertions to match the receipt store's redaction output (`<redacted-opaque-token>`, `<redacted-unexpected-string>`)
- `MusicFeature/Tests/MusicFeatureTests/MusicItemDetailPresentationTests.swift` — reordered `NFTFixture` initializer args so `collectionName` precedes `network`; switched `name: nil` to `name: ""` so `AuraPlayMusicItemDetailPresentation.cleanedText` treats it as missing
- `MusicFeature/Tests/MusicFeatureTests/AuraPlayDomainTests.swift` — added inner `try` inside `#require` for `loader.artworkURL(for:)`

Additionally, the `AuralisTests` Xcode target gained two missing package product dependencies (`AuraUI`, `CapabilitiesCore`). Without those, `AuralisTests.xctest` would not link.

## Categorized Inventory Of Remaining Failures

### Category A — Swift Testing macro pattern (low effort, mechanical)

Symptom: errors like `errors thrown from here are not handled` originating from macro expansions named `@__swiftmacro_…expectfMf_…`. Cause: the test uses `try #expect(try #require(...))` or similar nesting where the inner expression throws but the macro expansion does not propagate `try` cleanly.

Fix pattern (same as `AuraPlayDomainTests.swift`):

```swift
// Before
#expect(try #require(thing.value()).property == expected)

// After
let unwrapped = try #require(try thing.value())
#expect(unwrapped.property == expected)
```

Affected files:
- `AuraUI/Tests/AuraUITests/AuraColorTests.swift` — multiple instances (saw macro errors `MX10` through `MX21`+)
- `AuralisShellCore/Tests/AuralisShellCoreTests/ShellStoreTests.swift` — multiple instances (`MX34, MX35, MX60, MX61, MX376, MX402` from sweep output)
- `NFTLibraryFeature/Tests/NFTLibraryFeatureTests/NFTLibraryPresentationTests.swift` — `MX35, MX56`

For each file: grep for `#expect(try #require` and split.

### Category B — `@MainActor` isolation drift (low-medium effort)

Symptom: `call to main actor-isolated static method 'context()' in a synchronous nonisolated context`. Cause: a shared test helper (likely something like `TestModelContainer.context()` in `AuralisTestSupport` or a sibling) became `@MainActor`-isolated, but the test functions calling it are not.

Affected files (each appears to be a single call site):
- `ReceiptStorage/Tests/ReceiptStorageTests/SwiftDataReceiptStorageTests.swift:137`
- `SwiftDataAdapters/Tests/SwiftDataAdaptersTests/ModelContextMutationSupportTests.swift:97`
- `TokenStorage/Tests/TokenStorageTests/SwiftDataTokenHoldingsStoreTests.swift:241`

Fix options (pick per-file):
- Add `@MainActor` to the enclosing test function or test type
- Wrap the call in `MainActor.run { ... }`
- Drop the `@MainActor` from the helper if it does not actually require main-actor isolation

Recommend looking at the helper first — if all three tests need to wrap, the helper is probably what's wrong.

### Category C — Redaction expectation drift (small)

Symptom: production error / payload now emits a redacted form (`provider_error_payload_redacted reason=unclassified_message sha256=…`) but the test still expects the raw upstream message.

Same shape as `MusicReceiptEventLoggerTests` was. Reference the existing redaction-aware tests in `AuralisTests` for the expected assertion style.

Affected file:
- `ProviderKit/Tests/ProviderKitTests/ProviderConfigurationTests.swift:202`
  - Test: `"Native balance maps RPC error responses to provider errors"`
  - Actual: `.providerError("provider_error_payload_redacted reason=unclassified_message sha256=fbf483cb…")`
  - Expected (by test): `.providerError("upstream failed")`

Fix: update the expectation to match the redacted shape (with a wildcard or substring match on the `sha256=` prefix), or assert structurally on the redaction sentinel rather than the exact string.

### Category D — Stale API or symbol drift (medium-high effort, per-file investigation)

These need real investigation — APIs moved during package extractions and the tests reference identifiers that no longer exist or have new shapes.

**`AccountStorage/Tests/AccountStorageTests/SwiftDataAccountStoreTests.swift`** (lines 77, 78, 80, 83, 100):
- `incorrect argument label in call (have 'name:', expected 'from:')` — likely a `Decoder` init that now takes `from:` instead of `name:`
- `cannot find 'NFT' in scope` — missing `import AuralisPrimaryModels` / `AuralisPrimaryPersistence`, or `NFT` moved
- `'nil' requires a contextual type` — typically follows the missing-import cascade

Start by fixing the imports and the type resolution will likely cascade-fix the rest.

**`ChainProviders/Tests/ChainProvidersTests/ChainProviderCapabilitiesTests.swift:38, 60`:**
- `cannot find 'LockedValue' in scope` — likely needs `import` of a sync helper module (possibly `AuralisShellCore`?)
- `cannot infer contextual base in reference to member 'baseMainnet'` — `Chain` enum not in scope

**`ENS/Tests/ENSTests/ENSResolutionServiceTests.swift:152, 193`:**
- `invalid redeclaration of 'verified'` — two helpers/locals share the name; rename one
- `errors thrown from here are not handled` — separate throws-handling issue at 193

**`NFTLibraryFeature/Tests/NFTLibraryFeatureTests/NFTImageLoaderTests.swift:55, 93, 121, 163`:**
- `invalid redeclaration of 'response'` (4 times) — likely a stub/helper defined at file scope shadows local `response` lets; rename file-scope or convert to per-test

### Category E — Schemes with no test action configured

Both packages have `swift test` / `xcodebuild test` blocked because the scheme is autogenerated without the test action enabled. Same fix pattern as the `AuralisTests` package linkage from Phase 3:

- `AuralisPrimaryModels` — has `Tests/AuralisPrimaryModelsTests/`
- `NFTKit` — has `Tests/NFTKitTests/`

Per the AGENTS.md guardrail, pbxproj-style metadata edits while Xcode is open are unsafe to do programmatically. The right path is to open each package in Xcode, edit the scheme (`Product → Scheme → Edit Scheme… → Test`), make sure the test target is checked, and save.

Once test actions are enabled, both will need an independent sweep to confirm whether they pass.

## Suggested Order Of Attack

1. **Category A (macro pattern)** first — three files, mechanical edits, builds confidence and removes the most noise.
2. **Category B (`@MainActor`)** — investigate the shared helper once; the three call sites should all use the same fix.
3. **Category C (ProviderKit redaction)** — one assertion update.
4. **Category E (enable schemes)** — both, in Xcode UI, then re-sweep.
5. **Category D (symbol drift)** — slowest, per-file. Do AccountStorage and ChainProviders first (likely just import fixes), then ENS, then NFTLibraryFeature.

A full re-sweep after each category will confirm progress without surprises.

## Running The Sweep

The exact commands used during Phase 3 validation, for repeatability:

```bash
# Single package
cd /Users/danielbell/Dev/Auralis-Apple/Auralis/<Package> && \
  xcodebuild test \
    -scheme <Package> \
    -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5" \
  2>&1 | grep -E "^(\*\* TEST|Failing tests:|xcodebuild: error|Test run with)"

# Full sweep (capture pass/fail per package)
for pkg in AccountStorage AccountsCore AccountsFeature AuraUI \
           AuralisPrimaryModels AuralisShellCore CapabilitiesCore \
           ChainProviders CodeScanner ENS ExplorerAdapter NFTKit \
           NFTLibraryFeature OperatorCore PolicyCore ProviderKit \
           ReceiptStorage ReceiptsCore SwiftDataAdapters TokenStorage \
           UserDefaultsAdapters; do
  printf "=== %s ===\n" "$pkg"
  cd "/Users/danielbell/Dev/Auralis-Apple/Auralis/$pkg" && \
    xcodebuild test \
      -scheme "$pkg" \
      -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5" \
    2>&1 | grep -E "^(\*\* TEST|Failing tests:|xcodebuild: error|Test run with)" | head -8
done
```

To get failure detail (compile errors, recorded issues) for a single package:

```bash
cd /Users/danielbell/Dev/Auralis-Apple/Auralis/<Package> && \
  xcodebuild test \
    -scheme <Package> \
    -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5" \
  2>&1 | grep -E "(error:|Failing tests:|recorded an issue)" | head -20
```

## Definition Of Done

- Every local package in `Package dependencies` either:
  - Has its full test suite passing on `iPhone 17 Pro, iOS 26.5`, or
  - Has a deliberately tracked entry in `AuraPlay-Gaps.md` or a sibling gap log explaining why a suite is intentionally excluded
- `AuralisPrimaryModels` and `NFTKit` schemes have their test action enabled
- A new entry is added to `AuraPlay-Status.md` (or a top-level engineering status doc) reflecting the green sweep

## What This Doc Is Not

- Not a Phase 3 plan — Phase 3 is closed (`phase3-tickets.md`, `AuraPlay-Phase5-Handoff.md`)
- Not a new feature backlog — it is purely test-debt restoration
- Not an excuse to refactor production code; if a failing test reveals a real production bug, file it separately and link from here
