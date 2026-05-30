# Auralis Project Memory

## Project Overview

Auralis is a SwiftUI app for wallet-based NFT discovery, Aura-branded browsing, gas utilities, and an NFT-driven music experience.

The shell flow is:

- authenticate by pasting/scanning a wallet or selecting a guest pass
- restore account/chain state
- fetch and persist NFTs with SwiftData
- route across Home, News, Gas, Music, ERC-20 Tokens, and NFT Tokens

## Architecture Decisions

- `AuralisShellCore` owns the package-level shell state machine boundary: `ShellStore`, shell state/actions, collaborator protocols, route effects, and deep-link replay rules.
- App-side shell files provide live adapters only, such as SwiftData account resolution, NFT refresh coordination, receipt logging, and router effect handling.
- `MainAuraView` owns the shared router and long-lived services, but it now consumes `ShellStore` state instead of synchronizing `currentAddress` / `currentAccount` / `currentChain` / `currentChainId` itself.
- `AppRouter` is the central navigation store for selected tab, per-tab back stacks, and routed errors.
- `MainTabView` renders top-level tabs and sends shell intents upward. It no longer repairs shell state through `onChange` fan-out.
- Home is a launcher tab, not a second navigation hierarchy.
- Shared NFT detail is reused across Music, News, and NFT Tokens.
- Deep links are parsed first, then replayed only when shell state is ready.

## Important Conventions

- Prefer SwiftUI-first, state-driven code.
- Prefer Swift Concurrency over callback-heavy APIs.
- Prefer instance methods and injected dependencies over `static` helpers unless type-level behavior is genuinely the right model.
- Prefer Swift Testing over XCTest for unit and integration-style tests.
- Prefer parameterized tests over many near-duplicate individual tests.
- XCUI tests still use XCTest/XCUIAutomation because that is the platform tool.
- Keep route logic centralized in the shell/router rather than scattering ad hoc navigation state across views.
- `@Query` may project shell-scoped SwiftData data for presentation, detail lookup, and the single `MainAuraView` account resolver bridge. It must not become a shell coordinator: active account, active chain, logout/privacy reset, account removal, route reset, refresh, and deep-link readiness changes flow through `ShellStore.send(_:)` or collaborators invoked by `ShellStore`.
- Treat NFT IDs and Ethereum wallet addresses as public identifiers in this product. They may be shown in UI, logs, and receipts when useful; do not flag their mere presence as a privacy issue. Secrets, API keys, auth tokens, cookies, private keys, seed material, copied sensitive text, and provider internals still require redaction or hashing.

## Build And Run

- Use the `Auralis` scheme.
- Build with Xcode or the MCP `BuildProject` tool.
- Unit tests live in `AuralisTests`.
- UI tests live in `AuralisUITests`.

## High-Value Docs

- `LLM_CONTEXT.md` is the fastest repo orientation file for engineers or models that need the working mental model without rereading the entire codebase.
- `P0-Future-Work.md` is the post-Phase-0 backlog and should be updated when hardening or architecture follow-on work becomes clearer.
- `P0-Physical-Device-QA-Suite.md` is the real-device manual QA contract for Phase 0.
- `P0-UI-Design-Audit-Checklist.md` is the product/design quality checklist for Phase 0 surfaces.
- `AuralisPrimaryModels/` is a local Swift package with two targets: pure domain values live in `AuralisPrimaryModels`, while the remaining shared SwiftData schema cluster lives in `AuralisPrimaryPersistence`.
- `AuralisShellCore/` is the local Swift package for shell state, shell actions, `ShellStore`, dependency protocols, and deep-link routing rules. Keep live app infrastructure out of this package.
- `MusicFeature/` is the local Swift package for the AuraPlay music feature boundary. It currently owns AuraPlay domain values and service protocols; keep `AudioEngine`, SwiftData live adapters, and app composition in the app target until later migration phases deliberately move them.
- `SwiftDataAdapters/` is the local Swift package for shared SwiftData mechanics such as rollback-safe and undoable mutation helpers. It should provide tools, not domain-specific stores.
- `AccountStorage/` is the local Swift package for SwiftData-backed account persistence. Keep protocol consumers on `AccountsCore.AccountStoring`; only composition and storage tests should import `AccountStorage`.
- `ReceiptStorage/` is the local Swift package for SwiftData-backed receipt persistence and destructive receipt reset adapters. Keep protocol/logging consumers on `ReceiptsCore`; only concrete builders and storage tests should import `ReceiptStorage`.
- Receipt integrity is a local tamper-evidence contract. Receipts are hash-chained in SwiftData and checked against Keychain-protected account heads on the same device; externally enforceable proof requires trusted infrastructure or signed receipt-head sync.

## Quirks And Gotchas

- `NFT.swift` is oversized and contains multiple responsibilities.
- Account, chain, logout, and deep-link shell transitions should go through `ShellStore.send(_:)`, not direct binding mutation.
- Account changes should reset routed detail stacks to root.
- Guest passes are a lightweight onboarding shortcut to curated public wallets, not a separate demo-data product mode.
- Deep links may arrive during cold start; queue them until shell state is ready.
- Receipt routing is intentionally safe-fail for now. Full receipt support is deferred.
- The shipping music UI now lives under `MusicApp/AuraPlay/`, while `MusicApp/AI/Audio Engine/` still provides the playback bridge.
- Provider-facing UI expects typed failures. Prefer mapping transport/provider errors into `ProviderAbstractionError` or `NFTProviderFailure` instead of leaking raw `URLError`s upward.
- Reuse the shared `RetryAfterSupport` helper for backoff parsing. The stack now supports both numeric and HTTP-date `Retry-After` headers.
- Shared SwiftUI motion should flow through `AuraMotionPolicy` from AuraUI. Build it from `@Environment(\.accessibilityReduceMotion)` so decorative loops and state-change animations honor Reduce Motion consistently.
- `AuraHaptics` intentionally remains tied to Reduce Motion for 0.1.0. A separate haptics preference is a future product/settings decision, not a Phase 4 behavior change.
