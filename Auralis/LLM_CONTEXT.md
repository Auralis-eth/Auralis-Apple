# Auralis LLM Context

This is the shortest useful map of the app for an engineer or model that needs to work safely without loading the entire repo.

## What the app is

Auralis is a SwiftUI app that:

- accepts a wallet address or guest-pass account
- restores account and chain scope
- fetches NFTs and token holdings from read-only provider-backed services
- stores useful state locally with SwiftData
- exposes that state through Home, Search, News, Tokens, Receipts, and Music

It is not a signing wallet. It is a read-only, stateful shell with multiple product surfaces sharing the same identity and data spine.

## The mental model

Think of the app as five layers:

1. Shell: who is the active account, which chain is selected, which root tab/route is open
2. Services: provider access, context building, receipts, balances, holdings, NFT refresh
3. Persistence: SwiftData models for accounts, NFTs, holdings, receipts, playlists, and related state
4. Feature surfaces: Home, Search, News, Tokens, Receipts, Music
5. Chrome and policy: global shell chrome, trust labels, mode state, safe action wrappers

If a bug feels "global," it is usually in the shell, router, scoped persistence, or a shared service seam rather than in an individual leaf view.

## Core ownership

### App and shell

- `AuralisApp` installs the app scene and model container.
- `MainAuraView` is the main shell owner.
- `MainAuraShell` and `MainTabView` mount the root UI surfaces.
- `AppRouter` is the navigation store for tabs and pushed detail flows.

### Accounts and scope

- `AccountStore` is the account CRUD seam.
- addresses are validation-first and stored in lowercase canonical `0x...` form for Phase 0
- chain scope is per-account and should drive what data appears

### Networking and provider seams

- `NFTFetcher` handles validation, retries, pagination, and provider fetch orchestration
- `NFTService` coordinates refresh and local persistence
- provider-backed read-only support sits behind injected seams rather than living in views
- degraded mode and cached-data behavior are part of the intended product path, not edge cases

### Context and receipts

- `ContextSnapshot` is the shared shell-facing context contract
- `ContextService` builds the snapshot consumed by shell/chrome surfaces
- receipts are append-only operational records with sanitization and reset seams

### Music

- active code is under `Auralis/Auralis/MusicApp/AI/`
- `AudioEngine` is the shared playback engine
- `MusicLibraryIndex` builds a local library view from persisted/scoped NFT data
- `Auralis/Auralis/MusicApp/OLD/` is legacy; do not change it unless you confirm it is active

## Where to look first

- auth, shell, Home, Search, shared UI: `Auralis/Auralis/Aura/`
- accounts and holdings: `Auralis/Auralis/Accounts/`
- domain models: `Auralis/Auralis/DataModels/`
- provider and refresh logic: `Auralis/Auralis/Networking/`
- active music stack: `Auralis/Auralis/MusicApp/AI/`

## Current Phase 0 status

Phase 0 is effectively closed for the current slice except for deeper follow-on hardening and manual QA expansion. Highlights:

- shell, chrome, context inspector, and receipts are in place
- Home, Search, Music, and token surfaces are mounted
- provider-backed holdings and a local music index exist
- privacy/security and baseline-release docs exist
- the main remaining open operational gap called out by closeout docs is manual UI QA on the ERC-20 surface

## Rules that matter when editing

- prefer SwiftUI-first, state-driven code
- prefer Swift Concurrency over callback-heavy APIs
- prefer injected dependencies and instance ownership over `static` helpers
- avoid force unwraps
- preserve the Aura visual language unless the task is explicitly a redesign
- keep route logic centralized; do not scatter duplicate navigation state into random views

## Repo gotchas

- `NFT.swift` is oversized and carries more than one responsibility
- account, chain, and routed state are tightly coupled; changing one can ripple through launch, refresh, and logout behavior
- deep links may arrive during cold start and should be replayed only when the shell is ready
- receipt routing is intentionally conservative
- provider fallback responses may be thinner than the happy-path schema; decoding and persistence must degrade safely
- audio loading already has stale-task cancellation concerns; preserve that discipline

## If you need to answer "what should I change?"

- shell-state bug: inspect `MainAuraView`, `MainAuraShell`, `MainTabView`, `AppRouter`
- account or chain bug: inspect `AccountStore`, `EOAccount`, shell restore logic
- NFT loading bug: inspect `NFTFetcher`, `NFTService`, local persistence paths
- token bug: inspect `TokenHoldingsStore`, `TokenHolding`, token routes in the shell
- music bug: inspect `AudioEngine`, `MusicLibraryIndex`, active music views under `AI/V1`
- trust/privacy bug: inspect receipt sanitization, trust labels, settings reset surfaces, and outbound-action seams

## Docs worth reading next

- `AGENTS.md`
- `Journal.md`
- `Auralis/P0-Implementation-Order-Plan.md`
- `Auralis/P0-Hard-Closeout-Report.md`
- `P0-Future-Work.md`
- `P0-Physical-Device-QA-Suite.md`
- `P0-UI-Design-Audit-Checklist.md`
