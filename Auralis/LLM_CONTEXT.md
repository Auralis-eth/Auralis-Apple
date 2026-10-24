# Auralis LLM Context

This is the shortest useful map of the app for an engineer or model that needs to work safely without loading the entire repo.

## What the app is

Auralis is a SwiftUI app that:

- accepts a wallet address, guest-pass account, or connected/in-app wallet
- restores account and chain scope
- fetches NFTs and token holdings from provider-backed services
- stores useful state locally with SwiftData
- exposes that state through `AppTab`'s 11 cases: Home, News, Gas, Music, Receipts, Profile, Search, ERC-20 Tokens, NFT Tokens, Mission Control, and Social — though Social only appears when the relay flag is on, and it currently is not (see Current status)
- runs agent work through a governed runtime that proposes, checks, judges, executes, and receipts every action

**It can sign.** Earlier revisions of this doc said "it is not a signing wallet"; that is no longer
true. `InAppWalletSigner` implements `signPersonalMessage` and `sendTransaction`, and
`WalletActionExecutor` turns an approved action into a signature or on-chain transaction. What keeps
that safe is *gating*, not absence: signing is reachable only in **Operate** mode, only on
approval-resume through the governed pipeline, and only with a receipt. `WalletActionExecutor` never
decides policy itself — it reconstructs an already-approved payload. See `ADR-010` and
`Auralis/docs/reference/Runtime-Kernel.md`.

## The mental model

Think of the app as six layers:

1. Shell: who is the active account, which chain is selected, which root tab/route is open
2. Services: provider access, context building, receipts, balances, holdings, NFT refresh
3. Persistence: SwiftData models for accounts, NFTs, holdings, receipts, playlists, and related state
4. Feature surfaces: the 11 tabs above
5. Chrome and policy: global shell chrome, trust labels, crypto-mode state, safe action wrappers
6. Governed runtime: `RuntimeCore` primitives + `RuntimeKit` host — the action boundary, tool registry, deterministic checks, judge, worklog, receipts, and event bus that any agent-initiated work must pass through

If a bug feels "global," it is usually in the shell, router, scoped persistence, or a shared service seam rather than in an individual leaf view. If it feels like "the agent did something it shouldn't," it is in layer 6 — start at `GovernedToolPipeline`.

Most code now lives in **42 local Swift packages**; the app target is mostly composition (see
`Auralis/Auralis/Assemblies/`) plus live adapters. `ADR-008` governs the boundaries and tests enforce
them, so putting new capability in the app target instead of a package will fail
`ArchitectureBoundaryTests`.

## Core ownership

### App and shell

- `AuralisApp` installs the app scene and model container.
- `ShellStore` (`AuralisShellCore`) owns the shell state machine. Account, chain, logout, privacy reset, account removal, route reset, refresh, and deep-link readiness all flow through `ShellStore.send(_:)` — not through direct binding mutation.
- `MainAuraView` owns the shared router and long-lived services, and *consumes* `ShellStore` state rather than synchronizing it itself.
- `MainAuraShell` and `MainTabView` mount the root UI surfaces.
- `AppRouter` is the navigation store for tabs and pushed detail flows.

### Accounts and scope

- `AccountStore` (`AccountsCore`) is the account seam; SwiftData persistence lives in `AccountStorage`. Keep consumers on the `AccountsCore.AccountStoring` protocol.
- addresses are validation-first and **stored** in lowercase canonical `0x...` form — `EthereumAddress.init` lowercases as it normalizes, which deliberately discards the checksum
- checksum state is therefore a *separate* concern from storage: `EthereumAddressChecksum` / `checksumState(of:)` carries EIP-55 validity, and the runtime's `address.format` check enforces it
- chain scope is per-account and should drive what data appears

### Networking and provider seams

- `NFTFetcher` (`NFTKit/NFTProviderAdapters`, an actor) handles validation, retries, pagination, and provider fetch orchestration
- `NFTService` (`NFTKit/NFTPresentation`) coordinates refresh and local persistence
- `TokenHoldingsProviding` (`ProviderKit`) is the holdings fetch seam; `SwiftDataTokenHoldingsStore` + `TokenHolding` (`TokenStorage`) persist it
- provider support sits behind injected seams rather than living in views
- provider-facing UI expects typed failures — map transport errors into `ProviderAbstractionError` or `NFTProviderFailure` instead of leaking raw `URLError`s
- degraded mode and cached-data behavior are part of the intended product path, not edge cases

### Context and receipts

- `ContextSnapshot` / `ContextService` (app-side) are the shell-facing context contract for chrome surfaces
- **distinct from** the runtime's `ContextBundle` / `ContextBundleContract` (`RuntimeCore`), which is the governed, provenance-carrying context that model and tool work consume. Do not conflate the two.
- receipts are append-only, hash-chained, and P-256 signed (`ReceiptsCore` protocols, `ReceiptStorage` persistence), with sanitization and reset seams
- receipt integrity is a **local** tamper-evidence claim; export verification must pin `provenanceTrustAnchor()` through a channel separate from the exported JSON

### Music

- active code is under `Auralis/Auralis/MusicApp/AuraPlay/` and the `MusicFeature` package. The old `MusicApp/AI/` namespace is **gone** — do not reintroduce it.
- playback internals are package-owned: `AudioEngineController` (`AuraPlayAudioEngine`) and `AuraPlayVideoEngine`
- `MusicLibraryIndex` (`MusicFeature/Sources/MusicFeature/Services/`) builds a local library view from persisted/scoped NFT data

### Governed runtime

- `RuntimeCore` holds the primitives; `RuntimeKit`'s `RuntimeHost` is the composition root and the only supported entry point for app callers
- `GovernedToolPipeline` is the single execution path: resolve tool → validate schema → deterministic checks → judge → (escalate → approve → resume) → execute → receipt → worklog + events
- Mission Control (`MissionControlFeature`) is the operator console over that runtime. `MissionControlRootView.Section` currently has **16** cases: Home, Run a Goal, Timeline, Activity, Sessions, Context, Approvals, Powers, Receipts, Operators, Artifacts, Playbooks, Routines, Performance, Report Cards, Mode. Count from the enum, not from docs — several still say 14, which predates Run a Goal and Report Cards.
- full contract reference: `Auralis/docs/reference/Runtime-Kernel.md`

## Where to look first

- auth, shell, Home, Search, shared UI: `Auralis/Auralis/Aura/`
- dependency composition: `Auralis/Auralis/Assemblies/`
- accounts and holdings: `Auralis/Auralis/Accounts/`
- domain models: `Auralis/Auralis/DataModels/` (shared schema in `AuralisPrimaryModels` / `AuralisPrimaryPersistence`)
- provider and refresh logic: `Auralis/Auralis/Networking/` + `ProviderKit`, `NFTKit`, `ChainProviders`
- active music stack: `Auralis/Auralis/MusicApp/AuraPlay/` + `MusicFeature`
- governed runtime and agent work: `RuntimeCore`, `RuntimeKit`, `MissionControlFeature`

## Current status

Phase 0 (shell/product surfaces) closed long ago. The current program is **Phase 1 — Mission Control /
operator console**, which is code complete and green; what remains is a gate a compiler cannot close.

- all seven Phase 1 exit criteria are met: Mission Control is the operator surface, work is visible and
  inspectable, playbooks/artifacts/routines are first-class, governance is fixed and visible
- the runtime kernel is code complete and CI-covered — verified 2026-09-06: RuntimeCore 247 tests / 35
  suites, EvalCore 35/4, TrustedUIKit 13/3, all green
- **open, and not closeable by compiling:** Secure Enclave signing on hardware (MC-Device-011),
  BGTaskScheduler background firing on hardware (MC-Device-010), the on-device VoiceOver / Dynamic Type
  sweep, and the App Review checklist
- Social v1 is code-complete but **off**: `AURALIS_SOCIAL_RELAY_ENABLED = NO` in both
  `Auralis-Debug.xcconfig` and `Auralis-Release.xcconfig`, and the Social tab only appears when relay
  social is enabled. Its external gates (relay ToS/quota, two-device QA) are not closed. Check the
  xcconfig before making any claim about social being live.
- Phase 2 (bounded automation) has not started; its entry gate is the Phase 1 device/review gate
- the app is English-only on purpose; localization wiring and translations land together in one later pass

Status detail lives in `Auralis/docs/plans/OperatorConsole-Ship-Readiness.md`,
`Phase-1-Known-Limitations.md`, and `OperatorConsole-Ship-Readiness.md`.

## Rules that matter when editing

- prefer SwiftUI-first, state-driven code
- prefer Swift Concurrency over callback-heavy APIs; avoid Combine
- prefer injected dependencies and instance ownership over `static` helpers
- avoid force unwraps
- preserve the Aura visual language unless the task is explicitly a redesign
- keep route logic centralized; do not scatter duplicate navigation state into random views
- new capability goes in a package, not the app target; the app composes (ADR-008, test-enforced)
- never bypass `RuntimeHost` / `GovernedToolPipeline` to reach a tool executor — also test-enforced
- attribution is compiler-enforced: a recorded act needs a real actor, authority, and correlation ID
- register accessibility identifiers in `AuraUI/Sources/AuraUI/A11yID.swift` before merge
- NFT IDs and wallet addresses are public identifiers in this product and may appear in UI, logs, and
  receipts; secrets, keys, tokens, cookies, and seed material still require redaction or hashing

## Repo gotchas

- `NFT.swift` is oversized and carries more than one responsibility
- account, chain, and routed state are tightly coupled; changing one can ripple through launch, refresh, and logout behavior
- deep links may arrive during cold start and should be replayed only when the shell is ready
- receipt routing is intentionally conservative
- provider fallback responses may be thinner than the happy-path schema; decoding and persistence must degrade safely
- audio loading already has stale-task cancellation concerns; preserve that discipline
- Observe-only is **crypto-scoped**: it constrains wallet actions, not the app. The rest of the product is full CRUD.
- `swift test` needs the Xcode-beta toolchain here; the Command Line Tools toolchain lacks `Testing.framework`
- privacy reset must reach the `OperatorRuntimeStorage` container too, not just the app's main model container

## If you need to answer "what should I change?"

- shell-state bug: inspect `ShellStore`, `MainAuraView`, `MainAuraShell`, `MainTabView`, `AppRouter`
- account or chain bug: inspect `AccountStore`, `EOAccount`, shell restore logic
- NFT loading bug: inspect `NFTFetcher`, `NFTService`, local persistence paths
- token bug: inspect `TokenHoldingsProviding`, `SwiftDataTokenHoldingsStore`, `TokenHolding`, token routes in the shell
- music bug: inspect `AudioEngineController` (`AuraPlayAudioEngine`), `MusicLibraryIndex` (`MusicFeature`), views under `MusicApp/AuraPlay/`
- trust/privacy bug: inspect receipt sanitization, trust labels, settings reset surfaces, and outbound-action seams
- agent/governance bug: inspect `GovernedToolPipeline`, the deterministic check registry, and the worklog — the worklog is the primary source of what actually happened
- wallet signing bug: inspect `WalletActionExecutor`, `InAppWalletSigner`, crypto mode, and the approval-resume path

## Docs worth reading next

- `AGENTS.md` — conventions and durable contracts
- `Auralis/docs/reference/Runtime-Kernel.md` — the governed runtime's contracts, phase-free
- `Journal.md` — narrative history of why things are the way they are
- `Auralis/docs/decisions/` — ADRs, notably ADR-008 (package boundaries) and ADR-010 (crypto-scoped Observe)
- `Auralis/docs/plans/OperatorConsole-Ship-Readiness.md` and `Phase-1-Known-Limitations.md` — current program status and what is honestly unverified
- `Auralis/docs/plans/P0-Future-Work.md`
- `Auralis/docs/plans/P0-Physical-Device-QA-Suite.md`
- `Auralis/docs/plans/P0-UI-Design-Audit-Checklist.md`

Doc-alignment note (2026-09-07): this file had drifted badly. The three `P0-*` entries were listed as
repo-root filenames after the move into `Auralis/docs/plans/`; `P0-Implementation-Order-Plan.md` and
`P0-Hard-Closeout-Report.md` were listed and no longer exist anywhere in the tree. Separately, the
"not a signing wallet" claim, the `MusicApp/AI/` paths, the `AudioEngine` / `TokenHoldingsStore` type
names, and the "Current Phase 0 status" section were all stale and are corrected above.
