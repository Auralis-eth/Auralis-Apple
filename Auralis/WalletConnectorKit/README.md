# WalletConnectorKit

A Swift package for connecting the Auralis app to external and embedded crypto
wallets. The core `WalletConnectorKit` target is SDK-free (no Reown, wallet
SDKs, UIKit, or SwiftUI) and ships a self-contained WalletConnect v2 Sign
transport over the IRN relay. Wallet-specific integrations live in separate
adapter products (Reown, Coinbase, MetaMask, Privy, Dynamic, Solana).

## Products

| Product | Purpose |
| --- | --- |
| `WalletConnectorKit` | Core domain types, registry, custom WalletConnect v2 IRN transport, persistence. SDK-free. |
| `WalletConnectorKitReownAdapter` | Reown AppKit-backed connector (live; links `ReownAppKit`, **iOS only** — the AppKit product is linked under `.when(platforms: [.iOS])`, so on macOS the target builds without a live client). |
| `WalletConnectorKitCoinbaseAdapter` | Direct Coinbase Mobile Wallet Protocol connector (live; links `CoinbaseWalletSDK`; no persistent WalletConnect session and no advertised chain-switching grant). |
| `WalletConnectorKitMetaMaskAdapter` | **Request-only stub** — the archived MetaMask native SDK was intentionally dropped, so no vendor SDK is linked. **Connect MetaMask through WalletConnect/Reown** (the custom IRN transport or `WalletConnectorKitReownAdapter`), which is MetaMask's supported iOS route. The bespoke connector stays `.experimental`. |
| `WalletConnectorKitPrivyAdapter` / `WalletConnectorKitDynamicAdapter` | Embedded-wallet adapters (live). Each links its vendor iOS SDK **iOS-only** (`Privy` / `DynamicSDKSwift`, under `.when(platforms: [.iOS])`) and ships a live client — `LivePrivySDKClient` / `LiveDynamicSDKClient` — behind `#if canImport(...)`. The wrapper delegates the **full connector lifecycle** (connect→session, `sessions()`, callbacks, EVM `verifyOwnership`). Both SDKs are **auth-first**: the host owns the login UI; `connect` surfaces the already-authenticated embedded EVM wallet. Readiness reaches `.productionReady` only with a recovery-capable crypto provider **and** real metadata (same gating as Reown/Coinbase). |
| `WalletConnectorKitSolanaAdapter` | **Request-only shim** — this adapter cannot establish sessions. **Connect Solana wallets through WalletConnect/Reown** or a deep link, then route Solana requests through this adapter. Stays `.experimental`. |

Every host surface must gate connector routing through `connector.readiness`.
The protocol default is `.unavailable`, so new connectors must explicitly opt
into production readiness. Unconfigured MetaMask, Privy, Dynamic, Solana, Reown,
and Coinbase clients report `.unavailable`. Configured **MetaMask** remains
`.experimental` (route MetaMask through WalletConnect/Reown instead), and
configured **Solana** remains `.experimental` because it is request-only.
Configured **Privy** and **Dynamic** delegate the full lifecycle and reach
`.productionReady` only once a recovery-capable `WalletConnectorCryptoProvider`
(`supportsRecovery == true`) **and** real `WalletConnectionMetadata` are injected
— until then they stay `.experimental` (identical gating to Reown/Coinbase).
The custom IRN connector completes the WalletConnect v2 transport, but its default
readiness is also gated by EVM ownership support: without a recovery-capable
crypto provider it reports `.experimental` because the default strict lifecycle
cannot persist EVM identity safely. Inject `cryptoProvider:` for production EVM
identity flows, or pass an explicit readiness override only when host composition
intentionally owns that risk.

**Reown and Coinbase report `.productionReady` only when they can actually prove
ownership.** A configured live client is necessary but not sufficient: the
connector stays `.experimental` until you inject *both* a recovery-capable
`WalletConnectorCryptoProvider` (`supportsRecovery == true`) and real
`WalletConnectionMetadata`. Without the recovery provider EVM `verifyOwnership`
fails closed; without real metadata the SIWE challenge is bound to a placeholder
domain. Construct them as
`ReownWalletConnector(client:, cryptoProvider: appProvider, metadata: appMetadata)`
(same for `CoinbaseWalletConnector`). Provider catalog presence is not a promise
that an adapter can handle production traffic.

### Wiring the embedded-wallet adapters (Privy / Dynamic)

The host constructs the SDK with its own credentials, wraps it in the live
client, then injects the recovery provider + metadata (same gating as
Reown/Coinbase). The host owns the vendor login UI — the live client's `connect`
only surfaces the *already-authenticated* embedded wallet.

```swift
#if os(iOS)
// Privy: host creates the Privy instance with its app ID.
let privy = PrivySdk.initialize(config: PrivyConfig(appId: "<privy-app-id>", appClientId: "<client-id>"))
let privyConnector = PrivyWalletConnector(
    client: LivePrivySDKClient(privy: privy),
    cryptoProvider: appProvider,   // secp256k1 recovery (supportsRecovery == true)
    metadata: appMetadata
)

// Dynamic: host initializes the SDK on the main actor with its environment ID.
let dynamic = DynamicSDK.initialize(props: ClientProps(environmentId: "<env-id>"))
let dynamicConnector = DynamicWalletConnector(
    client: LiveDynamicSDKClient(sdk: dynamic),
    cryptoProvider: appProvider,
    metadata: appMetadata
)
#endif
```

Until a live client + recovery provider + real metadata are injected the adapters
stay `.experimental` (and the shipped `Unconfigured…` client reports
`.unavailable`). The live clients are **iOS-compile-verified** but still require
on-device QA with a real Privy/Dynamic account before production — see the
Manual Live-Wallet Suite in `WalletConnectorKit-QA-Checklist.md`, which is the
standing ship gate for every live wallet route.

**SDK session restore.** SDK connectors (Reown/Coinbase) keep their session
records in a vendor store outside this package, so a restored SDK session always
reports `addressVerified == false`. To avoid re-prompting the user on every cold
launch, `WalletConnectionLifecycleService` persists the connect-time ownership
proof on the topic record (`WalletSessionTopicRecord.verified`) and merges it
back on `restoreSavedSessions()`. Legacy records default to unverified
(fail-closed), so only sessions actually proven at connect time re-activate.

## Configuration

### Relay project ID (custom IRN transport)

`WalletConnectRelayConfiguration` requires a WalletConnect/Reown **project ID**.
The relay rejects unauthenticated sockets, so a `WalletConnectRelayAuthProviding`
(default: `WalletConnectKeychainRelayAuthProvider`) attaches a signed Ed25519
DID-JWT alongside the project ID.

```swift
let relay = WalletConnectIRNRelayClient(
    configuration: WalletConnectRelayConfiguration(projectID: "<your-project-id>")
)
```

The default relay host is `wss://relay.walletconnect.org` (the legacy `.com`
host is deprecated).

### Reown adapter project ID

The Reown adapter reads `REOWN_PROJECT_ID`. Supply it through
`ReownAppKitConfiguration`; when it is missing the adapter throws
`WalletConnectionError.unavailable`.

### Reown namespace grants

The Reown adapter now passes both `requiredNamespaces` and `optionalNamespaces`
into AppKit session parameters when the proposal contains both. That keeps strict
flows strict while still allowing richer optional capability negotiation. The
pinned SDK currently marks that initializer deprecated in favor of optional-only
session parameters, so keep an eye on Reown upgrades before removing this bridge:
silently downgrading required grants into optional grants would weaken caller
intent.

### Reown App Group entitlement

Reown SDK/AppKit storage that requires an App Group must be configured on the
**host app target**, not in this Swift package. App Groups are code-signing
entitlements owned by the signed app or extension target. `WalletConnectorKit`
can expose Reown configuration and document the requirement, but it cannot grant
`com.apple.security.application-groups` to the final app binary.

In the host app, enable **Signing & Capabilities > App Groups** and add the group
identifier required by the Reown integration, for example `group.com.example.app`.
Add the same group to every app extension that must share Reown/session data with
the app. Keep the identifier in host-app configuration so app-specific bundle IDs,
teams, and provisioning profiles stay outside the reusable package.

### Sharing custom-IRN sessions with an app extension (Keychain access group)

> **An App Group container does not share Keychain items.** The App Groups
> capability above shares files and `UserDefaults` suites; it does **not** make
> this package's Keychain items (session key material, topic index, relay
> identity) visible to an extension.

If an extension must read/restore the custom `WalletConnectIRNTransportClient`
sessions, you need a **Keychain access group**, which is a distinct mechanism:

1. Enable **Signing & Capabilities > Keychain Sharing** on the app target **and**
   every consuming extension target, with the *same* group — e.g.
   `$(AppIdentifierPrefix)com.auraplay.walletconnect.shared`.
2. Pass that group to **all three** keychain-backed stores so they agree on one
   namespace: `KeychainWalletConnectSessionStateStore(accessGroup:)`,
   `KeychainWalletSessionTopicStore(accessGroup:)`, and
   `WalletConnectKeychainRelayAuthProvider(accessGroup:)` (injected as the relay
   client's `authProvider`). Mixing groups across the three yields a partial view.

`accessGroup` defaults to `nil`, which keeps items in the app's private default
access group (no sharing) — the secure default for a single-target app. The
Auralis host resolves the group at runtime (team prefix + a fixed base name) in
`AuralisWalletConnectionFeature`, so no team id is hard-coded; until the Keychain
Sharing entitlement is present the stores fail closed on those items.

### Cross-launch session restoration

The custom `WalletConnectIRNTransportClient` **defaults** to
`KeychainWalletConnectSessionStateStore.shared` (the shared store for the default
keychain service), so a bare transport survives relaunch and its
read-modify-write operations serialize through one actor. Pass
`InMemoryWalletConnectSessionStateStore()` explicitly to opt out of restoration
(tests, or callers that deliberately keep sessions process-local). If you need a
custom service name or degradation callback, create one shared store instance for
that service and reuse it everywhere in app composition.

```swift
let transport = WalletConnectIRNTransportClient(
    relayClient: relay,
    stateStore: KeychainWalletConnectSessionStateStore.shared
)
```

On settle the transport persists the session symmetric key, the local X25519
key-agreement key, the pairing lineage, the original proposal's allowed-chain
constraint, and session metadata. Restoration is
**lazy**: the transport rehydrates and re-subscribes tracked topics (pruning
expired records) on the first call to `sessions()`, `createPairing`, `request`,
or `disconnect` after launch — it is not automatic. Call `sessions()` (e.g. via
`WalletConnectionLifecycleService.restoreSavedSessions()`) early in launch so
inbound requests/deletes on restored topics are received. Persistence is
device-local, non-syncing, and readable only while unlocked. Persistence is now
durable for settled/updated/verified session state: if a save fails, the
transport does not emit the successful state transition. Destructive transitions
are also fail-closed: if the persisted record cannot be deleted during disconnect,
peer delete, invalid update, or expiry pruning, the transport does not emit a
clean `sessionDeleted` state that could resurrect on the next launch.
All sessions share one keychain record, so on a keychain **read** error the store
throws `WalletConnectSessionStateStoreError.unreadable`, fires
`onPersistenceDegraded`, and leaves the existing record intact instead of
pretending there are no sessions. `WalletConnectionLifecycleService` propagates
that restore failure and does **not** delete topics or deactivate accounts when
storage is merely hidden/unreadable. A blob whose bytes cannot decode at all is
treated as already-lost and purged by the store; a decoded record with malformed
WalletConnect key material is treated as restoration degradation and causes the
transport restore to throw instead of silently skipping the session. Keychain
update paths also include the hardened accessibility attributes; if the platform
refuses to mutate those attributes in place, the exact existing item is replaced
so older records migrate to `WhenUnlockedThisDeviceOnly` instead of keeping a
weaker class forever.

Expired live sessions are pruned **lazily**: an in-memory session past its expiry
is dropped on the next `sessions()` (filtered out) or `request()` (which throws
`sessionExpired`), not by a background timer. A session that expires while the
process idles remains in memory until one of those calls, so treat `sessions()`
as the source of truth for "is this live?" rather than caching its result.

The peer supplies the session `expiry` in `wc_sessionSettle`, so the transport
**clamps** it to the WalletConnect 7-day cap: a wallet cannot settle a session
whose key material and relay subscription would otherwise persist indefinitely.

Outbound `wc_sessionRequest` values are bounded to the WalletConnect request
window: expiry must be at least 5 minutes and at most 7 days from now. The custom
IRN transport publishes request messages with relay TTL derived from that expiry,
so local pending state cannot outlive the relay message window by construction.

Settled and updated namespaces must satisfy every `requiredNamespaces` grant from
the original proposal before the transport exposes or retains a live session. If
a wallet omits a required chain account, method, or event, settle is rejected; if
a later update removes one, the session is deleted locally. Use
`connect(proposalRequest:)` when a flow truly requires specific chains/methods;
the legacy `connect(proposal:)` overload remains an optional-capabilities
convenience for broad discovery.

## Verifying wallet ownership (important)

Settling a session only proves a wallet **claims** an address — it does **not**
prove the user controls the private key. To establish ownership you must issue a
signing challenge and verify the signature. `verifyOwnership` issues a canonical
**EIP-4361 (Sign-In with Ethereum)** message that binds the app domain, URI,
chain id, a high-entropy nonce, and an issued-at/expiration window, so a captured
signature cannot be replayed against another domain or after it expires.
Verification requires secp256k1 public-key recovery, which this package does not
vend: inject a `WalletConnectorCryptoProvider` (the Auralis app supplies one
backed by web3.swift). That provider's `recoverPublicKey` receives the
**already-hashed** EIP-191 digest and must not re-apply the message prefix.

```swift
let connector = WalletConnectDAppConnector(
    transport: transport,
    metadata: metadata,
    cryptoProvider: appCryptoProvider // secp256k1 recovery
)

// After connecting, before trusting the address:
let owns = try await connector.verifyOwnership(of: address, in: sessionID)
guard owns else { /* reject */ }
```

`verifyOwnership` **fails closed**: without a recovery-capable `cryptoProvider`
it throws instead of silently returning success. `DefaultWalletConnectorCryptoProvider`
does not implement recovery and will throw if used for verification.

### Smart-contract wallets (EIP-1271)

Ownership verification tries **EOA secp256k1 recovery first**, then falls back to
**EIP-1271** on-chain validation. A smart-contract account (Safe, Coinbase Smart
Wallet, most ERC-4337 accounts, and some Privy/Dynamic embedded wallets) has **no
recoverable private key** — it validates signatures via an on-chain
`isValidSignature(bytes32,bytes)` call — so `ecrecover` can never match its
address. Verifying such a wallet requires an RPC-backed check, which this package
does not vend.

To support them, inject a `WalletConnectorCryptoProvider` that sets
`supportsSmartContractOwnership == true` and implements
`isValidERC1271Signature(address:message:signature:chain:)` (the Auralis app's
web3.swift-backed provider does the `eth_call`). When present, `verifyOwnership`
consults it after EOA recovery fails, so a legitimate contract wallet is proven
instead of rejected. If you do **not** inject such a provider, a smart-contract
wallet cannot be proven under the default `ownershipPolicy: .requireVerified` and
its session will fail closed — use `ownershipPolicy: .allowUnverified` for
intentionally non-sensitive flows with those wallets, and do not treat the
address as proven identity.

`verifyOwnership` remains callable directly on a connector after connection and
before trusting an address for anything sensitive. `WalletConnectionLifecycleService`
defaults to `ownershipPolicy: .requireVerified`; when an approved session is not
already marked verified, the service now asks the connector to prove each extracted
address before writing account/topic state. If the connector cannot verify, or the
signature does not recover the claimed address, persistence fails closed. The same
policy is applied during restore: legacy or SDK sessions that are still unverified
are reported in `unverifiedSessionTopics`, left in the topic store, not upserted,
and not made active. Use `.allowUnverified` only for intentionally non-sensitive
flows such as broad personalization, and do not treat the restored address as
proven identity in that mode.

To make the claimed-vs-proven distinction impossible to miss, every
`WalletConnectorSession` (and `WalletSession`) carries `addressVerified`. It is
`false` on a freshly settled session and only becomes `true` after
`verifyOwnership` succeeds — at which point the transport re-persists the session
so the flag survives relaunch. Treat `addressVerified == false` as "the wallet
merely *claims* this address" and never authorize anything sensitive on it.

**Connector scope.** `verifyOwnership` is declared on the `WalletConnector`
protocol and **fails closed by default**: every connector responds to the call,
and connectors that do not implement challenge signing throw
`WalletConnectionError.unavailable`. The custom IRN connector, Reown connector,
and Coinbase connector can issue EVM `personal_sign` challenges when configured
with a recovery-capable `WalletConnectorCryptoProvider`. The custom IRN transport
also persists `addressVerified == true` on its restorable session record; SDK
connectors prove ownership at the lifecycle boundary because their vendor session
stores remain outside this package.

Because the transport also **scopes settled accounts to the proposed chain set**,
a wallet cannot settle accounts on chains you never proposed (they are dropped
before the session is built). This is a structural guard, *not* a substitute for
`verifyOwnership`: an in-scope address is still only *claimed* until proven.

### `personal_sign` message encoding

`WalletRequestBuilder.personalSign(message:)` places `message` on the wire
verbatim; per EIP-191 that parameter should be `0x`-hex. To sign human-readable
text, use `personalSignText(text:)`, which hex-encodes the UTF-8 bytes. The
semantic `EVMWalletOperation.personalSign(message:)` follows the text path so its
public `message` argument is safe for normal user-readable strings; use the raw
builder or `WalletOperation.raw` for already-encoded payloads.

## Host app configuration checklist

- Register the native callback scheme used by wallet redirects.
- Add every wallet deep-link scheme to `LSApplicationQueriesSchemes`.
- Scope `WalletReturnURLHandler` to your app's callback scheme/hosts. The
  bare `WalletInboundURLCoordinator()` default accepts **any** scheme/host;
  construct it with `WalletInboundURLCoordinator(allowedSchemes:allowedHosts:)`
  when it ingests untrusted inbound URLs.
- Route SceneDelegate, SwiftUI `.onOpenURL`, and universal-link callbacks
  through one `WalletInboundURLCoordinator` (dedup + operation-ID correlation).
- The IRN relay transport receives all protocol traffic over its WebSocket, so
  `WalletConnectDAppConnector.handleCallback(url:)` treats a foreground return as
  a no-op. It does **not** process Link Mode (`wc_ev`) envelopes — those require a
  WalletConnect SDK-backed connector — and now throws
  `WalletConnectionError.unavailable` for a `wc_ev` callback instead of silently
  discarding it. Use an SDK-backed adapter if you need Link Mode.

## Session updates, extends, and events

The custom IRN transport handles the full v2 Sign session lifecycle, not just the
initial settle. When the connected wallet sends:

- `wc_sessionUpdate` — the transport re-applies the wallet's revised
  namespaces/accounts through the **same chain-scoping guard** used at settle
  (accounts on chains you never proposed are dropped), re-persists, and emits
  `WalletConnectorEvent.sessionUpdated`. If the account set actually changes,
  `addressVerified` is reset to `false` — a prior ownership proof only covered
  the old accounts.
- `wc_sessionExtend` — the transport adopts the new expiry only when it is not
  earlier than the current one and within the WalletConnect 7-day cap; otherwise
  it is ignored. A valid extend re-persists and emits `.sessionUpdated`.
- `wc_sessionEvent` (`accountsChanged` / `chainChanged`) — surfaced to the host
  as `WalletConnectorEvent.sessionEvent`. This is informational; it does not
  mutate the session's account set (a wallet that wants that sends
  `wc_sessionUpdate`).

Peer acknowledgements for settle/update/delete/ping/event messages are still
published after the local state transition they acknowledge. If that publish
fails, the transport now emits
`WalletConnectorEvent.peerAcknowledgementFailed(WalletPeerAcknowledgementFailure)`
with the topic, request id, tag, and mapped error. Treat it as telemetry and a
wallet-UX diagnostic signal; the local dedupe/retry path remains the state source
of truth.

Missed-message recovery on a dropped socket is handled by explicitly draining
`irn_fetchMessages` before re-subscribing on reconnect and cold-launch restore.
The transport replays fetched messages locally, follows `hasMore` pagination, and
only exposes restored sessions after relay recovery succeeds. A settle/response/
delete published during an outage is therefore processed before the topic is
considered live again.

## Transport security notes

Relay payloads are end-to-end encrypted (X25519 + HKDF-SHA256, ChaCha20-Poly1305),
so the relay never sees plaintext. The relay endpoint must still use TLS: a
non-`wss` `relayURL` is rejected at `connect()` with
`WalletConnectRelayConfigurationError.insecureRelayURL` (and `isUsable` is
`false`), closing a silent transport-downgrade misconfiguration. TLS certificate
pinning on the relay socket is **not** applied — it is defense-in-depth only given
E2E encryption, and pinning a third-party relay certificate is operationally
fragile. Revisit if your threat model requires it.

`wc_sessionRequest` responses are correlated by JSON-RPC id **and** the session
topic they arrive on: a response is only accepted on the topic the request was
published on, so a second connected wallet cannot resolve another session's
in-flight request by guessing its id. Relay and Sign JSON-RPC ids now follow the
WalletConnect relay shape more closely: millisecond epoch high digits plus six
cryptographically-random low-order digits, with monotonic clamping when needed.

Pairing URIs are gated on the canonical WalletConnect v2 shape (64-hex topic +
64-hex symKey) before they can drive any key derivation, so a truncated or
malformed symmetric key never reaches the crypto layer. For URIs sourced from
outside the app (scanned QR / pasted), parse with
`WalletConnectURI(externalScannedString:)`, which enforces the same check.

See `WalletConnectorKit-QA-Checklist.md` for the full verification matrix.
</content>
</invoke>
