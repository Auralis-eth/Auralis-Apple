# WalletConnectorKit Journal

## The Big Picture

WalletConnectorKit is the wallet doorway for Auralis. It gives the app one vocabulary for wallet providers, account IDs, WalletConnect pairings, request payloads, return URLs, and session lifecycle work without forcing every screen to know whether the real work is happening through Reown, Coinbase, MetaMask, Privy, Dynamic, SolanaSwift, or a package-local transport.

Think of it as the front desk at a busy venue. The wallets are different guests with different ID cards, entrances, and habits. The app should not need a different clipboard for every guest; WalletConnectorKit makes the clipboard consistent while still recording which entrance each guest actually used.

## Architecture Deep Dive

The core target is the shared language layer. It owns provider metadata, CAIP parsing, request builders, typed errors, lifecycle persistence contracts, deep-link helpers, and the experimental WalletConnect transport boundary. Adapter targets sit beside it and depend on it: Reown handles production WalletConnect/AppKit flows, while Coinbase, MetaMask, Privy, Dynamic, and Solana adapters provide provider-specific doorways.

The important architecture rule is that a connector is not automatically a WalletConnect WebSocket. Reown owns its SDK state. Coinbase is direct request/response. Privy and Dynamic are embedded-wallet/auth providers. SolanaSwift is closer to chain/client plumbing than wallet discovery. The package now models those differences with runtime families, readiness, roles, custody models, support status, and capability flags.

The lifecycle service is deliberately boring. It receives approved sessions, extracts supported wallet addresses, persists a lightweight address-to-topic index, refreshes metadata through injected app adapters, and clears stale saved topics when a connector cannot restore them. It is an expeditor, not a storage engine for every provider's private protocol state.

## The Codebase Map

- `Sources/WalletConnectorKit/Domain/` contains the shared nouns: providers, chains, accounts, namespaces, sessions, lifecycle states, capabilities, and errors.
- `Sources/WalletConnectorKit/Requests/` contains typed JSON values, raw wallet requests, and semantic EVM/Solana operation wrappers.
- `Sources/WalletConnectorKit/Transport/` contains WalletConnect URI/deep-link helpers, app-opening boundaries, return URL coordination, relay JSON-RPC plumbing, and the experimental custom DApp connector.
- `Sources/WalletConnectorKit/Persistence/` contains active-wallet and lightweight session-topic stores.
- `Sources/WalletConnectorKit*Adapter/` targets are adapter rooms for SDK-backed providers.
- `Tests/WalletConnectorKitTests/` covers the core target with Swift Testing.

## Tech Stack & Why

The package uses Swift 6 because the host app is moving toward strict, explicit concurrency boundaries. Actors protect mutable stores and pending request maps. Async/await keeps connector flows readable without callback mazes.

Reown AppKit is the preferred production WalletConnect path because WalletConnect v2 is a full protocol engine, not just a WebSocket. The local IRN code remains useful for tests and experiments, but it is not promoted to production until it has the missing protocol pieces: relay auth, encryption envelopes, settlement, fetch/dedupe, expiry, and complete protocol-state persistence.

Swift Testing is used for package tests because the suite is mostly pure Swift behavior: CAIP parsing, request shapes, callback routing, registry filtering, and persistence contracts. Those tests should stay small, deterministic, and mostly parallel-safe.

Keychain is used for wallet session topic indexing because wallet topics and protocol references should not live in ordinary app defaults. `UserDefaults` is only used for the active public wallet address, which this product treats as a non-secret display/selection value.

## The Journey

### 2026-07-26: The Clean-Room Wallet Kit Begins

The first package shape focused on building a clean vocabulary before wiring live wallets. Providers, chains, CAIP accounts, namespaces, WalletConnect URIs, and request models landed as small value types. That mattered because wallet integrations are easy to make look simple by hiding everything in strings, but the moment Solana joins EVM, string soup starts spilling on the floor.

### 2026-07-26: Lifecycle Without App Gravity

The clean-room package grew a lifecycle service. `WalletSessionAddressExtractor` turns approved sessions into deduplicated supported wallet addresses, `WalletSessionTopicStoring` captures the secure topic-index contract, and `WalletConnectionLifecycleService` coordinates approved sessions, launch restoration, expired-topic cleanup, and wallet removal through injected app adapters.

The service can say "upsert this wallet," "deactivate this wallet," "clean local media," and "refresh metadata" without importing SwiftData, ENS, UIKit, or a wallet SDK. It is the restaurant expeditor, not the chef at every station.

The Solana CAIP reference initially moved to the package-friendly `solana:mainnet` shorthand, but later research corrected that: new wallet output must use the Chain Agnostic mainnet genesis reference, while `solana:mainnet` remains a legacy input alias. Wallet strings are tiny hinges; when they swing the wrong way, an entire integration door sticks.

### 2026-07-27: SDK Adapters Move Into the House

The product direction changed again, and this time the architecture has a sturdier compromise: `WalletConnectorKit` stays the clean kitchen where the nouns live, while SDK-backed adapter targets move into separate rooms of the same package. Reown becomes the main dining room for wallet discovery and WalletConnect-style flows. Coinbase, MetaMask, Privy, Dynamic, and Solana each get their own adapter doorway so we can use direct SDKs without stapling their assumptions onto every caller.

Dependency boundaries are like plumbing. You can run more pipes through the building, but you still want shutoff valves. The core target owns shared state, QR presentation, request builders, capability filtering, and error mapping. The SDK targets depend on the core target, not the other way around.

### 2026-07-27: Readiness Badges for Wallet Engines

After the WalletConnect/Reown/IRN research pass, we added an explicit `WalletConnectorReadiness` contract. This is a small badge with a big job: it lets app composition tell the difference between a live SDK-backed connector and a hand-built transport that can only make it through part of the handshake.

`WalletConnectDAppConnector` now defaults to `experimental` because the custom transport can create pairings, but session settlement and request publishing are not production-complete. That is the wallet equivalent of having a front door and no cash register: useful for rehearsing the entrance, not enough to run the shop.

### 2026-07-27: Five Iterations, Fewer Trapdoors

The research pass turned into practical guardrails. Connector readiness prevents the custom WalletConnect transport from wearing a production badge. Request validation checks namespace/method fit and parameter counts before requests reach Reown, provider SDKs, or the experimental relay path. Return URL handling can be scoped to expected schemes and hosts. Session restoration reports stale topic cleanup and deactivates stale Solana-looking address records as Solana.

Provider metadata now exposes query schemes, universal links, SDK identifiers, and launch families so the host app can build its Info.plist and adapter routing from package facts instead of scattered notes.

### 2026-07-27: Gemini Pass Tightens the Wallet Doorframe

The second research pass sharpened places where mobile wallet integrations usually wobble. We added connector runtime families so a Reown-backed WalletConnect SDK path and the custom IRN experiment cannot be mistaken for interchangeable engines. We also added `WalletSessionProposalRequest`, which can keep broad EVM and Solana capabilities optional instead of over-stuffing required namespaces and inviting wallets to reject the session at the front desk.

Keychain topic storage moved to `AfterFirstUnlockThisDeviceOnly`. The session topic still stays device-bound and unsynchronized, but now the app has a fighting chance to read it during background/return-from-wallet work after the first unlock.

Deep links now carry the native redirect URL when metadata provides it. That gives wallets a clean route home after approval and keeps callback filtering paired with the exact host-app scheme the package expects.

### 2026-07-27: Gemini v2 Adds the Receipt Window

The relay and app-lifecycle contracts became less wishful. `WalletConnectIRNRelayClient` now waits for matching JSON-RPC acknowledgements from `irn_subscribe` and `irn_publish` before reporting success. Writing bytes to a WebSocket is not the same thing as the relay accepting the message; this change gives the custom IRN experiment a receipt window instead of a shrug.

URL callbacks also got a coordinator. `WalletInboundURLCoordinator` deduplicates repeated lifecycle deliveries and queues cold-launch wallet returns until the connector layer is ready. That gives SwiftUI `.onOpenURL`, SceneDelegate, and universal-link routing a single package-level funnel without putting `UIApplication.shared` inside the core target.

Provider errors now have `WalletProviderErrorContext`, which lets adapters record a vendor error type, provider ID, code, and message while still mapping back into package errors.

### 2026-07-27: JSON Params Stop Wearing String Costumes

Wallet requests stopped hiding objects inside strings. `wallet_switchEthereumChain` now carries an actual `{ chainId }` object, `wallet_addEthereumChain` and transactions stay structured, and `wallet_watchAsset` uses the wallet-standard `{ type, options }` shape. Reown gets typed JSON values instead of being asked to decode private string envelopes.

Pending Reown responses now resolve by request ID, not by oldest outstanding request. Two signing prompts in flight should not be a coin toss with better branding.

### 2026-07-27: ChatGPT Research Turns Into New Guardrails

The third research pass was blunt in a useful way: a WalletConnect topic is not a wallet session, and a connector is not always a WebSocket with a topic. So the package now has a capability matrix, connector roles, custody models, and support status. That lets MetaMask's legacy native route, Coinbase's direct request/response model, Privy/Dynamic embedded-wallet auth, Solana RPC helpers, Reown SDK state, and the custom IRN experiment stop pretending to be the same thing in different coats.

Lifecycle state also got more honest. Pairing creation, wallet launch, proposal pending, settlement, offline-connected restoration, disconnecting, and restoration failure are now expressible states instead of being flattened into `pairing`, `awaitingApproval`, or `connected`.

The persistence lesson was the sharpest one. `WalletConnectProtocolState` now makes restoration completeness visible: pairing key, session key, relay identity, expiry, namespaces, and subscribed topics are separate ingredients. A stored topic by itself is just a locker number without the combination.

### 2026-07-27: Provider Claims Learn Some Humility

The latest implementation pass tightened a subtle but important boundary: provider metadata no longer implies the package is using a custom WalletConnect IRN engine. A wallet can be external, support EVM, support Solana, or have a direct SDK route without inheriting `.walletConnectIRN` just because it has a deep link. That flag now belongs to actual connector runtime behavior, not casual catalog inference.

MetaMask also got a more honest label. The legacy native iOS SDK dependency still exists for source compatibility, but the catalog marks that path as deprecated because the upstream repo was archived on February 26, 2026. That is not a reason to panic; it is a reason to route production external-wallet flows through Reown/WalletConnect or a current embedded-wallet product instead of pretending the old native bridge is fresh lumber.

Solana transaction validation also stopped accepting base58 for WalletConnect-shaped transaction requests. Base58 still exists as a vocabulary word because provider-specific deep links may need it, but the shared WalletConnect/Reown request path now expects base64 serialized transactions. The package is learning to ask, "which counter are we standing at?" before accepting a payload.

## Engineer's Wisdom

A wallet package should not make unsupported things look supported. It is better to expose a sharp `experimental` badge, a deprecated provider route, or a typed `unavailable` error than to let the host app discover the truth in a live signing flow.

Typed values beat clever strings. The closer request payloads stay to their real JSON shape, the easier it is to test method order, validate quantities, and bridge into SDKs without accidental double encoding.

Transport is not identity. Provider, connector, transport, custody model, and chain client are separate ideas. Mixing them together creates APIs that feel convenient right up until the first restoration, callback, or provider upgrade.

## If I Were Starting Over...

I would start by making Reown the only production WalletConnect engine and keep the custom IRN path behind an explicit experimental module until it can pass protocol-level restoration tests. I would also separate provider catalog metadata from connector runtime metadata on day one; wallet support is not the same thing as our chosen transport.

For Solana, I would begin with semantic operations and serialized transaction bytes before adding any provider adapter. Solana is not EVM with a different method prefix, and the code gets cleaner when it stops pretending otherwise.
