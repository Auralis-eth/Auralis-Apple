# WalletConnectorKit QA Checklist

Use this checklist after the SDK-backed package work is wired into a host app.
The core `WalletConnectorKit` target remains SDK-free, while adapter targets may import Reown and wallet-specific SDKs.

## Package Contract

| Test | Expected result |
| --- | --- |
| Core dependency boundary | `WalletConnectorKit` does not import Reown, wallet SDKs, UIKit, or SwiftUI. |
| Adapter products | Reown, Coinbase, MetaMask, Privy, Dynamic, and Solana adapter products are available as separate package products. |
| Provider catalog | Rabby, Rainbow, Coinbase Wallet, MetaMask, Phantom, Backpack, Solflare, Privy, Dynamic, and Generic Wallet are present. |
| Chain and method filtering | EVM providers appear for EVM methods; Solana methods only return Solana-capable providers. |
| CAIP parsing | Supported EVM and Solana CAIP-2 / CAIP-10 values parse, new Solana output uses the canonical mainnet genesis reference, legacy `solana:mainnet` values still restore, and malformed values are rejected. |
| WalletConnect URI | `wc:` URI formatting and parsing round-trip with a single nested percent-encoding pass. |
| Relay acknowledgements | IRN subscribe, publish, and unsubscribe calls do not report success until the relay returns a matching JSON-RPC acknowledgement. |
| Missed-message recovery | On reconnect and cold-launch restore the transport drains `irn_fetchMessages` pages until `hasMore == false`, replays queued messages onto the event stream, and only then re-subscribes each tracked topic. Restore fails closed if relay recovery fails, preserving persisted user state instead of exposing a half-live session. |
| Session lifecycle updates | `wc_sessionSettle` and `wc_sessionUpdate` re-scope namespaces/accounts to the proposed chain set (dropping unproposed-chain accounts) and must satisfy every required namespace chain/method/event/account grant before a session is exposed or retained; update resets `addressVerified` when accounts change; `wc_sessionExtend` adopts a new expiry only when not-earlier-than-current and within the 7-day cap (out-of-range ignored); `wc_sessionEvent` (`accountsChanged`/`chainChanged`) surfaces to the host. Each acks with its response tag and re-acks duplicates idempotently. |
| Relay subscription callbacks | Inbound `irn_subscription` messages surface subscription events and send a matching JSON-RPC `result: true` acknowledgement back to the relay. |
| Protocol restoration state | `WalletConnectProtocolState.restorationStatus` is a standalone domain model (used for host-side gating/telemetry) that refuses topic-only records and requires pairing key, session key, relay identity, expiry, and namespace state before reporting a resumable session. It is **not** the transport's restoration gate. The custom transport restores independently via `WalletConnectPersistedSession` + `WalletConnectSessionStatePersisting`: on settle it persists the session symmetric key, local X25519 key-agreement key, pairing lineage, and metadata, then rehydrates + re-subscribes on the next launch. Restoration requires a parseable session symmetric key and a non-expired record (expired records are pruned); unreadable keychain state throws and must not trigger topic deletion/account deactivation, while corrupt JSON is purged as already lost. The self key-agreement key is persisted for every newly settled session (only pre-existing legacy records may omit it, in which case the session still restores for `type0` request/response traffic). |
| Ownership verification | Settling a session proves only a *claimed* address. `WalletConnectDAppConnector.verifyOwnership(of:in:)` issues a canonical EIP-4361 (SIWE) `personal_sign` challenge binding app domain, URI, chain id, a high-entropy nonce, and an issued-at/expiration window, and verifies recovery via an injected `WalletConnectorCryptoProvider` (which receives the already-hashed EIP-191 digest); it fails closed (throws) when no recovery-capable provider is configured. Host flows that use wallet identity for sensitive state must either check `addressVerified == true` before use or configure `WalletConnectionLifecycleService(ownershipPolicy: .requireVerified)` so unverified sessions are rejected before persistence. |
| QR presentation | Pairing presentation exposes provider, URI, QR payload, expiry, optional open URL, and connection state. |
| Request builders | Personal sign, typed-data sign, send transaction, switch chain, add chain, watch asset, Solana sign message, Solana sign transaction, sign-and-send, and sign-all produce deterministic typed JSON payloads. |
| Semantic operations | Public EVM and Solana operation wrappers produce typed `WalletRequest` values, while raw requests remain an explicit escape hatch. |
| Request validation | EVM methods are rejected on Solana namespaces, Solana methods are rejected on EVM namespaces, malformed parameter counts fail before reaching adapters, object params keep their JSON shape, EVM quantity strings reject decimal or leading-zero formats, WalletConnect-shaped Solana transaction requests require base64 serialized transactions, and request expiry must be 5 minutes to 7 days. Custom IRN publishes `wc_sessionRequest` with relay TTL derived from request expiry. Custom IRN, Reown, and Coinbase request paths reject requests whose chain, method, or signer/from account is not present in the settled session grant before publishing or prompting the wallet. |
| Provider capabilities | Catalog capabilities distinguish external wallets, embedded providers, direct request/response SDKs, persistent sessions, and connector-owned IRN transport; provider metadata alone does not imply `.walletConnectIRN`. |
| Error mapping | Rejection, timeout, missing wallet, unsupported method, unsupported chain, and disconnect messages map to typed package errors. |
| Connector readiness | The custom WalletConnect DApp transport completes the v2 Sign handshake, publishes requests, expires stalled pairings, and restores sessions across launches when given a keychain state store, but its default readiness is `.experimental` until a recovery-capable `WalletConnectorCryptoProvider` (`supportsRecovery == true`) is injected so strict EVM ownership verification can succeed; an explicit readiness override is host-owned risk. Readiness of the SDK adapters is gated on the dependencies each connector actually needs: **unconfigured** SDK clients (MetaMask/Privy/Dynamic/Solana/Reown/Coinbase) report `.unavailable`; **configured** MetaMask reports `.experimental` (request-only stub — route MetaMask through WalletConnect/Reown); **configured** Solana reports `.experimental` because it is request-only and cannot connect; **configured** Privy/Dynamic (embedded wallets) and Reown/Coinbase delegate the full lifecycle and report `.experimental` until *both* a recovery-capable provider and real `WalletConnectionMetadata` are injected, and only then `.productionReady`. Runtime family metadata still prevents Reown and custom IRN engines from being routed as equivalent transports. |
| Lifecycle service | Approved sessions persist addresses and topics, launch restore keeps live sessions, expired saved topics are deleted and reported, unreadable restore failures leave saved topics/active wallet untouched, strict ownership policy verifies unverified sessions through the connector before persisting and rejects sessions that cannot be proven, and removal falls back active wallet selection. |

## Reown Adapter

| Test | Expected result |
| --- | --- |
| AppKit availability | Reown adapter reports unavailable on unsupported platforms and works on iOS. |
| Connection start | Reown-backed connector creates a pairing or AppKit session start and emits pairing/approval state. |
| Namespace proposal | WalletConnectorKit can model required and optional namespaces. With the current installed Reown SDK bridge, optional-only and required-only proposals are passed through `SessionParams(namespaces:)`; mixed required+optional proposals fail locally rather than being flattened silently. |
| Session mapping | Reown/AppKit sessions map into `WalletConnectorSession` with topic, provider, accounts, namespaces, and expiry. |
| Callback handling | Host URL callbacks are forwarded through the Reown adapter and do not touch core target code. |
| Request bridge | `personal_sign`, typed-data signing, send transaction, switch chain, add chain, watch asset, and Solana signing requests produce a response or typed rejection. |
| Timeout manager | Pending requests are keyed by `WalletSignRequestID`, resolve by matching WalletConnect response ID, and expire at `WalletRequest.expiryDate`. |

## Direct SDK Adapters

| Test | Expected result |
| --- | --- |
| Coinbase | Direct Coinbase adapter can connect, request, disconnect, and report typed unavailable errors when unconfigured. |
| MetaMask | Request-only stub — no vendor SDK is linked (the native MetaMask SDK was archived on February 26, 2026). Connect MetaMask through WalletConnect/Reown; the bespoke adapter reports typed unavailable errors when unconfigured and stays `.experimental` when configured. |
| Privy | Embedded-wallet adapter. `PrivyWalletConnector` delegates the full lifecycle (connect→session, events, `sessions()`, `handleCallback`, EVM `verifyOwnership`) to an injected `PrivySDKClient` (built against the Privy iOS SDK in the host app). Unconfigured → `.unavailable`; configured → `.experimental` until a recovery-capable crypto provider + real metadata are injected, then `.productionReady`. **On-device QA with a real Privy app ID required before production.** |
| Dynamic | Embedded-wallet adapter. `DynamicWalletConnector` delegates the full lifecycle (connect→session, events, `sessions()`, `handleCallback`, EVM `verifyOwnership`) to an injected `DynamicSDKClient` (built against the Dynamic iOS SDK in the host app). Unconfigured → `.unavailable`; configured → `.experimental` until a recovery-capable crypto provider + real metadata are injected, then `.productionReady`. **On-device QA with a real Dynamic environment ID required before production.** |
| Solana | Solana adapter accepts Solana requests only and rejects EVM requests with typed unsupported-chain errors. It cannot establish sessions — connect Solana wallets through WalletConnect/Reown or a deep link, then route Solana requests here. |

## Host App Configuration

| Test | Expected result |
| --- | --- |
| Reown project ID | Host app supplies the Reown project ID through adapter configuration. |
| Reown App Group entitlement | If the Reown SDK/AppKit integration requires shared App Group storage, the host app target enables **Signing & Capabilities > App Groups** and adds the required `group...` identifier. The package does not own or add this entitlement; every app extension that shares Reown/session data must add the same group. |
| Custom-transport session store | When using `WalletConnectIRNTransportClient`, the host app injects `KeychainWalletConnectSessionStateStore.shared` for the default service so all read-modify-write operations serialize through one actor; the default in-memory store is for tests only. Custom keychain service names must still use one shared instance per service. |
| Native callback scheme | The host app registers the callback scheme used by wallet redirects. |
| Query schemes | `LSApplicationQueriesSchemes` includes every wallet deep-link scheme exposed by provider configuration requirements. |
| URL opening adapter | Platform URL opening remains owned by the host app. |
| Redirect URL | Selected-wallet deep links include the host app native redirect when metadata provides one. |
| Callback allowlist | Return URL handling is configured with the host app's native callback scheme and expected callback hosts. |
| Callback deduplication | SceneDelegate, SwiftUI `.onOpenURL`, and universal-link callbacks are routed through one coordinator so duplicate lifecycle deliveries are suppressed. |
| Callback correlation | Pending wallet callbacks include a high-entropy state/request identifier; mismatched callbacks are rejected before they can complete an operation. |
| Cold launch callback | Initial wallet return URLs are queued until the connector layer is ready, then drained once. |
| QR fallback | If no wallet can be opened, the app shows the returned QR payload. |

## Manual Live-Wallet Suite

> **This suite is the standing ship gate for every live wallet route.** All automated
> tests exercise in-process mocks (mock relay sockets, mock SDK clients, stub crypto
> providers), so the four live vendor clients — `ReownAppKitLiveClient`,
> `LiveCoinbaseWalletSDKClient`, `LivePrivySDKClient`, `LiveDynamicSDKClient` — are
> **iOS-compile-verified only**. None has been run against a real wallet/account on a
> device. Do **not** enable Reown, Coinbase, Privy, or Dynamic as a production route
> until this suite passes on hardware. For each wallet confirm the deep-link/return
> round-trips through `handleCallback` (Reown/Coinbase) or login → embedded-wallet
> `connect` → `request` (`personal_sign`) → `disconnect` (Privy/Dynamic), and that
> `verifyOwnership` recovers the connected address using the **real** injected
> secp256k1 provider (not a stub). Record device, iOS version, build, and wallet
> versions per run.

| Wallet | Required smoke tests |
| --- | --- |
| MetaMask | Connect, reject, disconnect, restore, `personal_sign`, typed-data sign, switch/add chain. |
| Rainbow | Connect through Reown/WalletConnect, reject, disconnect, restore, `personal_sign`. |
| Coinbase Wallet | Connect through Reown and direct Coinbase adapter, reject, disconnect, `personal_sign`. |
| Phantom | Connect through Reown/WalletConnect or deep link, reject, Solana sign message. |
| Rabby | Connect through Reown/WalletConnect or deep link, reject, EVM sign request. |
| Privy / Dynamic (embedded) | Login → `connect` surfaces the authenticated EVM wallet → `personal_sign` → multi-chain request → `disconnect`; requires a real Privy app ID / Dynamic environment ID. |

## Known Limitations & Deliberate Non-Fixes

These are intentional trade-offs, not regressions. Do not "re-fix" them without the
revisit trigger. Each is documented at the cited source location.

| ID | Item | Reason left as-is | Revisit when |
| --- | --- | --- | --- |
| LIM-1 | Relay JWT mints a fresh random `sub` per token instead of persisting one. | Harmless — the relay derives `client_id` from `iss` (the persisted Ed25519 identity key), not `sub`. See `WalletConnectRelayAuth.swift`. | The relay begins keying rate-limits/analytics on `sub` stability. |
| LIM-2 | `WalletConnectURI.init?(absoluteString:)` accepts short/even-length hex keys and an unconstrained topic. | Keeps the value type round-trippable for fixtures. Externally-sourced URIs must use `init?(externalScannedString:)`, which gates on `isCanonicalV2` (64-hex topic + symKey). See `WalletConnectURI.swift`. | A caller ingests an external URI via the lenient initializer. |
| LIM-3 | Relay identity key falls back to an in-memory key when the keychain is unavailable. | Prevents relay auth from hard-failing; only cross-launch `client_id` stability is lost, and the fallback never clobbers a real persisted record. See `WalletConnectRelayAuth.swift`. | Seen firing in production (not just test hosts). |
| LIM-4 | `WalletReturnURLHandler`'s default allow-list is `nil` (accept any scheme/host). | The public entry point (`WalletConnectDAppConnector`) defaults to a scoped handler derived from the app's redirect scheme + callback host, so inbound URLs are origin-checked in practice. See `WalletReturnURLHandler.swift`. | A new caller wires the handler directly without scoping. |
| LIM-5 | `KeychainWalletConnectSessionStateStore` read-modify-write is atomic only within one actor instance. | Mitigated by shipping a `.shared` singleton injected everywhere, so all IRN transports serialize through one actor. See `WalletConnectSessionStateStore.swift`. | A composition creates a second store instance for the same service — use `.shared`. |
| LIM-6 | `WalletChain` is a fixed enum of 6 chains (ethereum, polygon, base, optimism, arbitrum, solana). | Keeps the chain model closed and exhaustively switchable; unknown-chain accounts are dropped safely (fail-closed) rather than mishandled. | The product needs a chain outside the fixed set — requires a data-driven chain model. |

## Verification Status

- Last recorded package suite: **204 total / 198 passed / 6 skipped / 0 failed** (the 6 skips are environment-gated real-keychain integration tests, exercised only during on-device QA).
- The SDK-free core (`WalletConnectorKit`) is production-grade by static/unit verification and is fail-closed on the security-critical surface (crypto envelope, relay auth, keychain persistence, request validation, lifecycle restore).
- The single outstanding ship gate for live wallets is the Manual Live-Wallet Suite above (on-device QA), owned by the wallet integration owner.
