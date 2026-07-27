# WalletConnectorKit Journal

## The Big Picture

WalletConnectorKit is the wallet handshake counter at the front of Auralis. It knows how to describe wallets, start WalletConnect-style pairings, remember sessions, and hand the app a clean QR or deep-link payload. Think of it as the host who checks IDs, points people to the right table, and keeps the reservation book tidy.

## Architecture Deep Dive

The package is split between pure wallet domain types, transport contracts, persistence, registry/catalog data, request builders, and crypto boundaries. The domain layer is the menu everyone agrees on. The transport layer is the phone line to wallets and relays. The app-opening boundary is the doorman: the package can ask whether a wallet URL can open, but the host app owns the platform call.

## The Codebase Map

- `Sources/WalletConnectorKit/Domain/` holds wallet accounts, connections, namespaces, and providers.
- `Sources/WalletConnectorKit/Transport/` owns WalletConnect pairing values, return URL handling, request routing contracts, and app-opening boundaries.
- `Sources/WalletConnectorKit/Crypto/` contains envelope and relay auth helpers.
- `Sources/WalletConnectorKit/Persistence/` stores wallet sessions.
- `Sources/WalletConnectorKit/Registry/` lists known wallet providers.
- `Tests/WalletConnectorKitTests/` covers domain, transport, registry, and session-store behavior.

## Tech Stack & Why

Swift Package Manager keeps the wallet connector independently buildable and testable. Swift concurrency is used for connection and request flows because wallet work is naturally asynchronous: open an app, wait for approval, wait for relay messages, then resolve or time out. The package intentionally has no wallet SDK dependency; Reown and WalletConnect SDKs are references, not ingredients in production source.

## The Journey

### 2026-06-29: Reset to Reown AppKit Only

We deliberately stopped trying to be a WalletConnect implementation. The package had grown a parallel universe: local relay clients, envelope crypto, session stores, wallet registries, request builders, fake transports, and tests for all of it. Useful learning, but too much machinery when the product decision is "use Reown AppKit first, learn from what they provide, then customize only when we have a real reason."

The reset keeps the package as a small adapter around Reown AppKit. The remaining local code is just the Auralis-facing shape: supported chains, parsed wallet accounts, session summaries, namespace method lists, configuration, and the main `ReownAppKitWalletCoordinator`. Everything that tried to manually speak WalletConnect IRN went away. It is like replacing a home-built train system with a ticket counter for the actual railway.

Build result: the focused `WalletConnectorKit` scheme built successfully after the reset.

Follow-up alignment pass: the coordinator now reads `PROJECT_ID` from the app bundle first, then environment, and fails with a useful message if no project ID exists. It applies AppKit session params before presentation, uses `AppKit.present(from: nil)`, handles callbacks through `AppKit.instance.handleDeeplink(url)`, and exposes a compact `personal_sign` proof that reads the connected address from AppKit and launches the current wallet for approval.

### 2026-06-29: Reown Product Names and Swift 6 Singleton Checks

The package failed before compilation with `product 'WalletConnectRelay' required by package 'walletconnectorkit' target 'WalletConnectorKit' not found in package 'reown-swift'`. The trick was that Reown 2.3.0 has targets named `WalletConnectRelay` and `WalletConnectSigner`, but it does not vend them as SwiftPM products. SwiftPM only lets a dependency target depend on another package's public products, not arbitrary internal targets. The manifest was asking the bouncer for a guest who was working in the kitchen.

The fix was to keep the public Reown products this package actually needs: `ReownAppKit` and `WalletConnectNetworking`. Once the package graph resolved, Swift 6 reached the source files and flagged Reown's singleton-style `AppKit.instance` as shared mutable state. The coordinator is already `@MainActor`, so the bridge now uses `@preconcurrency` imports with a clear invariant: all AppKit access stays inside that main-actor coordinator until Reown publishes full Swift 6 annotations.

A second Swift 6 warning appeared in the local `URLSessionWebSocketTask` adapter. Reown's `WebSocketConnecting` protocol is callback based and pre-concurrency, so the adapter now carries an explicit `@unchecked Sendable` conformance with a safety note. That is not a decoration; it is a promise that each socket instance is owned as a single connection lifecycle by Reown's networking layer.

Build result: the focused `WalletConnectorKit` scheme built successfully after the manifest and concurrency bridge fixes.

### 2026-06-29: Package-Owned Wallet Surface and Guard Rails

The Reown adapter grew the pieces that belong in the package instead of the host app: a reusable SwiftUI `WalletConnectorPanel`, configuration validation that reports missing `PROJECT_ID`, URL scheme, query schemes, and app-group alignment, and a Swift Testing target for the pure wallet logic. The package is now less like a mystery box and more like a preflight checklist taped to the cockpit: it cannot install the app's entitlements, but it can tell you exactly what the app forgot to wire.

Crypto got an important course correction. The old placeholder claimed Keccak work with SHA-256, which is the kind of bug that wears a fake mustache and gets past casual review. The default provider now computes Ethereum Keccak-256 directly in the package, while public-key recovery is explicitly injectable through `WalletConnectorCryptoProvider`. That keeps basic AppKit/signing flows honest without pretending SIWE-grade recovery exists when the host has not supplied it.

The URLSession socket bridge also lost its remaining Swift 6 sendability warning by boxing the legacy callback before handing it to the send completion closure. Small fix, but it states the ownership boundary clearly: Reown owns the socket lifecycle, and our adapter only bridges the callback world into Swift 6's stricter checker.

One sneaky validation bug got corrected after the setup audit: the package can accept a Reown project ID directly in `ReownAppKitConfiguration`, but the preflight checker only looked in the host app's `Info.plist` and launch environment. That was like asking someone for ID after they had already handed it to you. Validation now honors the explicit configuration value first, then falls back to the host-app sources, and a focused Swift Testing case guards that behavior.

Lifecycle follow-through: signing is no longer a half-lit dashboard bulb. The coordinator now records typed signing approvals and rejections with request ID, topic, chain, payload, and JSON-RPC failure details. It also records connection approval/rejection, disconnection reasons, auth results, wallet events such as account or chain changes, and expiry transitions when stale sessions are refreshed. The host app still has to perform real wallet QA, but the package now has the lifecycle hooks it needs instead of asking callers to reverse-engineer strings.

AppKit coverage pass: the package now wraps the remaining useful Reown AppKit surface instead of leaving it as a trapdoor. We added package-owned types for pairing URIs, pairings, custom wallets, custom chain presets, SIWE auth params/results, and AppKit JSON-RPC requests. The coordinator can create QR/pairing URIs, refresh pairings, extend sessions, send arbitrary AppKit-supported RPC requests, read the current address, snapshot Reown's selected chain, set fresh SIWE auth params, and toggle Reown analytics. It is still intentionally not a replacement for live wallet QA; it is the control panel and instrumentation for that QA.

Build result: `BuildProject(buildForTesting: true)` succeeded, and `RunAllTests` passed with 30 executed test cases because parameterized Swift Testing cases are counted individually at runtime.

### 2026-07-03: Unit Tests Become the Flight Recorder

The package tests grew from a handful of headline checks into a proper flight recorder for the wallet connector's value layer. The new suites cover CAIP parsing, exact chain metadata, RPC method names, Codable round trips, configuration preflight warnings, Keccak vectors, and the coordinator's pure mapping/state helpers. None of these tests opens a wallet or talks to Reown's network; they test the knobs and gauges we own.

The useful lesson: wallet integrations have a lot of tiny strings that look harmless until one changes shape. `eip155:8453`, `wallet_addEthereumChain`, `LSApplicationQueriesSchemes`, and `group.` entitlements are all small labels with big blast radiuses. Good unit tests pin those labels down like luggage tags before the live-wallet QA trip begins.

### 2026-07-26: The Clean-Room Rule Wins

The wallet connector briefly wandered into the wrong kitchen. The Markdown plans said one thing clearly: use Reown and WalletConnect as maps, not as cookware. Production `WalletConnectorKit` should be SDK-free, with the host app owning presentation and platform URL opening. The code had drifted into a Reown AppKit coordinator, a SwiftUI panel, AppKit configuration validation, and a SwiftPM dependency on `reown-swift`. That was not "not integrated yet"; it was the wrong dependency boundary.

The repair reset the package to the documented clean-room baseline. The provider catalog now covers the Phase 4 families: Rabby, Rainbow, Coinbase Wallet, MetaMask, Phantom, Backpack, Solflare, Privy, Dynamic, and Generic Wallet. WalletConnect URI formatting/parsing lives in the package, nested deep-link encoding happens exactly once, return URLs are classified without dispatching SDK envelopes, and `WalletConnectDAppConnector` talks through injected transport and app-opening protocols. The app can later bring a QR sheet or wallet picker, but the reusable wallet rules already live where they belong.

The war story is simple: a third-party SDK can make a demo look alive while quietly moving the architecture's center of gravity. The fix was to make the package own the language of the feature first — CAIP accounts, namespace proposals, pairings, sessions, request IDs, and typed errors — then leave live relay and app UI as follow-up wiring.

## Engineer's Wisdom

When a package dependency looks overstuffed, check the architecture decision before debugging the manifest. Product names are the public contract; target names are implementation detail, but the more important question is whether the dependency belongs in the package at all. For wallet connection, the durable boundary is our own domain and transport protocols; SDKs stay outside unless a later accepted plan deliberately adds an adapter.

## If I Were Starting Over...

I would start with the clean-room package contracts and fake relay tests before touching any live wallet SDK. A good wallet package should first prove it can describe a session, validate an account, create a pairing URI, and persist a session without opening a single real wallet.

### 2026-07-26: Lifecycle Without App Gravity

The clean-room package now owns more than nouns. `WalletSessionAddressExtractor` turns approved sessions into deduplicated supported wallet addresses, `WalletSessionTopicStoring` captures the secure session-topic contract, `KeychainWalletSessionTopicStore` uses foreground-only device-bound storage with iCloud synchronization explicitly disabled, and `WalletConnectionLifecycleService` coordinates approved sessions, launch restoration, expired-topic cleanup, and wallet removal through injected app adapters.

That last part matters. The service can call "upsert this wallet," "deactivate this wallet," "clean local media," and "refresh metadata" without importing SwiftData, ENS, Spotlight, UIKit, or a wallet SDK. It is the restaurant expeditor, not the chef at every station. The host app still has to provide real adapters, but the lifecycle rules are no longer scattered across a future sheet, a future relay client, and a future settings button.

The Solana CAIP reference also moved to `solana:mainnet`, matching the Phase 4 contract. Wallet strings are tiny hinges; when they swing the wrong way, an entire integration door sticks.
