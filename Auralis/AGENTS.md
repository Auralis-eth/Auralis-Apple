# Auralis Project Memory

## Project Overview

Auralis is a SwiftUI app for wallet-based NFT discovery, Aura-branded browsing, gas utilities, and an NFT-driven music experience.

The shell flow is:

- authenticate or select a demo account
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

## Quirks And Gotchas

- `NFT.swift` is oversized and contains multiple responsibilities.
- Account changes should reset routed detail stacks to root.
- Deep links may arrive during cold start; queue them until shell state is ready.
- Receipt routing is intentionally safe-fail for now. Full receipt support is deferred.
