# AuralisTestSupport

Shared test scaffolding for the Auralis app target and SwiftPM package test targets. Anything that more than one test target needs lives here.

## Public Surface

| Symbol | Use |
|---|---|
| `Fixture.referenceDate` | Canonical "now" for deterministic time-based tests. Equivalent to `2024-01-01T00:00:00Z`. |
| `Fixture.referenceDatePlus(seconds:)` / `Date.plus(seconds:)` | Offset relative to `referenceDate` for stale/fresh fixture construction. |
| `Fixture.address(repeating:)` | Generates a synthetic 40-character EVM address (e.g. `Fixture.address(repeating: "a")`). |
| `Fixture.Accounts.primary` / `.secondary` / `.tertiary` | Named primary/secondary/tertiary account addresses for fixtures. |
| `Fixture.Contracts.default` / `.alternate` / `Fixture.contract(_:)` | Named or generated contract addresses for fixture NFTs and token holdings. |
| `Fixture.tokenID(_:)` | Stable synthetic token identifier (`"fixture-token-…"`). |
| `Fixture.correlationID(_:)` | Stable synthetic correlation identifier. |
| `NFTFixture` | Shared NFT builder with `.music`, `.image`, `.with { }`, and `.build()`. |
| `MusicLibraryItemFixture` | Shared AuraPlay library item builder with `.music`, `.with { }`, and `.build()`. |
| `StoredReceiptFixture` | Shared persisted receipt builder with `.successful`, `.with { }`, and throwing `.build()`. |
| `TestSupport.temporaryUserDefaults(prefix:)` | Creates a UUID-suffixed `UserDefaults` suite with paired cleanup closure. Use `defer { cleanup() }`. Forwards `SourceLocation` to the `#require` macro. |
| `UserDefaultsBox` | `@unchecked Sendable` wrapper for crossing isolation boundaries with a `UserDefaults` reference. Use instead of retroactively conforming `UserDefaults: Sendable`. |
| `URLProtocolMock` / `URLSession.mocked(_:)` | Per-test URLSession with an injected request handler. No global state. |

## Tag Vocabulary

Tags are declared once on `Testing.Tag` and consumed via `@Suite(.tags(.xxx))`. Suites should pick exactly the tags that describe their cost or category. Multiple tags are allowed.

| Tag | Apply when |
|---|---|
| `.smoke` | A small package or composition-root contract proves a target is wired (one or two `@Test`s). |
| `.slow` | The suite scans the filesystem, parses `.pbxproj`, builds an app composition root, runs persistence-heavy setup, or otherwise takes meaningfully longer than a unit test. |
| `.networking` | The suite touches `URLSession`, `URLProtocol`, provider clients, retry/backoff, or HTTP parsing. |
| `.swiftdata` | The suite constructs a `ModelContainer`, `ModelContext`, or SwiftData-backed store. |
| `.architecture` | The suite scans project structure, package boundaries, `pbxproj` files, manifests, or source imports — i.e. it can fail on harmless refactors. |
| `.privacy` | The suite verifies data deletion, receipt logging, local data classification, or privacy reset contracts. |

### Test Plan Routing

Four test plans live in `Auralis.xcodeproj/xcshareddata/xctestplans/`:

| Plan | Includes | Excludes |
|---|---|---|
| `Auralis-Fast` | Everything except the currently known slow/architecture app suites | Name-based skips for the suites tagged `.slow` and `.architecture` |
| `Auralis-Architecture` | Name-based selection of architecture suites | — |
| `Auralis-Slow` | Name-based selection of suites tagged `.slow` | — |
| `Auralis-Full` | Everything | — |

> **Open follow-up (TEST-007a):** plan filters currently use `selectedTests` / `skippedTests` (name-based) rather than tag-based filtering. Until that conversion lands in the Xcode test-plan editor, any new `.architecture`- or `.slow`-tagged suite must also be added to the relevant plan's name list. See `Unit-Test-Refactor-Tickets.md`.

## Authoring Guidelines

- New helpers belong here only if they are consumed from more than one test target. Keep single-package helpers local.
- Do not import `Testing` from a production-linked module. `AuralisTestSupport` is test-only.
- All helpers that wrap `#expect` or `#require` must accept and forward `sourceLocation: SourceLocation = #_sourceLocation` so failure reports point at the call site, not the helper body.
- Prefer `actor` recorders over `NSLock`-wrapped `final class` doubles. Reserve `@MainActor final class` for doubles whose production protocol is itself `@MainActor`.
- Do not add app-target-only dependencies. If a helper needs an app-only type, move the type into a package first or keep the helper inside `AuralisTests`.
