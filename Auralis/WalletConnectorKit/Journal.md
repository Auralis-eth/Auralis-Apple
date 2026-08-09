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

Reown AppKit remains a fully supported production WalletConnect path because it ships the entire v2 protocol engine and wallet-discovery UI. The custom IRN transport is now also production-capable: it has relay auth, encryption envelopes, settlement, fetch/reconnect, a pairing-window expiry, and — as of 2026-07-29 — real cross-launch protocol-state persistence via `KeychainWalletConnectSessionStateStore`. Choose Reown when you want the AppKit modal and the broadest wallet coverage; choose the custom transport when you want a dependency-light, fully in-house relay client.

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

### 2026-07-27: The Keychain Door Now Locks When the Device Does

Phase 4 sharpened the security rule for WalletConnect session topics: they are useful only while the user is actively using the device, so the Keychain item now uses `WhenUnlockedThisDeviceOnly` instead of the more background-friendly `AfterFirstUnlockThisDeviceOnly`. That is a deliberate product stance. AuraPlay is read-only, but a session topic is still a live pairing reference; it should not be available while the device is locked just because the phone has been unlocked once since boot.

The tests grew two layers. The always-on query-factory test checks the exact attributes we promise. Real Keychain integration tests are present too, but they politely step aside on runners that return `-34018` because there is no Keychain-capable test host. Think of it as testing the vault combination when a vault exists, while still checking the blueprint everywhere.

Reown configuration also got a front-desk checklist: trim the project ID, reject an empty value with the exact `REOWN_PROJECT_ID not set - see README.md` diagnostic, and refuse conflicting second configurations. The host app still decides when to call it, but the package now makes it harder to accidentally configure AppKit twice.

### 2026-07-27: Provider Claims Learn Some Humility

The latest implementation pass tightened a subtle but important boundary: provider metadata no longer implies the package is using a custom WalletConnect IRN engine. A wallet can be external, support EVM, support Solana, or have a direct SDK route without inheriting `.walletConnectIRN` just because it has a deep link. That flag now belongs to actual connector runtime behavior, not casual catalog inference.

MetaMask also got a more honest label. The legacy native iOS SDK dependency still exists for source compatibility, but the catalog marks that path as deprecated because the upstream repo was archived on February 26, 2026. That is not a reason to panic; it is a reason to route production external-wallet flows through Reown/WalletConnect or a current embedded-wallet product instead of pretending the old native bridge is fresh lumber.

Solana transaction validation also stopped accepting base58 for WalletConnect-shaped transaction requests. Base58 still exists as a vocabulary word because provider-specific deep links may need it, but the shared WalletConnect/Reown request path now expects base64 serialized transactions. The package is learning to ask, "which counter are we standing at?" before accepting a payload.

### 2026-08-01: The Relay Mailbox Gets a Real Pickup Routine

The shipping audit found a classic distributed-systems trap: we were treating "subscribe again" like a guaranteed mailbox drain. The current WalletConnect relay contract is more explicit: ask for queued messages, keep asking while `hasMore` says the mailbox is not empty, then subscribe for live traffic. The transport now does that on restore and reconnect, and it refuses to show a restored session as live if the relay recovery step fails.

Unsubscribe also learned to bring its claim ticket. The relay returns a subscription id when we subscribe, and expects that id back when we unsubscribe. Sending only a topic was like telling coat check, "the black jacket, please" in a room full of black jackets.

The other lesson was about permission boundaries. A settled session namespace is the wallet's grant, not a suggestion. Custom IRN, Reown, and Coinbase now validate chain, method, and signer account locally before a prompt can escape to a wallet. Ownership verification also stopped being a handshake high-five: if the verified flag cannot be persisted, the call fails instead of pretending the proof will survive relaunch.

### 2026-08-08: The Menu Promised Dishes the Kitchen Would Not Cook

A strict component audit found a routing truthfulness bug hiding in plain sight. The catalog had learned to say "Privy and Dynamic are EVM-only," and Coinbase had learned not to grant chain switching in its live session, but the registry's method filter was still acting like every EVM provider could do every EVM method. That is how a host can invite Coinbase to a `wallet_switchEthereumChain` flow or Privy to a method its live client rejects.

The lesson is boring and important: capabilities, registry filters, session namespaces, and adapter request mappings are four menus for the same kitchen. If one menu says a dish exists and another says it does not, users find out at the table.

The fix made the registry ask for the exact capability behind each request method instead of trusting the broad EVM/Solana family label. Privy now advertises message signing only, Dynamic keeps transaction signing but not chain-admin or asset-watch powers, and both embedded live clients grant only the methods their request mappers can actually serve. The menu and the kitchen finally agree.

## Engineer's Wisdom

A wallet package should not make unsupported things look supported. It is better to expose a sharp `experimental` badge, a deprecated provider route, or a typed `unavailable` error than to let the host app discover the truth in a live signing flow.

Typed values beat clever strings. The closer request payloads stay to their real JSON shape, the easier it is to test method order, validate quantities, and bridge into SDKs without accidental double encoding.

Transport is not identity. Provider, connector, transport, custody model, and chain client are separate ideas. Mixing them together creates APIs that feel convenient right up until the first restoration, callback, or provider upgrade.

## If I Were Starting Over...

I would separate provider catalog metadata from connector runtime metadata on day one; wallet support is not the same thing as our chosen transport. I would also build protocol-state persistence *with* the transport rather than after it — the custom IRN path spent a release claiming production readiness while quietly losing every session on relaunch, because a topic index was mistaken for full protocol state. A stored topic is a locker number; you also need the session key, the local key-agreement key, and the pairing lineage before you can say "resumable."

For Solana, I would begin with semantic operations and serialized transaction bytes before adding any provider adapter. Solana is not EVM with a different method prefix, and the code gets cleaner when it stops pretending otherwise.

## 2026-07-28 — The custom transport grew up

This pass took the "experimental" badge off the custom WalletConnect IRN transport by making it actually complete the v2 Sign handshake. The relay client now authenticates with a real Ed25519 DID-JWT (`?auth=`), because the relay was never going to let an anonymous socket in; messages are sealed with ChaCha20-Poly1305 typed envelopes; session keys are derived with X25519 + HKDF-SHA256; and the engine drives propose → derive → settle → request → delete, correlating responses by the on-the-wire JSON-RPC id. The crypto primitives are pinned bit-for-bit to the reown reference vectors, and a scripted mock-wallet test proves the whole loop end to end. Inbound relay subscriptions — previously dropped on the floor — are now decrypted and dispatched, and a dropped socket reconnects with capped backoff instead of waiting for the next outbound call.

Coinbase got a real native adapter over the Mobile Wallet Protocol SDK, bridged from its completion-handler API into async/await. Coinbase is honestly modeled as a direct request/response wallet: it hands back an account synchronously, so `WalletConnectionStart.pairingURI` became optional rather than pretending a pairing URI exists.

The six review findings all landed: the DApp connector scopes its return-URL handler to the app's own scheme/host by default (no more accept-any-origin Link Mode envelopes), request validation now checks EVM addresses and hex calldata, the Reown adapter surfaces an error instead of a silent empty result, an `externalScannedString` initializer enforces the canonical 32-byte key for untrusted URIs, and the package ships an ownership-verification helper (SIWE recovery is injected from the app via web3.swift, keeping secp256k1 out of the package's dependency surface).

### Engineer's wisdom (this pass)

Mirror the reference, don't reinvent the crypto. The envelope byte layout, HKDF salt/info, and did:key multicodec all had exact answers sitting in the resolved reown checkout; copying them (and their test vectors) turned "hope the math is right" into "the vectors say it's right."

Fail soft on identity, hard on secrets. The relay-auth key falls back to an in-memory identity when the keychain is unavailable, so a missing entitlement degrades `client_id` stability instead of bricking every connection — but a failed `SecRandomCopyBytes` still throws rather than emit a predictable key.

## 2026-07-29 — Closing the ship-readiness gaps

An independent review (crypto verified bit-for-bit against Keccak-256, EIP-191, and Base58 vectors) found the custom IRN transport was flagged `.productionReady` but could not survive a relaunch: session state lived only in actor memory, the keychain store persisted only a topic→address index, and `WalletConnectProtocolState` existed as a value type that nothing ever wrote. Worse, `restoreSavedSessions()` treated the empty `sessions()` after a cold launch as proof the sessions were dead and actively deleted the saved topics and deactivated the wallets. The docs were internally contradictory about all of this.

This pass made the readiness claim true rather than demoting it:

- **Real cross-launch persistence.** `WalletConnectPersistedSession` now captures the full restorable state — session symmetric key, the local X25519 key-agreement private key, pairing lineage, provider, accounts, namespaces, and expiry. `WalletConnectSessionStatePersisting` has an in-memory implementation (the transport default, hermetic for tests) and `KeychainWalletConnectSessionStateStore`, a single device-local `WhenUnlockedThisDeviceOnly` item that is fail-soft: a missing entitlement loses restoration, never a live connection. The transport persists on settle, restores + re-subscribes on first use, and prunes expired records. Production wires the keychain store; a bare transport stays in-memory.
- **No more silent hangs.** `createPairing` arms a single pairing-window timeout that spans propose → settle. If the wallet never answers, or answers but never settles, the pairing expires with a reported `.pairingExpired` event instead of a permanent stall. A failed session-topic subscribe is now surfaced as a rejection rather than swallowed.
- **Correct relay hygiene.** Peer `wc_sessionPing`/`wc_sessionEvent` acks use the proper `1115`/`1111` response tags (they were both mislabeled `1103`), and `disconnect`/inbound `wc_sessionDelete` now unsubscribe the relay topic and clear persisted state instead of leaking the subscription. The relay client gained `irn_unsubscribe`.

Verified with `swift test`: 79 tests across 12 suites pass, including new coverage for the session-state store round-trip and transport restore/prune.

### Engineer's wisdom (this pass)

"Production-ready" is a claim about what survives a cold launch, not what works in one session. The tell was that the restoration *contract* (`WalletConnectProtocolState.restorationStatus`) was fully modeled and unit-tested while nothing on the write path ever produced one. Model and mechanism have to ship together, or the model just launders an aspiration into something that looks done.

## 2026-07-31 — Three ship-blocking transport bugs, closed

A principal-level audit pass fixed three concrete defects that survived the earlier hardening because each only bites at a boundary the happy-path tests never crossed (a socket drop, a mid-request teardown, a cold-launch race):

- **Missed messages are recovered on reconnect and restore.** `WalletConnectIRNRelayClient.fetchMessages(topic:)` existed but was never called, so a `wc_sessionSettle` / request-response / `wc_sessionDelete` the wallet published while our socket was down was lost — the request then hung until its expiry. The relay does not replay its mailbox on subscribe, so the fix drains it explicitly: `resubscribeAll()` (reconnect) and the transport's cold-launch `performRestore()` now issue an `irn_fetchMessages` per topic, and an ack carrying `{ messages: [...] }` is replayed onto the subscription event stream (`deliverFetchedMessages`). The drain is fire-and-forget so a slow/absent fetch ack never stalls the subscribe or the operation that triggered the reconnect; dedup on decrypted identity keeps a fetched-and-pushed message from running twice.
- **In-flight requests fail fast when the session dies.** A `wc_sessionDelete` or a local `disconnect()` tore down the topic's key material but left any awaiting `request(...)` blocked on its continuation until the (up to 5-minute) expiry. `failPendingRequests(forTopic:)` now uses the existing wire-id → topic binding to reject exactly those pending requests with `.sessionExpired` on delete, disconnect, and expiry-prune.
- **Restoration no longer races itself.** `ensureRestored()` set `didRestore = true` *before* awaiting `loadAll()`, so a second caller arriving during that suspension returned early and observed an empty session set (and could throw `sessionExpired` for a session that was merely not-yet-rehydrated). It now coalesces every caller onto one restore `Task` — the same pattern the relay client already used to coalesce concurrent `connect()`.

Verified with `swift test`: 108 tests across 15 suites pass, including three new regression tests (fetch-ack replay, request-fails-fast-on-disconnect, and concurrent-restore-coalescing).

### Engineer's wisdom (this pass)

Dead code that names a real guarantee is worse than a missing feature: `fetchMessages` and a QA-checklist line both described a mailbox drain that nothing invoked, so the gap read as "done." A capability isn't shipped until something on a live path calls it and a test crosses the boundary where it matters. And when you solve a re-entrancy race once (the relay's `connect()` coalescing), grep for the same shape elsewhere — `ensureRestored` had reintroduced it verbatim.

## 2026-07-31 (later) — Correcting the fetch premise; finishing the Sign protocol; honest adapters

Two things this pass: a **correction** and a **completion**.

**Correction (the fetch drain was solving a non-problem).** The previous entry claimed missed messages were lost because "the relay does not replay its mailbox on subscribe." Checking the reference (`reown-swift`) directly disproved that: its relay client has **no fetch method at all** — `RelayClient.setupConnectionSubscriptions` simply `batchSubscribe`s every tracked topic when the socket reaches `.connected`, and that is its entire missed-message recovery. If the relay didn't replay queued messages on (re)subscribe, the reference client would drop messages on every reconnect, which it doesn't. So re-subscribe *is* the recovery mechanism, and the pre-existing `resubscribeAll()` / cold-launch `subscribe()` already did the job. The speculative `irn_fetchMessages` auto-wiring (which isn't even a method this relay generation supports) was reverted; `resubscribeAll` now documents that re-subscribe is the recovery, and `fetchMessages`/`deliverFetchedMessages` remain only as an optional, explicitly-invoked API for relays/tests that support a mailbox drain. Lesson: verify the premise against the reference *before* building the mechanism — the fix and the bug were both fictional.

**Completion (the v2 Sign protocol handled only half the session lifecycle).** The transport processed propose/settle/request/delete/ping but silently dropped the three messages a wallet uses to *change* a live session. Now, mirroring reown's tags and validation:

- `wc_sessionUpdate` (1104/1105) — re-applies the wallet's namespaces/accounts through the **same chain-scoping guard** as settle (extracted into `scopedAccountsAndNamespaces`), re-persists, emits `.sessionUpdated`, and **resets `addressVerified` to false when the account set actually changes** (prior proof covered the old accounts).
- `wc_sessionExtend` (1106/1107) — adopts the new expiry only when it is not earlier than the current one and within the 7-day cap (mirrors `WCSession.updateExpiry(to:)`); an out-of-range value is ignored, not acked as success. Fixes the real bug where a wallet-extended session would be pruned early.
- `wc_sessionEvent` (1110/1111) — surfaces `accountsChanged`/`chainChanged` to the host as `.sessionEvent` instead of acking into the void. Informational only; it does not mutate the account set.

New `WalletTransportEvent.sessionUpdated/.sessionEvent` and `WalletConnectorEvent.sessionUpdated/.sessionEvent` carry these to the app; duplicates re-ack idempotently without re-emitting.

**Honest adapters + SIWE + a crypto contract note (P3).** The stub adapters (MetaMask/Privy/Dynamic/Solana) inherited the protocol's `.productionReady` default despite linking no vendor SDK — a composition layer checking `readiness.allowsProductionUse` would have trusted them. Each SDK-client protocol now carries `isConfigured` (default `true`; the `Unconfigured…` stubs return `false`) and the connector derives `readiness` from it, so a stub reports `.unavailable` while a real client reports ready. `verifyOwnership` now issues a canonical **EIP-4361 SIWE** message binding app domain, URI, chain id, nonce, and an issued-at/expiration window (replaces the ad-hoc three-line challenge). And `WalletConnectorCryptoProvider.recoverPublicKey` now documents that `message` is the already-hashed digest — the injected provider must **not** re-apply the EIP-191 prefix or verification silently fails to match.

Verified with `swift test`: 116 tests across 16 suites pass, including new coverage for update/extend (incl. the beyond-cap ignore), event surfacing, unproposed-chain drops on update, the SIWE challenge shape, and stub-adapter readiness.

### Engineer's wisdom (this pass)

Read the reference before you trust your own diagnosis. A confident, well-written bug report (mine, last pass) sent me building a fetch-drain for a mailbox the relay already replays on subscribe — the reference client's *absence* of a fetch path was the tell. "The reference doesn't do X, and it works" is stronger evidence than "X seems necessary."

## 2026-08-01 — Shipping audit: badges, restore failure, and session grants

This pass closed the boring-but-dangerous gaps where a package can look polished while still steering a production app into a wall.

First, readiness badges stopped being inherited optimism. Solana, Reown, and Coinbase now follow the same rule as the other adapter shims: a real injected client defaults to configured, while every `Unconfigured...` client says no. The host UI can finally treat `readiness` like a route guard instead of a decorative sticker.

Second, restore learned the difference between an empty shelf and a locked storeroom. A corrupt Keychain blob is already lost, so the store purges it and lets cleanup continue. An unreadable Keychain item means sessions may still exist but are temporarily hidden, so the transport throws and the lifecycle service does not delete topics or deactivate accounts. That is the wallet version of not throwing away someone's coat just because the coat-check window is closed.

Third, outbound WalletConnect requests now check the settled grant before publishing: chain, method, and signer account must all be present in the approved namespaces/accounts. Wallets should reject bad requests too, but the SDK should not make the app UX wait on a wallet prompt for something the session contract already ruled out.

Finally, ownership verification now has a host-enforceable policy. `addressVerified` remains fail-closed, and sensitive flows can opt into `WalletConnectionLifecycleService(ownershipPolicy: .requireVerified)` so claimed-but-unproven sessions never enter persisted identity state.

### Engineer's wisdom (this pass)

State named `[]` is not always empty. Sometimes it means "definitely none," sometimes it means "I could not look." Shipping code needs separate branches for those states, because cleanup is only safe in the first one.

## 2026-08-01 — Reown App Groups belong to the host app

The Reown/AppKit integration has one of those boundaries that looks like package work until you remember code signing exists. App Groups are not Swift package features; they are entitlements baked into the signed app or extension. WalletConnectorKit can be the recipe card that says "use this shared pantry," but only the host app gets to ask Apple for the pantry key.

So the docs now make the split explicit: the package exposes Reown configuration, while the Auralis app target enables **Signing & Capabilities > App Groups** and adds the required `group...` identifier. Any extension that needs the same Reown/session storage must carry the same entitlement. Do not hide a team-specific App Group ID in `Package.swift`, and do not create package-level entitlement files for a reusable library target.

### Engineer's wisdom (this pass)

When a dependency asks for an entitlement, first ask "which binary is signed?" Libraries can model requirements, validate inputs, and fail clearly, but the final app target owns provisioning, bundle identity, and capabilities. That line keeps reusable packages from quietly depending on one team's signing setup.

## 2026-08-01 — Durable means the vault actually wrote it

This pass tightened the final shipping contract around the places where "looks connected" can lie.

The Keychain session-state store now throws when writes or deletes fail. Before this, the transport's transitions were shaped like a bank teller saying "deposited" after the pneumatic tube jammed: the in-memory session looked verified/updated, but a relaunch could not restore that fact. Now settle, update, and ownership verification only move forward when the durable store accepts the record.

Relay auth picked up the required `act: client_auth` claim, and session requests now live inside WalletConnect's expiry box: no shorter than five minutes, no longer than seven days. The relay publish TTL follows the request expiry, so the local pending request and the relay's mailbox agree about how long the request exists.

Required namespaces also stopped being paperwork. The custom transport now validates settled and updated namespaces against the original required grant. If the wallet omits a required method, event, or chain account, the session never becomes live; if an update removes one later, the session is deleted. The Reown bridge no longer silently flattens mixed required+optional proposals on this installed SDK version; it passes optional-only or required-only proposals through and fails mixed proposals locally until the newer split-namespace API is available.

### Engineer's wisdom (this pass)

A persistence API that says `throws` but never throws is worse than a non-throwing API: it trains every caller to believe durability was checked. Make the lie impossible at the lowest layer, then let higher layers stay simple.

## 2026-08-02 — Strict shipping means the receipt has to survive both directions

Today's product call picked the conservative lane: shipping UI shows only configured live connectors, Coinbase stays direct request/response, and sensitive identity flows require ownership proof before trust. That let the code stop hovering between "developer convenience" and "production contract."

The main connector API now preserves required and optional WalletConnect namespaces instead of flattening everything into optional discovery. Optional is great when you are asking, "what can this wallet do?" Required is different: it is the bouncer's guest list. If a flow requires a chain or method, the proposal has to say so and the settled session has to prove it.

Restored sessions also remember the chains originally allowed by the proposal. Before this, a restored session could wake up with amnesia and accept a later update for chains it never asked for. That is subtle because the first launch was safe; the bug lived across the relaunch boundary, where many wallet bugs like to hide.

The other half of durability is deletion. Saving verified state has to throw when the vault refuses the record, but deletion has the same rule. A disconnect that cannot delete the persisted record is not a clean disconnect; it is a stuck receipt that could walk back into the app on next launch. The transport now refuses to emit the happy-path delete story when the durable delete failed.

### Engineer's wisdom (this pass)

Security boundaries are verbs as much as nouns. "Required," "verified," and "deleted" are promises about actions that already completed, not labels we optimistically attach while hoping storage or a wallet SDK catches up later.

## 2026-08-02 — No More Accidental Green Lights

This shipping pass pulled two defaults out of the danger zone. A bare connector no longer inherits a production-ready badge just for conforming to `WalletConnector`; it has to say, out loud, that it is ready. That turns readiness from a participation trophy into a release gate.

The lifecycle service also flipped its default to `requireVerified`. The host still has to perform the ownership challenge, but persistence now behaves like a cautious clerk: no proof, no permanent account record. Non-sensitive flows can still choose `.allowUnverified`, but they have to write that choice down.

One more wallet prompt got a sharper bouncer. `wallet_switchEthereumChain` already had a valid JSON shape, but now the requested target chain must also be present in the settled session grant. Otherwise a mainnet-only session could ask the wallet to switch to Polygon and hope the wallet objected. The SDK should not outsource obvious permission mistakes to the wallet prompt.

### Engineer's wisdom (this pass)

Defaults are architecture. In a wallet package, an optimistic default is not convenience; it is a future incident report wearing comfortable shoes.

## 2026-08-02 — Restore Stops Treating Doubt as Absence

The last ship-blocker pass tightened the cold-launch story one layer deeper. Strict ownership used to stop new unverified sessions from being persisted, but restore still let an old unverified session stroll back into active account state. Now `restoreSavedSessions()` applies the same `requireVerified` policy: unverified topics are preserved and reported, but they are not upserted, not activated, and not mistaken for stale deletes. That is the difference between "this guest needs ID checked" and "throw away their reservation."

Custom IRN restore also stopped skipping malformed persisted key material. If a session record decodes but its symmetric key or local X25519 private key is unusable, the transport throws. That keeps lifecycle cleanup from seeing an empty live-session list and deleting perfectly real topic/account records because the crypto receipt was damaged.

Coinbase got a smaller honesty fix: it is direct request/response and grants the connected account's current chain, so the catalog and synthetic namespace no longer advertise chain switching. `wallet_watchAsset` also now rejects malformed EVM token addresses locally before any wallet prompt is launched.

### Engineer's wisdom (this pass)

Restoration has three states, not two: live, gone, and uncertain. Shipping code can clean up only the second one. The third one deserves a loud error or an inactive holding pattern, because destructive certainty is hard to undo.

## 2026-08-02 — The Final WalletConnect Screws Get Tightened

This pass cleaned up the medium and low findings that were not dramatic enough to stop a demo, but were exactly the kind of details that become support tickets after release.

First, strict ownership stayed strict on purpose. Reown and Coinbase can restore SDK sessions whose addresses are still claims, not proof, so the lifecycle default keeps them inactive until the host verifies ownership. That may feel stern for a broad connect-wallet UX, but identity code needs a locked front desk. If the product wants personalization without proof, it can opt into `.allowUnverified` and keep the badge honest.

Second, old Keychain records no longer get grandfathered into weaker accessibility forever. Updates now carry the hardened `WhenUnlockedThisDeviceOnly` class, and if Security refuses to mutate that class in place, the store replaces the exact record. The migration is like changing the lock when someone comes back to renew their room key, not waiting for every guest to check out.

Third, the Reown bridge learned to carry both required and optional namespaces at the same time. The pinned SDK complains that this initializer is deprecated, but preserving the caller's required grants is still the safer trade until the AppKit wrapper offers the newer split connect surface cleanly.

Finally, protocol edges stopped being silent. Peer ACK publish failures now surface as `peerAcknowledgementFailed`, and relay/request IDs moved to the WalletConnect-shaped millisecond-plus-six-random-digits form. Neither change is flashy. Both make the package easier to diagnose if a relay or wallet starts enforcing the spec more tightly.

### Engineer's wisdom (this pass)

Ship-readiness is mostly refusing to confuse "works today" with "well-specified enough to survive tomorrow." Keep the conservative identity default, migrate old secrets when you touch them, and turn swallowed protocol failures into observable facts.

## 2026-08-03 — Proof First, Then the Clipboard

Today's review fix closed an awkward identity deadlock. The lifecycle service defaulted to `requireVerified`, which was the right security posture, but it checked the `addressVerified` receipt before giving SDK-backed connectors a chance to produce one. Reown and Coinbase could ask the wallet to sign; the front desk just never handed them the pen.

Now strict persistence works in the right order: extract the claimed addresses, ask the connector to prove each one, then write account/topic state only after the proof passes. The write path is staged too. If storage fails halfway through a multi-account session, the service walks back topic records and deactivates any addresses it already upserted instead of leaving half a table set for dinner.

Reown and Coinbase gained the same ownership-verification shape as the custom IRN connector: issue a `personal_sign` challenge, parse the returned EVM signature, and verify it with a host-injected secp256k1 recovery provider. The default crypto provider still refuses recovery, which is intentional. A package that cannot recover a public key should say "I need the app's crypto adapter," not squint at a signature and call it identity.

Coinbase also got a timeout bridge around its SDK callbacks. Completion handlers are like couriers: most arrive, some get lost, and your app should not stand at the door forever. The new bridge lets connect/request finish on success, timeout, or task cancellation, and uses a single-resume box so a late callback cannot crash the continuation after the timeout already fired.

### Engineer's wisdom (this pass)

A security default is only useful if the safe path is also passable. "Require proof" should mean "perform proof before persistence," not "reject every unverified receipt at the door." And every callback bridge needs an escape hatch; indefinite waits are just bugs with no stack trace.

## 2026-08-04 — Same Address, Different Chains, Separate Receipts

This pass fixed the kind of wallet bug that hides behind perfectly reasonable data. An EVM wallet often shows the same address on Ethereum, Polygon, Base, and friends. The app persisted accounts by `(address, chain)`, but the topic index used only the bare address, which meant each chain saved over the previous chain's receipt. Cleanup then had one surviving receipt and deactivated one chain, leaving the others dressed up as active accounts with no live session behind them.

The topic store now gives each chain-address pair its own claim ticket while still reading old bare-address records. Restore cleanup deletes the exact stale receipt it is processing and deactivates that receipt's chain, so Base can no longer accidentally wear Ethereum's coat. The regression test uses one address on Ethereum and Base, lets both go stale, and verifies both accounts are deactivated and both topic records disappear.

Ownership prompts got the same treatment: no more adapter-specific little challenge poems. Reown, Coinbase, and the custom IRN connector now share the same SIWE builder for EVM ownership, including domain, address, URI, chain id, nonce, issued-at, and expiration. The adapter tests decode the actual `personal_sign` bytes so a future drift back to a nonce-only prompt trips loudly.

MetaMask, Privy, and Dynamic also stopped getting a production green light for half a connector. Their unconfigured stubs were already unavailable; now even configured clients remain `experimental` until the protocols can delegate sessions, callbacks, events, and ownership semantics. A configured request pipe is useful, but it is not a full wallet lifecycle.

The WidgetRenderer crash from today's simulator audit was not a WalletConnectorKit crash. The process was Apple's `com.apple.chrono.WidgetRenderer-Default`, killed by a scene-create watchdog while RenderBox/Metal compiled/rendered in the simulator. This package has no WidgetKit target or rendering path, so it belongs in simulator/OS triage unless the host app produces a reproducible widget-render input.

### Engineer's wisdom (this pass)

Keys should match the thing you intend to clean up. If persistence says accounts are chain-scoped, every receipt that can later deactivate them needs to be chain-scoped too. Otherwise cleanup is just guessing with better type names.

## 2026-08-05 — A Green Badge Needs a Working Pen

This pass tightened a subtle release-contract problem in the custom IRN connector. The transport could complete the WalletConnect dance, but the default app lifecycle also asks wallets to prove EVM ownership before saving identity. Without a secp256k1 recovery provider, that proof fails closed. So the connector no longer walks around with a production badge by default unless the host injects the crypto pen it needs to verify the signature.

The semantic signing API also stopped pretending `"Hello"` was already wire-ready hex. `EVMWalletOperation.personalSign(message:)` now treats its message like a normal human-readable string and hex-encodes it through the text builder. The raw builder still exists for callers who already have `0x...` payloads; it just has to be chosen deliberately.

### Engineer's wisdom (this pass)

A readiness badge is a promise about the whole path a production app will take, not just the prettiest subsystem. If strict identity persistence needs a signature verifier, production readiness should ask whether that verifier is actually in the room.

## 2026-08-08 — Capabilities Stop Overpromising

Today's shipping fix was a menu problem. The embedded-wallet runtime family said, in broad strokes, "I can do EVM and Solana," but the two real embedded adapters in the package — Privy and Dynamic — are EVM-only doors. If the host app trusted the generic menu, it could send a user to Privy or Dynamic for a Solana signing flow and only discover the mismatch after the request hit the adapter.

So Privy and Dynamic now print their own menus: embedded wallet, EVM, message signing, and transaction signing. No Solana, no batch Solana signing, no sign-and-send claim. The broad runtime-family default stays where it is for a future embedded connector that genuinely supports more chains, but concrete production adapters now speak for themselves.

The second pass found the restaurant menu had two copies: the connector menu was fixed, but the public catalog menu still had "sign and send" printed under Privy and Dynamic. That matters because hosts often browse the catalog before they ever touch a connector instance. The catalog now matches the actual kitchen too.

### Engineer's wisdom (this pass)

Capabilities are contracts, not vibes. A connector should advertise only the routes it can actually drive, because routing bugs are still shipping bugs even when they fail safely.

## 2026-08-09 — Retiring the Audit Log, Keeping the Verdict

The append-only `AI-Audit-Log.md` had done its job. Across a long run of multi-model sessions it drove the SDK-free core to a fail-closed, adversarially-tested state and, just as usefully, it kept surfacing the one thing no automated session could ever close: the four live vendor clients (Reown, Coinbase, Privy, Dynamic) have never run against a real wallet on a real device. But a 1,200-line ledger of resolved defects is a maintenance liability once its findings are either fixed-and-tested or reduced to a small set of durable truths.

So the ledger is retired and its lasting conclusions moved to where they will actually be read: the QA checklist now carries the Manual Live-Wallet Suite as the explicit standing ship gate (the old AUD-022), the Known Limitations table (the old LIM-1…LIM-6), and a verification-status summary. `AGENTS.md` points future sessions there. The Auralis app's `P0-Physical-Device-QA-Suite.md` gained a live-wallet connection pass so the device gate lives in the plan the human actually runs on hardware.

### Engineer's wisdom (this pass)

A log that only grows is a log that stops being read. Findings belong in one of two places: fixed with a test that guards the fix, or distilled into the contract docs a maintainer opens on purpose. Provenance is worth preserving right up until it outweighs the signal — then the signal moves and the ledger goes.
