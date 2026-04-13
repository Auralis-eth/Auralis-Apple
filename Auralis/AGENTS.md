# Auralis Project Memory

## Project Overview

Auralis is a SwiftUI app for wallet-based NFT discovery, Aura-branded browsing, gas utilities, and an NFT-driven music experience.

The shell flow is:

- authenticate by pasting/scanning a wallet or selecting a guest pass
- restore account/chain state
- fetch and persist NFTs with SwiftData
- route across Home, News, Gas, Music, ERC-20 Tokens, and NFT Tokens

## Architecture Decisions

- `MainAuraView` owns shell state, account restoration, deep-link handling, and the shared router.
- `AppRouter` is the central navigation store for selected tab, per-tab back stacks, and routed errors.
- `MainTabView` renders top-level tabs only. Pushed detail state lives in per-tab paths.
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

## Quirks And Gotchas

- `NFT.swift` is oversized and contains multiple responsibilities.
- Account changes should reset routed detail stacks to root.
- Guest passes are a lightweight onboarding shortcut to curated public wallets, not a separate demo-data product mode.
- Deep links may arrive during cold start; queue them until shell state is ready.
- Receipt routing is intentionally safe-fail for now. Full receipt support is deferred.
- The active audio path lives under `MusicApp/AI/`; `MusicApp/OLD/` is legacy until proven otherwise.
