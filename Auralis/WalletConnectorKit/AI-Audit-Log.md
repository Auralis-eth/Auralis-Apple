# AI Audit & Fix Log

Shared, append-only record of AI-driven audits, fixes, and validations for **WalletConnectorKit**.
Designed for **multi-LLM, multi-session** work: any model in any session should be able to read this
file and understand what has been checked, what was fixed, how it was verified, and what remains open.

## How to use this document

- **Append, don't rewrite.** Add new entries at the top of each section. Never delete history — supersede it.
- **Cite specific sources.** Every claim of correctness must name *what* was used to verify it
  (a file+line, a doc URL, a test name, a build result). "Looks right" is not a source.
- **One entry per defect/gap/blocker.** Give each a stable ID so other sessions can reference it.
- **State what you could NOT resolve** and why. A partial fix with a documented reason is more useful
  than a silent gap.
- **Sign every entry** with the model/session so provenance is clear across LLMs.

### Entry status legend

| Status | Meaning |
|--------|---------|
| ✅ Resolved | Fixed and verified; verification source recorded |
| 🟡 Partial | Improved but not fully closed; remaining work noted |
| 🔵 Verified-OK | Audited, found correct as-is; no change needed |
| ⛔ Blocked | Cannot proceed; blocker and reason recorded |
| 🔴 Open | Identified, not yet addressed |

### Source-type tags (use in the "Sources" field)

- `code:` a file path + line range in this repo
- `test:` a test name / suite that exercises the behavior
- `build:` a build or compile result
- `doc:` official documentation (include URL + section)
- `spec:` a protocol/standard (e.g. WalletConnect v2, CAIP-2, EIP-155)
- `web:` other web reference (include URL + access date)
- `runtime:` observed behavior on device/simulator

---

## 1. Audit Sessions

High-level log of each audit pass. One row per session/agent run.

| Date | Model / Session | Scope audited | Entries produced | Overall verdict |
|------|-----------------|---------------|------------------|-----------------|
| 2026-08-07 | Opus 4.8 (session P, component-breakdown audit + fix) | Structured component-by-component production-readiness audit at the user's request: broke the package into (A) crypto & ownership verification, (B) transport (IRN relay + Sign engine), (C) persistence, (D) requests & validation, (E) domain/registry/lifecycle, (F) vendor adapters. Independently re-read the full security-critical surface end-to-end (`WalletConnectV2Crypto`, `WalletConnectorCryptoProvider`, both keychain stores, `WalletConnectSessionStateStore`, the entire `WalletConnectIRNTransportClient` incl. inbound type0/type1 gating + settle/update/extend/delete/event + response topic-binding + ack path + keepalive + JS-safe id minting, `WalletConnectIRNRelayClient`, `WalletConnectionLifecycleService`, `WalletSessionGrantValidator`, `WalletRequestValidation`/builders, `WalletConnectURI`, `WalletConnectDAppConnector` + ownership verifiers, `WalletReturnURLHandler`/`WalletInboundURLCoordinator`, and all four live vendor SDK clients Reown/Coinbase/Privy/Dynamic). Then fixed the two actionable code findings per user direction. | AUD-044 (A/C/D Verified-OK; F-1, F-2), AUD-043 (B-1 fix), AUD-042 (E-1 fix) | **Components A/C/D re-confirmed production-grade; one High trust-seam defect (E-1) and one Low→Medium teardown defect (B-1) found and fixed; core build green.** **E-1 (High, fixed):** `restoreSavedSessions` merged the topic record's connect-time `verified` bit with `session.addressVerified` via a fail-open `||`, so a wallet that swapped accounts via `wc_sessionUpdate` (which correctly clears the IRN transport's `addressVerified`) could be restored as ownership-verified across relaunch — bypassing `.requireVerified`. Fixed by gating the topic-bit fallback on `runtimeFamily.restoredVerificationIsAuthoritative` (true only for the custom IRN transport, whose session flag is authoritative). **B-1 (Low→Med, fixed):** the peer-facing `wc_sessionDelete` on `disconnect` was published from a `[weak self]` detached task, so a transport deallocated in the same turn (the common "remove wallet + tear down connector" flow) skipped it and left the wallet showing a stale live session — fixed by sealing the envelope on the actor and publishing via the strongly-held relay, independent of `self`. **F-1 (Medium, verify):** `LivePrivySDKClient` compiles behind `#if canImport(PrivySDK)` while the SPM product is `Privy`; if the vendored module name ≠ `PrivySDK` the live client silently drops from the build and the adapter ships stub-only — unverifiable without building against the SDK, folded into AUD-022 device QA. **F-2 (Low):** Coinbase `web3RPC` defaults a missing `eth_sendTransaction` `chainId` to `0x1` (unreachable today — core validation guarantees it — but a latent mainnet-default footgun). BuildProject → success 11.5s, 0 errors; diagnostics clean on all three edited files. AUD-022 device QA remains the standing ship gate. |
| 2026-08-07 | Opus 4.8 (session O, strict report-only production-readiness audit) | Independent principal re-read of the full security-critical surface end-to-end: crypto envelope + X25519/HKDF key derivation (`WalletConnectV2Crypto`), relay DID-JWT auth + base58 (`WalletConnectRelayAuth`), both keychain stores + access-group migration + relay-identity keychain, session-state store, the entire IRN transport (`WalletConnectIRNTransportClient` incl. inbound type0/type1 gating, dedup, settle/update/extend/delete/event, response topic-binding, ack path, keepalive, JS-safe id minting), the relay socket + reconnect/backoff (`WalletConnectIRNRelayClient`), lifecycle service, grant validator, request validation, URI parser, pending-request store, DApp connector + ownership verifiers, and the app-side `Web3SwiftWalletConnectorCryptoProvider`. Report-only per user direction (no fixes). | AUD-041 (Verified-OK + O-6, O-7) | **Confirm the standing verdict: the SDK-free custom IRN core is production-grade at the code level; AUD-022 device QA remains the standing ship gate (deferred by the user to a later day, not closed).** No new critical or high-severity code defect found this pass — the transport is fail-closed, authenticity never depends on topic secrecy, keychain items are correctly device-local/non-syncing/unlocked-only, and every prior code defect (AUD-013…AUD-040) stays resolved. Build reconfirmed green (BuildProject → success, 3.3s, 0 errors). New lower-severity follow-ups recorded: **O-6 (Medium, app-side)** EIP-1271 is unimplemented in `Web3SwiftWalletConnectorCryptoProvider` (`supportsSmartContractOwnership == false`), so under the default `.requireVerified` policy Safe / Coinbase Smart Wallet / ERC-4337 users **cannot connect** (fail-closed at verify) — a real functional gap for a wallet app targeting Coinbase; **O-7 (Low)** `KeychainAccessGroupMigration` treats `errSecDuplicateItem` on the target-group copy as "moved" then deletes the source, which can retain a stale divergent copy across a repeated partial migration. |
| 2026-08-07 | Opus 4.8 (session N, embedded-adapter audit + fix) | Line-by-line read of the last unexamined surface: `PrivyWalletConnector`/`LivePrivySDKClient`, `DynamicWalletConnector`/`LiveDynamicSDKClient`, `SolanaWalletConnector`, `DeepLinkWalletLauncher`/`WalletProviderDeepLink`, `WalletConnectionBoundaries`, `WalletSessionStore`. Package now read end-to-end (core → AUD-038, Reown/Coinbase → AUD-039, embedded → AUD-040). Then fixed the two live findings per user direction. | AUD-040 (DEF-1, DEF-2, DEF-3) | **Embedded adapters had a real multi-chain functional bug — now fixed; core unchanged and green.** **DEF-1 (Medium, fixed):** Privy & Dynamic pinned the granted session to one EVM chain, so `WalletSessionGrantValidator` rejected any request on a different EVM chain (Dynamic even computed a per-request `chainId` the grant made unreachable) — now advertise the EOA across all `WalletChain.evmChains`. **DEF-2 (Low, fixed):** both ignored `sessionId` (served `first` wallet) and logged the whole user out on any disconnect — now honor a derived per-address session id and scope logout. **DEF-3 (Low, documented):** dead public `WalletSessionStore` parallel API — left in place pending sign-off. Build green on iOS-sim (SRC-52, so both `#if canImport` clients compile with the changes); suite **203 / 197 passed / 6 skipped / 0 failed** (SRC-53), no regression. Live clients still lack host behavioral tests → behavior itself belongs to the AUD-022 device pass. |
| 2026-08-07 | Opus 4.8 (session M, adapter-surface audit + fix) | Independent line-by-line read of the previously-shallow surface: all four vendor adapters + their live SDK clients (`ReownWalletConnector`/`ReownAppKitLiveClient`, `CoinbaseWalletConnector`/`LiveCoinbaseWalletSDKClient`, Privy/Dynamic spot-checked), `ReownPendingRequestStore`, `WalletConnectorRegistry`, `WalletAccount`/`WalletAccountParser`, `WalletNamespace`, `WalletConnectJSONRPC`. Then fixed the one safe code finding per user direction. | AUD-039 (BLK, A-1…A-4) | **Adapters are correctly fail-closed and readiness-gated; one Low dead-code defect fixed; the live tier's lack of automated coverage is the concrete AUD-022 blocker.** No new critical code defect. **A-2 (Low, fixed):** Coinbase `web3RPC` carried an unreachable `wallet_switchEthereumChain` mapping the granted namespace already excludes — reconciled (behavior-preserving). **A-1 (Verified-OK):** the `.ethereum` `verifyOwnership(chain:)` default is an intentional ergonomic API with no in-package trigger (lifecycle passes the real chain) — kept, documented. **BLK:** every `#if os(iOS)` live client is uncovered by the host plan (compiles on the active iOS-sim destination per SRC-50, but compiling ≠ exercising) — reaffirms AUD-022 as the ship gate. Build green (SRC-50, iOS-sim destination); full suite **203 / 197 passed / 6 skipped / 0 failed** (SRC-51), identical to SRC-49 (A-2 behavior-preserving). |
| 2026-08-06 | Opus 4.8 (session L, strict re-audit + fix) | Independent principal re-read of the full security-critical surface (crypto envelope + key derivation, relay DID-JWT auth + base58, both keychain stores + the access-group migration, session-state store, the entire IRN transport incl. inbound pipeline/type0+type1 gating/dedup/settle/update/extend/delete/event/response-topic binding/keepalive/id-minting, the relay socket + reconnect, lifecycle service, grant validator, request validation, URI parser, pending-request store, DApp connector + ownership verifiers, inbound-URL coordinator + return-URL handler, `Package.swift`). Then fixed the one standing code defect per user direction. | AUD-038 (F-1, F-2) | **SDK-free core remains ship-ready at the code level; one Medium defect closed; AUD-022 device QA is still the single ship gate.** No new *critical* code defect found — the core is fail-closed and adversarially tested, and every prior code-level defect (AUD-013…AUD-037) stays resolved. **F-1 (Medium):** the `wc_sessionDelete` inbound path was the only peer-request case with no live-session guard, so a delete that merely decrypted on any known-symKey topic ran a full teardown + emitted `.sessionDeleted`. **F-2 (Medium):** the pairing topic was left subscribed/decryptable for the client's lifetime after settle (its symKey is a bearer secret from the URI), so combined with F-1 a party holding the pairing secret could drive a spurious teardown. Both fixed (delete now guards on a live session and idempotently acks otherwise; settle now tears down the pairing topic). Recorded O-3 (relay TLS pinning — deferred to host, deliberately not hardcoded), O-4 (capabilities→registry), O-5 (secret zeroization) as open follow-ups. Build green (SRC-48); full suite **203 total / 197 passed / 6 skipped / 0 failed** (SRC-49), +1 = the new pairing-topic-delete regression. |
| 2026-08-06 | Opus 4.8 (session K, strict re-audit + fix) | Independent principal re-read of the full security-critical surface (crypto envelope + key derivation, relay DID-JWT auth + base58, both keychain stores + the access-group migration, session-state store, the entire IRN transport incl. inbound pipeline/type1 gating/dedup/settle/update/extend/response-topic-binding/keepalive/id-minting, the relay socket + reconnect, lifecycle service, grant validator, URI parser, pending-request store, `WalletJSONValue`). Then fixed the two standing code findings from this pass per user direction. | AUD-037 (F-1, F-2) | **Core remains ship-ready at the code level; two lower-severity defects closed; AUD-022 device QA is still the single ship gate.** No new high-severity defect found — the transport is fail-closed and adversarially tested, and every prior code-level defect (AUD-013…AUD-036) stays resolved. **F-1 (Medium):** a *corrupt* relay-identity keychain record could never self-heal — `loadOrCreateKey` fell back to an ephemeral key forever without purging the bad bytes, silently and permanently losing cross-launch `client_id` stability; fixed by distinguishing `invalidTopicData` (purge + regenerate) from a transient/unreadable record (keep the non-overwriting fallback), with a new `deleteIdentityData()` seam + regression test. **F-2 (Low):** `KeychainAccessGroupMigration` ran its (idempotent) migration body outside the lock, letting the three stores run redundant concurrent full-service migrations on first launch; fixed by holding the lock across the whole one-shot migration. Build green (SRC-45); full package suite green — **202 total, 196 passed, 6 skipped, 0 failed** (SRC-46, SRC-47); diagnostics clean on all edited files. |
| 2026-08-06 | Opus 4.8 (session J, strict re-audit + fix) | Full re-read of the security-critical surface (crypto envelope + key derivation, relay DID-JWT auth + base58, both keychain stores + access-group migration, session-state store, the entire IRN transport incl. inbound pipeline/type1 gating/dedup/settle/update/extend/response-topic-binding/keepalive/**id-minting**, the relay socket + reconnect, lifecycle service, grant validator, DApp connector, URI parser, pending-request store, capabilities/state) **cross-referenced against the vendored reown-swift sources**, plus the app-side `Web3SwiftWalletConnectorCryptoProvider`. Then fixed the findings per user direction. | AUD-036 | **New CRITICAL ship blocker found + fixed (BLK-3):** `WalletConnectIRNTransportClient.nextID()` minted wallet-facing Sign RPC ids ≈1.8e18 — ~198× over JavaScript's `Number.MAX_SAFE_INTEGER` (2^53) — so any JS/RN wallet (incl. MetaMask Mobile) rounds the id, echoes a different one, and the transport's topic/id response binding never matches → **every signing request silently hangs to expiry.** reown deliberately uses a smaller Sign-tier id (`ms*1000`) for exactly this reason; the code had copied the relay tier (`ms*1_000_000`). Fixed `nextID()` to the Sign tier (+ regression test asserting `< 2^53`); the relay client's larger tier is correct (Rust relay) and left as-is. Also: made relay-auth `sub` stable per client (F-2), corrected the "canonical SIWE" docstring (F-3), and **verified the app secp256k1 provider** returns 64-byte X‖Y with no EIP-191 double-prefix (info gap #1 → Verified-OK). Build green (SRC-43); full package **177/177 passed, 0 failed** (SRC-44). Invisible to all 35 prior audits + `swift test` (only manifests against a real JS wallet) — this is the decisive evidence that **AUD-022 device QA is a genuine ship gate.** |
| 2026-08-06 | Opus 4.8 (session I, strict re-audit + fix, "make it ship-ready") | Full independent re-read of the security-critical surface (crypto envelope + key derivation, relay DID-JWT auth + base58, the entire IRN transport engine incl. inbound pipeline/type1 gating/dedup/settle/update/extend/response-topic-binding/keepalive/id-minting, both keychain stores + the new `KeychainAccessGroupMigration`, session-state store, lifecycle service, grant validator, DApp connector, URI parser, pending-request store, relay socket) **and the live app composition** (`AuralisWalletConnectionService`, `Web3SwiftWalletConnectorCryptoProvider`, `WalletConnectKeychainAccessGroup`). Then fixed the findings per user direction. | AUD-035 | **Ship-ready (SDK-free core + app EVM/Solana identity), modulo AUD-022 device QA.** The two prior open gates are now **closed in-app**: AUD-034 gap #3 — a real secp256k1 `Web3SwiftWalletConnectorCryptoProvider` (returns 64-byte `X‖Y`, `supportsRecovery=true`) is injected at both connector call sites, so readiness is `.productionReady` and EVM ownership no longer fails closed; AUD-034 C-1 — `WalletConnectKeychainAccessGroup` resolves a shared group at runtime and threads it into all three stores, `KeychainAccessGroupMigration` moves legacy items, and the README now correctly separates App Groups from Keychain access groups. **New defect found + fixed (AUD-035):** `restoreSavedSessions` silently clobbered the persisted active wallet with an arbitrary sort-ordered address on every relaunch for multi-wallet users, and flattened MRU — fixed to preserve the previously-active wallet when still restored. Also hardened relay `resubscribeAll` to isolate per-topic recovery failures on reconnect. On reflection, the session-H-era "type0 propose-response" note is **not** a defect (the type1 sender↔responder binding adds nothing against the party that already holds the pairing bearer secret, and the type0 path is required for legitimate rejections). Build green (SRC-40); full plan **200 total / 194 passed / 6 skipped / 0 failed** (SRC-41), +2 = the new active-wallet restore regression tests. |
| 2026-08-06 | Opus 4.8 (session H, strict audit + fix) | Independent principal re-audit re-reading the crypto envelope + key derivation, relay auth (DID-JWT + base58), both keychain stores incl. AUD-032 namespacing, the IRN transport (settle/update/extend/restore/dedup/ack/response-topic-binding/id-minting/keepalive), the relay socket, the lifecycle service, the grant validator, and the ownership verifiers; traced the app's actual composition in `AuralisWalletConnectionFeature`; pulled `WalletConnectRelayConfiguration` + searched the app for a `WalletConnectorCryptoProvider` conformance. Then, per user direction, fixed the top findings. | AUD-034 (C-1, F-1, F-4 + gap #2/#3 closure) | **Core remains ship-ready modulo AUD-022 device QA; three fixes landed.** New finding **C-1**: none of the three keychain stores set `kSecAttrAccessGroup`, so the README's "share session data with extensions" contract is silently broken *and* the AUD-028 cross-process premise is moot — fixed by threading an opt-in `accessGroup:` through all three stores (nil-default = unchanged secure behavior). **F-1**: grant validator read the typed-data signer at a hard-coded index 0 (correct for `_v4`, wrong for legacy v1 `[typedData, address]`) — fixed to locate the EVM-address-shaped param regardless of ordering. **F-4**: `restoreSavedSessions` aborted the whole restore on one bad record — fixed with a per-record `do/catch` + optional diagnostic sink. Gap-closure: relay `aud` = `relayURL.absoluteString` matches the reown pattern (no mismatch); the app currently wires `WalletConnectDAppConnector` with **no** `cryptoProvider`, so *all* EVM ownership verification fails closed today — no web3.swift→`WalletConnectorCryptoProvider` adapter exists. Build green (SRC-37). |
| 2026-08-05 | Opus 4.8 (session G, strict report-only audit) | Independent principal re-audit of the standing "good to ship" claim, report-only (no fixes) per user direction. Re-read the crypto provider + ownership verifiers + keccak, the V2 crypto envelope, the relay auth DID-JWT + base58, the IRN transport (restore/settle/update/extend/event/ack/dedup/response-topic-binding/id-minting/keepalive), the lifecycle service (persist/verify/restore/remove/rollback), all three keychain stores (topic/session-state/relay-identity) incl. the AUD-032 namespacing + migration, the DApp connector, and the grant validator. Verified the current **uncommitted** working tree compiles. | AUD-033 (Verified-OK) | **Confirm the verdict: ship the SDK-free core; the four live adapters remain gated on AUD-022 device QA (user is deferring that).** No new code defect found in my pass — every prior code-level defect (AUD-013…AUD-032) is resolved, and the core is fail-closed and adversarially tested. `BuildProject(buildForTesting:)` on the current tree → success, 2.8s, 0 errors (SRC-36); I did **not** re-run the full test plan this pass (last recorded green: SRC-35, 198/192/6-skip/0-fail). Only open items are the standing device-QA blocker (AUD-022, explicitly deferred) and low-severity opportunities (capabilities→registry wiring per AUD-031; relay TLS pinning; closed `WalletChain` enum per LIM-6; reconcile AUD-028's cross-process premise with the absence of a `kSecAttrAccessGroup`; duplicate `SRC-23`/`SRC-24` ids in this log's Sources Registry). |
| 2026-08-05 | Opus 4.8 (session F, strict audit + fix) | Independent principal audit re-reading the crypto provider + ownership verifiers + keccak, the IRN transport (settle/update/extend/restore/ack/dedup/id-minting), the lifecycle service (persist/verify/restore/remove), **all three keychain stores that share one service** (topic store, per-topic session-state store, relay-auth identity), the DApp connector, and the grant validator; traced the app's actual composition in `AuralisWalletConnectionFeature`. Then, per user direction, fixed the finding. | AUD-032 | **New ship blocker found in the SDK-free core — now fixed.** `KeychainWalletSessionTopicStore` shared its keychain service with the relay-auth identity and the (post-AUD-028) per-topic `session-record:` items, but enumerated the whole service with no account discriminator, so `loadAll()` mis-read foreign items as topic records — throwing `.invalidTopicData` on the relay identity's non-UTF-8 bytes (breaking cross-launch restore entirely) or, worse, deleting live session-state records via bogus topic keys. Masked by every prior audit because it only manifests with real, mixed-kind keychain items — exactly the host-skipped integration path. Fixed by namespacing topic accounts with a `session-topic:` prefix, filtering `loadAll` to that prefix, and adding a one-shot legacy migration. Build green; full plan **198 total / 192 passed / 6 skipped / 0 failed** (SRC-34, SRC-35) — +7 vs SRC-33 = 1 host-runnable discriminator test + 2 new gated keychain integration tests + the 4 prior gated skips. AUD-022 (live-adapter device QA) remains the standing blocker. |
| 2026-08-05 | Opus 4.8 (session E, fix pass) | Fixed five findings from the standing strict audit, per user direction (the live-wallet/device-QA blocker AUD-022 is explicitly deferred to a later manual pass). Independently re-read the crypto provider + ownership verifiers, all five EVM connectors, the IRN transport restore path, the keychain session-state store, and the capabilities vocabulary; reproduced build + full plan before and after. | AUD-027, AUD-028, AUD-029, AUD-030, AUD-031 | **Fixes landed; the SDK-free core still ships and the four live adapters remain gated on AUD-022 device QA.** Added opt-in **EIP-1271** smart-contract-wallet ownership (AUD-027 — previously EOA-only, so Safe/Coinbase-Smart-Wallet/ERC-4337 sessions failed closed silently under the default policy); converted the session-state keychain store to **one item per topic** to remove the cross-process clobber (AUD-028); made ownership-flag persistence **best-effort** so a keychain hiccup no longer fails a proven verification (AUD-029); surfaced restore **re-subscribe failures** as diagnostics instead of swallowing them (AUD-030); documented the `WalletConnectorCapabilities` vocabulary as forthcoming (AUD-031). Build green; full plan **195 total / 191 passed / 4 skipped / 0 failed** (SRC-32, SRC-33) — +4 vs SRC-31 = the new EIP-1271 async-verifier cases. |
| 2026-08-05 | Opus 4.8 (session D, strict re-audit + fix pass) | Independent re-audit of the standing "good to ship" claim on branch `music-mini-app`. Re-read the crypto provider + ownership verifiers + keccak, lifecycle service (persist/verify/restore/remove), session-state store, DApp connector (SIWE/ownership/callback), pending-request store, provider/capabilities/chain domain model, and Package manifest. Reproduced build + full package test plan from scratch. Then, per user direction, fixed AUD-026 + closed the AUD-010 KAT follow-up. | AUD-026, AUD-010F | **Confirm the prior verdict: ship the SDK-free core, gate the four live adapters on device QA.** Independent build green and I reproduced 188 total / 184 passed / 4 skipped / 0 failed (SRC-27, SRC-28) — matches the recorded green state. The core is mature, fail-closed, and adversarially tested; I found no new defect in it. The decisive open blocker is unchanged: **AUD-022 (⛔) — none of the four live vendor paths (Reown/Coinbase/Privy/Dynamic) has ever run against a real wallet/account on a device;** they compile + unit-pass only. New low-severity finding: dead duplicate SIWE/Solana/nonce builders left in `WalletConnectDAppConnector` after AUD-014R (AUD-026), with a stale `SRC-12` citation pointing at the now-dead `siweMessage`. |
| 2026-08-04 | Codex GPT-5 (fix pass) | Fixed custom IRN readiness overclaim and semantic EVM personal-sign text/raw mismatch; updated README, QA checklist, and Journal. | AUD-024, AUD-025 | **Resolved.** Custom IRN default readiness is now `.experimental` until a recovery-capable `WalletConnectorCryptoProvider` is injected, while explicit host overrides remain possible. `EVMWalletOperation.personalSign(message:)` now hex-encodes human-readable text; the raw builder still passes `0x...` payloads unchanged. Build green and package tests green: 188 total, 184 passed, 4 skipped, 0 failed (SRC-23, SRC-24). |
| 2026-08-04 | Opus 4.8 (session C, fix pass) | Fixed AUD-020 (registry trap) + AUD-021 (QA-checklist drift). Marked AUD-022 ⛔ Blocked (environment). Per user direction, advanced MetaMask/Privy/Dynamic/Solana toward "working": expanded Privy + Dynamic to the full connector lifecycle (connect→session, events, sessions, callbacks, EVM SIWE ownership) with Reown/Coinbase-parity readiness gating; documented MetaMask + Solana routing through WalletConnect/Reown. | AUD-023 | **AUD-020/021 resolved; AUD-022 blocked on device QA.** Privy/Dynamic are now full-lifecycle-capable and can reach `.productionReady` when the host injects a live vendor-SDK client + recovery provider + real metadata — but the **vendor SDK live clients are not written** (not linkable/verifiable here) and **no device QA exists** (AUD-022 now also covers Privy/Dynamic). MetaMask stays request-only (route via WalletConnect/Reown; SDK archived); Solana stays request-only. Full plan green: 188 total, 184 passed, 4 skipped, 0 failed (SRC-22). |
| 2026-08-04 | Opus 4.8 (session C) | Independent strict re-audit of the standing "good to ship" claim. Re-read core (crypto provider + ownership verifiers + keccak), lifecycle service (persist/restore/remove), both live adapters (Reown AppKit live client, Coinbase MWP live client), all four stub adapters (MetaMask/Privy/Dynamic/Solana), registry, catalog, provider/chain domain model. Re-ran the full package test plan from scratch. | AUD-020, AUD-021, AUD-022 | **Confirm the prior verdict, with sharper framing.** No new code defect blocks the SDK-free core — it is mature, fail-closed, adversarially tested, and my own run reproduced 182 passed / 4 skipped / 0 failed (SRC-20). The standing "good to ship" is only true if read as *ship the core*. The two live adapters (Reown/Coinbase) are code-complete and now correctly readiness-gated, but **remain unproven**: the entire Manual Live-Wallet Suite and every live vendor-SDK path is still unexecuted (AUD-022) — "should work," not "verified." MetaMask/Privy/Dynamic/Solana are stubs and cannot be routed to production (by design). New low-severity findings: a trapping registry initializer (AUD-020) and stale readiness wording in the QA checklist (AUD-021). |
| 2026-08-04 | Opus 4.8 | Independent principal re-audit of the "good to ship" claim: lifecycle restore/verify consistency, adapter readiness vs. the actual delegated surface, live Coinbase/Reown wrappers, crypto-provider composition defaults, chain model extensibility. Re-ran full test plan. | AUD-017…AUD-019, LIM-6 | **Ship the SDK-free core** — it is mature, fail-closed, adversarially tested (178 passed / 4 skipped / 0 failed). **The two `productionReady` adapters (Reown, Coinbase) are NOT turnkey:** SDK sessions silently drop from the active set on every cold launch under the default `.requireVerified` policy (AUD-017), and both default to a crypto provider that makes their own `verifyOwnership` throw (AUD-018). Neither blocks the core; both block shipping Reown/Coinbase as "just works." |
| 2026-08-04 | Codex GPT-5 | Fix-and-verify pass for AUD-013…AUD-015 plus simulator WidgetRenderer crash triage | AUD-013R…AUD-016 | Ship blockers addressed in package code. Same-address multi-chain topics are chain-scoped, Reown/Coinbase EVM ownership challenges share the canonical SIWE builder, and partial MetaMask/Privy/Dynamic wrappers no longer allow production routing. Build and package tests are green: 182 total, 178 passed, 4 skipped keychain integration tests, 0 failed. WidgetRenderer crash is not attributable to WalletConnectorKit. |
| 2026-08-04 | Codex GPT-5 | Principal shipping audit focused on previously weak areas: lifecycle/account cleanup, active/session stores, request builders/validation, adapter readiness boundaries, ownership challenge parity, current build/test health | AUD-013…AUD-015 | Not good to ship all advertised providers/features as-is. Core custom IRN transport remains strong and tests pass, but there are shipping blockers/gaps around same-address multi-chain lifecycle cleanup, non-canonical ownership challenges in Reown/Coinbase adapters, and stub adapter readiness contracts that can advertise production readiness without session/callback support. |
| 2026-08-04 | Opus 4.8 | First-pass core review: Crypto (v2 crypto, relay auth), Transport (IRN Sign engine, URI), Persistence (Keychain topic store), Requests (grant validator), Domain (address extractor) | AUD-001…AUD-006, LIM-1…LIM-3 | Core is mature and heavily hardened. No defects found this pass. Build clean; 160/160 package tests pass. Three deliberate, documented trade-offs recorded as limitations. Adapters + remaining transport files not yet audited. |
| 2026-08-04 | Opus 4.8 | Second pass: all six adapters (Coinbase, MetaMask, Reown incl. live client, Privy, Dynamic, Solana), remaining Transport (relay socket, DApp connector/SIWE, sign-protocol tags, relay config, inbound-URL/return-URL), Persistence (session-state store), Requests (pending store, JSON value), ownership verifiers, and test coverage/logic across the security-critical suites | AUD-007…AUD-012, LIM-4, LIM-5 | No defects found. Ownership verification (EVM secp256k1 + Solana ed25519) fails closed; adapters gate production use behind `isConfigured`; relay socket coalesces/reconnects/dedups correctly. Tests are genuinely adversarial (forged responses, malicious re-settle, tamper detection, reown parity vectors) — high quality, not box-checking. 160/160 pass. Two more documented trade-offs recorded. |

---

## 2. Sources Registry

Canonical list of authoritative sources relied upon, so multiple sessions cite them consistently.
Reference these by ID (e.g. `SRC-1`) in entries below.

> ⚠️ Verification method for the specs below: cross-referenced from model knowledge (cutoff Jan 2026)
> **against the in-code `reown-swift` citations** the source files already carry (e.g.
> `WalletConnectV2Crypto` cites `WalletConnectKMS`, `WalletConnectRelayAuth` cites
> `ClientIdAuthenticator` / `RelayAuthPayload`, `WalletConnectURI` cites ERC-1328). They were **not**
> re-fetched live in this pass. A future session should WebFetch the URLs and stamp an access date to
> upgrade these from "knowledge-verified" to "source-verified".

| ID | Type | Reference | Notes / version / verification |
|----|------|-----------|--------------------------------|
| SRC-1 | spec | WalletConnect v2 **Sign** API (`wc_sessionPropose/Settle/Update/Extend/Delete/Request/Ping/Event`) — specs.walletconnect.com/2.0 | Knowledge-verified; matches transport method/tag handling |
| SRC-2 | spec | WalletConnect **Relay** auth — DID-JWT `client_auth` (EdDSA, `did:key` multicodec `0xed01`) | Knowledge-verified vs `WalletConnectRelayAuth`; **not** live-fetched |
| SRC-3 | spec | WalletConnect **KMS / crypto envelope** — X25519+HKDF-SHA256, ChaCha20-Poly1305, type0/type1 envelopes, `SHA256(symKey)` topics | Knowledge-verified vs `WalletConnectV2Crypto` + reown code comments |
| SRC-4 | spec | **CAIP-2 / CAIP-10 / CAIP-25** — chain, account, and session-namespace identifiers | Knowledge-verified vs `SessionAddressExtractor`, `scopedAccountsAndNamespaces` |
| SRC-5 | spec | **ERC-1328** — `wc:` pairing URI format (incl. bracket-grouped `methods`) | Knowledge-verified vs `WalletConnectURI` |
| SRC-6 | spec | **EIP-155** chain IDs; personal_sign / eth_signTypedData / eth_sendTransaction signer params | Knowledge-verified vs `WalletSessionGrantValidator` |
| SRC-7 | ref | `reown-swift` (formerly WalletConnectSwiftV2) — github.com/reown-com/reown-swift | Cited throughout source as the reference impl; not independently checked out |
| SRC-8 | doc | Apple **CryptoKit** (`Curve25519`, `ChaChaPoly`, `HKDF`, `SHA256`) | Knowledge-verified; `DocumentationSearch` not run this pass |
| SRC-9 | doc | Apple **Keychain Services** (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, `SecItem*`) | Knowledge-verified vs `KeychainSessionTopicStore` + relay identity keychain |
| SRC-10 | build | `BuildProject(buildForTesting: true)` → success, 2.9s, 0 errors (2026-08-04) | Baseline compile signal |
| SRC-11 | test | `DEVELOPER_DIR=…/Xcode-beta swift test` → **160 tests / 17 suites passed**, 0.35s (2026-08-04, re-run confirmed) | Behavioral verification; see [[swift-test-needs-xcode-beta-developer-dir]] for why the beta DEVELOPER_DIR is required |
| SRC-12 | spec | **EIP-4361** (Sign-In with Ethereum) message format | Knowledge-verified vs `WalletOwnershipChallengeMessageBuilder.evmSIWEMessage` (the shared builder; corrected from the now-deleted `WalletConnectDAppConnector.siweMessage` per AUD-026) + test "verifyOwnership issues a canonical EIP-4361 SIWE challenge" |
| SRC-13 | spec | **EIP-191** personal-sign digest (`\x19Ethereum Signed Message:\n`); secp256k1 recovery-id 0/1 vs 27/28 | Knowledge-verified vs `WalletOwnershipVerifier`; recovery-id agnosticism proven by test |
| SRC-14 | spec | WalletConnect **IRN relay** JSON-RPC (`irn_subscribe/publish/unsubscribe/fetchMessages/subscription`) + Sign relay **tags 1100–1115** and TTLs | Knowledge-verified vs `WalletConnectIRNRelayClient` + `WalletConnectSignProtocol.ttl(for:)` |
| SRC-15 | doc | Apple **CryptoKit `Curve25519.Signing`** (ed25519 `isValidSignature`) | Knowledge-verified vs `WalletSolanaOwnershipVerifier` |
| SRC-16 | build | `BuildProject(buildForTesting: true)` → success, 2.072s, 0 errors (2026-08-04) | Current Codex GPT-5 audit compile signal |
| SRC-17 | test | `RunAllTests` on active `WalletConnectorKit-Package` test plan → 181 total, 177 passed, 4 skipped keychain integration tests, 0 failed (2026-08-04) | Current behavioral verification; skipped tests are real-keychain integration paths gated by environment availability |
| SRC-18 | build | `BuildProject(buildForTesting: true)` → success, 2.855s, 0 errors (2026-08-04 12:50 MDT) | Final post-fix compile verification for AUD-013…AUD-015 |
| SRC-19 | test | `RunAllTests` on active `WalletConnectorKit-Package` test plan → 182 total, 178 passed, 4 skipped keychain integration tests, 0 failed (2026-08-04 12:47 MDT) | Post-fix behavioral verification; skipped tests are real-keychain integration paths gated by environment availability |
| SRC-20 | test | `RunAllTests` on active `WalletConnectorKit-Package` test plan → **186 total, 182 passed, 4 skipped keychain integration, 0 failed** (2026-08-04 18:22 MDT, Opus 4.8 session C) | Independent re-run reproducing the green state; the 4 skips are the same environment-gated real-keychain integration paths |
| SRC-21 | test | Post-AUD-020-fix: full plan **186 total, 182 passed, 4 skipped, 0 failed** (18:31 MDT) + new `registryToleratesDuplicateProviderIDs` passes in isolation (18:31 MDT) | Verifies the registry duplicate-id fix and confirms no regression |
| SRC-22 | test | Post-Privy/Dynamic full-lifecycle expansion: full plan **188 total, 184 passed, 4 skipped, 0 failed** (18:39 MDT) | Verifies AUD-023; new `configuredEmbeddedAdaptersReachProductionWithOwnershipDependencies` passes and `configuredPartialProviderAdaptersRemainExperimental` still holds |
| SRC-23 | web | Privy iOS SDK [github.com/privy-io/privy-ios](https://github.com/privy-io/privy-ios) latest **2.14.0**; SPM library product **`Privy`** (binary target/module `PrivySDK`). Dynamic [github.com/dynamic-labs/swift-sdk-and-sample-app](https://github.com/dynamic-labs/swift-sdk-and-sample-app) **1.2.0**; SPM library product **`DynamicSDKSwift`** (wrapper target `DynamicSDKSwiftWrapper`), iOS 15+. MetaMask [github.com/MetaMask/metamask-ios-sdk](https://github.com/MetaMask/metamask-ios-sdk) **archived read-only 2026-02-26**. Solana: no native-Swift SPM MWA dApp SDK (Android-first; iOS lacks background websocket) — only the CocoaPods Safari-extension walletlib. (accessed 2026-08-05) | SDK viability verification for AUD-023 |
| SRC-24 | build | `swift package resolve` + `swift build` (DEVELOPER_DIR=Xcode-beta) → resolved Privy 2.14.0 + Dynamic 1.2.0 alongside the existing graph, **Build complete 6.45s, 0 errors** (2026-08-05 ~06:15 MDT) | Confirms the two new SPM deps resolve and the manifest/product names are valid |
| SRC-25 | build | `xcodebuild -scheme WalletConnectorKit-Package -destination 'platform=iOS Simulator,name=iPhone 17'` → **BUILD SUCCEEDED** (exit 0) with `LivePrivySDKClient.swift` + `LiveDynamicSDKClient.swift` compiled against the linked Privy/Dynamic XCFrameworks (2026-08-05 ~06:40 MDT). First attempt surfaced real Swift-6 region-isolation errors in the Dynamic client, fixed by making it nonisolated `@unchecked Sendable`. | iOS-compile verification of the two live clients — the only build in which the `#if canImport(...)` code paths are exercised |
| SRC-26 | code | Real SDK APIs read from the vendored `.swiftinterface` files: Privy `PrivySDK.xcframework/.../arm64-apple-ios.swiftinterface` (`PrivySdk.initialize(config:)`, `Privy.getUser()`, `PrivyUser.embeddedEthereumWallets`, `EmbeddedEthereumWalletProvider.request(_:)`, `EthereumRpcRequest.personalSign(message:address:)`); Dynamic `DynamicSDKSwift.xcframework/.../arm64-apple-ios.swiftinterface` (`DynamicSDK.initialize(props:)`, `.auth.authenticatedUser`, `.wallets.primary`/`.userWallets`, `.evm.request(method:params:wallet:chainId:)`, `.auth.logout()`) | Authoritative source for the live-client implementations (not inferred) |
| SRC-23 | build | `BuildProject(buildForTesting: true)` → success, 15.102s, 0 errors (2026-08-04 21:11 MDT, Codex GPT-5 fix pass) | Verifies AUD-024/AUD-025 compile cleanly |
| SRC-24 | test | `RunAllTests` on active `WalletConnectorKit-Package` test plan → **188 total, 184 passed, 4 skipped, 0 failed** (2026-08-04 21:11 MDT, Codex GPT-5 fix pass) | Verifies AUD-024/AUD-025 behavior; the 4 skips are real-keychain integration paths gated by environment availability |
| SRC-27 | build | `BuildProject(buildForTesting: true)` → success, 3.251s, 0 errors (2026-08-05 12:34 MDT, Opus 4.8 session D) | Independent re-audit compile signal on branch `music-mini-app` |
| SRC-28 | test | `RunAllTests` on active `WalletConnectorKit-Package` test plan → **188 total, 184 passed, 4 skipped, 0 failed** (2026-08-05 12:34 MDT, Opus 4.8 session D) | Independent reproduction of the green state; same 4 environment-gated real-keychain skips |
| SRC-29 | web | `emn178/js-sha3` reference test suite — [github.com/emn178/js-sha3/blob/master/tests/test.js](https://github.com/emn178/js-sha3/blob/master/tests/test.js) (accessed 2026-08-05) | Source of the added original-Keccak-256 KAT vectors (fox sentences + 341-byte MD5-description string). js-sha3 is a widely-used reference JS Keccak/SHA3 implementation; `keccak_256` = Ethereum-style original Keccak (0x01 padding), distinct from `sha3_256` |
| SRC-30 | build | `BuildProject(buildForTesting: true)` → success, 17.396s, 0 errors (2026-08-05 12:44 MDT, Opus 4.8 session D) | Post-fix compile verification for AUD-026 (dead-code + import removal) and AUD-010F (KAT vectors) |
| SRC-31 | test | `RunAllTests` on active `WalletConnectorKit-Package` test plan → **191 total, 187 passed, 4 skipped, 0 failed** (2026-08-05 12:44 MDT, Opus 4.8 session D) | Post-fix behavioral verification; +3 vs SRC-28 = the new Keccak parameterized cases (all pass, incl. the 341-byte multi-block vector); same 4 environment-gated real-keychain skips |
| SRC-32 | build | `BuildProject(buildForTesting: true)` → success, 0 errors (2026-08-05, Opus 4.8 session E) | Post-fix compile verification for AUD-027…AUD-031 (EIP-1271 hook, per-topic keychain store, best-effort flag persist, restore diagnostics, capabilities doc) |
| SRC-33 | test | `RunAllTests` on active `WalletConnectorKit-Package` test plan → **195 total, 191 passed, 4 skipped, 0 failed** (2026-08-05, Opus 4.8 session E) | Post-fix behavioral verification; +4 vs SRC-31 = the new `WalletMultiChainOwnershipTests` EIP-1271 async-verifier cases (EOA still verifies, contract wallet verifies via the on-chain fallback, non-EOA fails closed without SC support, misconfigured SC provider fails loud); same 4 environment-gated real-keychain skips |
| SRC-34 | build | `BuildProject(buildForTesting: true)` → success, 12.241s, 0 errors (2026-08-05, Opus 4.8 session F) | Post-fix compile verification for AUD-032 (topic-store account namespacing + legacy migration) |
| SRC-35 | test | `RunAllTests` on active `WalletConnectorKit-Package` test plan → **198 total, 192 passed, 6 skipped, 0 failed** (2026-08-05, Opus 4.8 session F) | Post-fix behavioral verification for AUD-032. +7 vs SRC-33: the host-runnable `WalletConnectDeepLinkTests.topicStoreAccountKeysAreNamespaced` (discriminator/round-trip/no-collision) passes on host; the 2 new AUD-032 keychain integration tests (`keychainTopicStoreLoadAllIgnoresForeignRecords`, `keychainTopicStoreMigratesLegacyUnnamespacedRecord`) join the 4 pre-existing environment-gated real-keychain skips (6 total), to be exercised in AUD-022 device QA |
| SRC-36 | build | `BuildProject(buildForTesting: true)` → success, 2.804s, 0 errors (2026-08-05, Opus 4.8 session G) | Compile signal for the current **uncommitted** working tree during the report-only re-audit (AUD-033) |
| SRC-37 | build | `BuildProject(buildForTesting: true)` → success, 19.694s, 0 errors (2026-08-06, Opus 4.8 session H) | Post-fix compile verification for AUD-034 (C-1 access-group threading across three keychain stores, F-1 typed-data signer fix, F-4 per-record restore isolation) |
| SRC-39 | build+test | `BuildProject(buildForTesting: true)` → success, 14.669s, 0 errors, then `RunAllTests` → **198 total / 192 passed / 6 skipped / 0 failed** (2026-08-06, Opus 4.8 session H) | Verifies the AUD-034 follow-up work (cross-access-group `KeychainAccessGroupMigration` wired into all three stores; per-record restore isolation). Same 6 environment-gated real-keychain skips; no regressions. App-target files (`Web3SwiftWalletConnectorCryptoProvider`, feature wiring) are outside this package workspace and not compiled here. |
| SRC-38 | code | App composition read live: `Auralis/Aura/WalletConnection/AuralisWalletConnectionFeature.swift:166` and `:173` both construct `WalletConnectDAppConnector(...)` with **no** `cryptoProvider:` argument; repo-wide grep for a non-package `WalletConnectorCryptoProvider` conformance / `recoverPublicKey` bridge returns nothing outside `web3.swift`'s own `KeyUtil`. `WalletConnectRelayConfiguration.swift:34-45` builds the socket URL and `WalletConnectRelayAuth.createToken` sets `aud = relayURL.absoluteString` (`wss://relay.walletconnect.org`). (accessed 2026-08-06) | Evidence for the AUD-034 gap #2/#3 closures |
| SRC-40 | build | `BuildProject(buildForTesting: true)` → success, 14.633s, 0 errors (2026-08-06, Opus 4.8 session I) | Post-fix compile verification for AUD-035 (active-wallet restore preservation + relay `resubscribeAll` per-topic isolation) |
| SRC-41 | test | `RunAllTests` on active `WalletConnectorKit-Package` test plan → **200 total, 194 passed, 6 skipped, 0 failed** (2026-08-06, Opus 4.8 session I) | Post-fix behavioral verification for AUD-035; +2 vs SRC-35/39 = `WalletConnectionCoreTests.lifecycleRestorePreservesActiveWallet` (persisted active survives relaunch, is not clobbered by the sort-order-last address) + `.lifecycleRestoreFallsBackWhenActiveGone` (falls back when the prior active is no longer restored). Same 6 environment-gated real-keychain skips; no regressions |
| SRC-42 | code | App composition re-read live (2026-08-06, session I): `Auralis/Auralis/Aura/WalletConnection/AuralisWalletConnectionFeature.swift:239` injects `Web3SwiftWalletConnectorCryptoProvider()` into `WalletConnectDAppConnector(cryptoProvider:)` (and `:249` in the failure path); `Web3SwiftWalletConnectorCryptoProvider.swift` implements real secp256k1 recovery (returns 64-byte `X‖Y`, `supportsRecovery=true`, EIP-1271 left `false` with a documented TODO); `:217-231` resolves `WalletConnectKeychainAccessGroup.resolved` and threads it into `KeychainWalletSessionTopicStore`, `KeychainWalletConnectSessionStateStore`, and `WalletConnectKeychainRelayAuthProvider`. Supersedes SRC-38 (the no-cryptoProvider snapshot). | Evidence that AUD-034 gap #3 (EVM recovery provider) and C-1 (shared keychain access group) are now closed in app composition |
| SRC-45 | build | `BuildProject(buildForTesting: true)` → success, 11.5s, 0 errors (2026-08-06, Opus 4.8 session K) | Post-fix compile verification for AUD-037 (relay-identity corrupt-record self-heal + access-group migration lock scope); `XcodeRefreshCodeIssuesInFile` also clean on `WalletConnectRelayAuth.swift`, `KeychainAccessGroupMigration.swift`, and `WalletReviewFixesTests.swift` |
| SRC-46 | test | `RunSomeTests` on `WalletReviewFixesTests` (WalletConnectorKit-Package plan) → **12 passed, 0 failed** (2026-08-06, Opus 4.8 session K) | Behavioral verification for AUD-037 F-1: new `relayIdentityCorruptRecordSelfHeals` passes (corrupt record purged once → fresh identity persisted → stable `client_id` thereafter) alongside the retained transient-error/valid-key cases |
| SRC-47 | test | `RunAllTests` on `WalletConnectorKit-Package` plan → **202 total, 196 passed, 6 skipped, 0 failed** (2026-08-06, Opus 4.8 session K) | Full-suite no-regression check after the AUD-037 fixes; +1 vs SRC-41 = the new corrupt-record test. Same 6 environment-gated real-keychain skips |
| SRC-48 | build | `BuildProject(buildForTesting: true)` → success, 7.9s, 0 errors (2026-08-06, Opus 4.8 session L) | Post-fix compile verification for AUD-038 (delete-path live-session guard + post-settle pairing-topic teardown) |
| SRC-49 | test | `RunAllTests` on `WalletConnectorKit-Package` plan → **203 total, 197 passed, 6 skipped, 0 failed** (2026-08-06, Opus 4.8 session L) | Post-fix behavioral verification for AUD-038; +1 vs SRC-47 = `WalletConnectSignEngineTests.pairingTopicDeleteIsIgnored` (a `wc_sessionDelete` injected on the lingering pairing topic neither tears down the settled session nor emits `.sessionDeleted`, and the session key still round-trips a request). Same 6 environment-gated real-keychain skips; no regressions |
| SRC-50 | build | `BuildProject(buildForTesting: true)` → success, 6.1s, 0 errors (2026-08-07, Opus 4.8 session M) | Post-fix compile verification for AUD-039 A-2. Active run destination **iPhone Air (iOS 27) Simulator** (confirmed via `XcodeListRunDestinations`), so the `#if os(iOS)` `LiveCoinbaseWalletSDKClient` **is** in the compile — the edited switch arm is genuinely type-checked (not excluded as it would be on a macOS destination) |
| SRC-51 | test | `RunAllTests` on `WalletConnectorKit-Package` plan → **203 total, 197 passed, 6 skipped, 0 failed** (2026-08-07, Opus 4.8 session M) | No-regression check after AUD-039 A-2 (behavior-preserving dead-arm removal); identical counts to SRC-49. Same 6 environment-gated real-keychain skips |
| SRC-52 | build | `BuildProject(buildForTesting: true)` → success, 7.8s, 0 errors (2026-08-07, Opus 4.8 session N) | Post-fix compile verification for AUD-040 (DEF-1 multi-chain embedded session + DEF-2 sessionId honoring). Active destination **iPhone Air (iOS 27) Simulator**, so both `#if canImport(PrivySDK)` `LivePrivySDKClient` and `#if canImport(DynamicSDKSwift)` `LiveDynamicSDKClient` are in the compile and genuinely type-checked (they are excluded on a macOS destination) |
| SRC-53 | test | `RunAllTests` on `WalletConnectorKit-Package` plan → **203 total, 197 passed, 6 skipped, 0 failed** (2026-08-07, Opus 4.8 session N) | No-regression check after AUD-040; identical counts to SRC-51. NOTE: the live Privy/Dynamic clients have **no** host behavioral tests (they need the vendor SDK types + an authenticated user), so this run validates *no regression + compile*, not the multi-chain grant behavior itself — that is part of the AUD-022 device pass |

---

## 3. Defects / Gaps / Blockers

One entry per issue. Copy the template. Newest at top.

### AUD-044 — Component-breakdown audit: crypto (A), persistence (C), requests (D) re-confirmed ship-ready; Privy build-gate + Coinbase chainId-default follow-ups
- **Status:** 🔵 Verified-OK (A crypto & ownership verification, C persistence, D requests & validation); 🟡 Partial (F-1 Privy build-gate — folded into AUD-022 device QA); 🔴 Open / low (F-2 Coinbase chainId default — latent, currently unreachable)
- **Type:** Audit (component breakdown) + two follow-ups
- **Severity:** No new Critical/High in A/C/D. F-1 Medium (unverifiable here). F-2 Low.
- **Area:** Crypto | Persistence | Requests | Adapter:Privy | Adapter:Coinbase
- **Found by:** Opus 4.8 (session P) on 2026-08-07
- **Description:**
  - **A — Crypto & ownership verification (Verified-OK):** re-confirmed the v2 KMS primitives (X25519→HKDF-SHA256, ChaCha20-Poly1305 combined sealbox, SHA256 topic), the type1 envelope length guard (`>= 33`), fail-loud CSPRNG for symKey/nonce/relay-subject, and `WalletOwnershipVerifier` fail-closed semantics (tries both `27/28` and `0/1` recovery-id conventions and rethrows when no candidate recovers rather than returning a silent `false`; rejects any recovered-key length other than 64/65 before hashing). Solana ownership is self-contained ed25519. No defect.
  - **C — Persistence (Verified-OK):** per-topic keychain items (no shared-blob cross-process clobber), fail-closed `loadAll` (unreadable keychain never mistaken for "no sessions"), corrupt-item purge without dropping siblings, `WhenUnlockedThisDeviceOnly` + non-syncing + macOS data-protection keychain, and prefix-namespacing (`session-record:` / `session-topic:`) so the shared service never cross-reads foreign kinds. The documented address+chain multi-chain cleanup nuance remains tracked under AUD-013 (not a regression).
  - **D — Requests & validation (Verified-OK):** `WalletRequestValidation` enforces EVM quantity/address/calldata shape, Solana base64 encoding, and an expiry window with 1s clock tolerance; `WalletSessionGrantValidator` locates the EVM signer by address shape (defeating the v1-vs-v4 typed-data ordering trap) and binds signer-address checks per method; `WalletPendingRequestStore` buffers early outcomes and uses `reject` (not `fail`) on cancellation so a late waiter cannot inherit a stale error.
  - **F-1 (Medium, verify):** `LivePrivySDKClient` is wrapped in `#if canImport(PrivySDK)` and does `import PrivySDK`, but `Package.swift` links `.product(name: "Privy", package: "privy-ios")`. If the module the SDK actually vends is not exactly `PrivySDK`, `canImport(PrivySDK)` is always false, the entire live client drops from the build, and `PrivyWalletConnector` can only be constructed with `UnconfiguredPrivySDKClient` — i.e. a stub-only adapter that *looks* wired. The Dynamic adapter uses the same pattern but its module (`DynamicSDKSwift`) matches its product. Cannot be confirmed without building against the SDK on-device.
  - **F-2 (Low):** `LiveCoinbaseWalletSDKClient.web3RPC` defaults a missing `eth_sendTransaction` `chainId` to `"0x1"` (mainnet). Currently unreachable because `WalletRequestValidation.validateTransactionParam` guarantees a valid `chainId`, but a silent mainnet default on a value-bearing transaction is a latent footgun if that validation is ever relaxed — prefer to throw on a missing chainId here too.
- **Root cause:** F-1 — a `canImport` module-name guard that may not match the vendored module; F-2 — a defensive default that duplicates (and could outlive) a guarantee enforced upstream.
- **Fix:** None applied for F-1/F-2 this session. F-1 is a build-configuration verification that must run during the deferred AUD-022 device QA (build the app scheme with the Privy SDK linked and confirm `PrivyWalletConnector(...).readiness != .unavailable`). F-2 left as a documented latent footgun pending sign-off (one-line change: throw instead of defaulting). A/C/D require no change.
- **Sources used to verify:** `code:Sources/WalletConnectorKit/Crypto/WalletConnectorCryptoProvider.swift:203-333`; `code:Sources/WalletConnectorKit/Persistence/WalletConnectSessionStateStore.swift`; `code:Sources/WalletConnectorKit/Persistence/KeychainSessionTopicStore.swift`; `code:Sources/WalletConnectorKit/Requests/WalletRequest.swift` + `WalletSessionGrantValidator.swift` + `WalletPendingRequestStore.swift`; `code:Sources/WalletConnectorKitPrivyAdapter/LivePrivySDKClient.swift:1-3` vs `Package.swift:84`; `code:Sources/WalletConnectorKitCoinbaseAdapter/LiveCoinbaseWalletSDKClient.swift:252`; `build:` BuildProject → success, 11.5s, 0 errors (2026-08-07).
- **Could not fully resolve because:** F-1 depends on the vendored Privy module name, only observable by building against the linked SDK (AUD-022 device QA, deferred by the user).
- **Follow-up / owner:** Fold F-1 into [[AUD-022]] device QA; decide F-2 (throw vs default) at next fix pass.
- **Signed:** Opus 4.8 (session P)

---

### AUD-043 — Remote `wc_sessionDelete` on disconnect could be silently dropped, leaving a stale live session in the wallet
- **Status:** ✅ Resolved
- **Type:** Defect
- **Severity:** Low→Medium (local teardown was always correct; only peer notification could be lost — a stale "connected" entry in the user's wallet app, no security impact)
- **Area:** Transport
- **Found by / fixed by:** Opus 4.8 (session P) on 2026-08-07
- **Description:** `WalletConnectIRNTransportClient.disconnect(topic:)` tore down local state synchronously (correct) but published the peer-facing `wc_sessionDelete` and the `unsubscribe` from a detached `Task { [weak self, relay = relayClient] }` that built the delete envelope via `self?.publishRequest(...)`. If the transport (and its owning connector) was deallocated in the same turn as `disconnect()` returned — the common "user removes the wallet, UI tears down the connector" flow — `self` was already `nil`, the `publishRequest` was skipped, and the wallet was never told the session ended, leaving a stale live session on the peer side. Only the peer notification was best-effort and droppable; local state was already gone.
- **Root cause:** the sealed-envelope construction was coupled to the actor (`self?.publishRequest`), so peer notification inherited the actor's lifetime instead of the (peer-lifetime) relay's.
- **Fix:** Extracted a `nonisolated static func sealedType0Message(method:params:id:symKey:)` (encode → ChaCha20-Poly1305 seal → base64 type0 envelope) and rewrote `disconnect` to seal the delete envelope **on the actor** (before the task) and hand the detached task only the finished message plus the strongly-held `relayClient`. The task no longer captures `self`, so the `wc_sessionDelete` is published (and the topic unsubscribed) even if the transport deallocates immediately after `disconnect()` returns. `publishRequest` now delegates its sealing to the same helper (behavior-preserving). `code:Sources/WalletConnectorKit/Transport/WalletConnectIRNTransportClient.swift:431-465` (disconnect task), `:1116-1149` (`publishRequest` + `sealedType0Message`).
- **Sources used to verify:** `code:` as above; `build:` BuildProject → success, 11.5s, 0 errors (2026-08-07); `diag:` XcodeRefreshCodeIssuesInFile → 0 issues on the edited transport file.
- **Follow-up / owner:** A host-behavioral confirmation (peer actually receives the delete after connector teardown) belongs to [[AUD-022]] device QA.
- **Signed:** Opus 4.8 (session P)

---

### AUD-042 — Ownership-verified trust could survive an account-swapping `wc_sessionUpdate` across relaunch (fail-open restore merge)
- **Status:** ✅ Resolved
- **Type:** Defect (security — ownership-verification bypass across restore)
- **Severity:** High
- **Area:** Domain / Lifecycle
- **Found by / fixed by:** Opus 4.8 (session P) on 2026-08-07
- **Description:** The trust seam between the transport and `WalletConnectionLifecycleService.restoreSavedSessions` was fail-open. The custom IRN transport does the right thing — `handleUpdate` recomputes `addressVerified = existing.addressVerified && !accountsChanged` and re-persists, so after a wallet swaps accounts via `wc_sessionUpdate` the transport's session (and its persisted record) correctly reads **unverified** (`WalletConnectIRNTransportClient.swift:854`). But the lifecycle keeps a **separate** trust bit — the topic record's `verified` flag, written once at connect in `persistApprovedSession` and never reset on update — and restore merged the two with `session.addressVerified || savedTopic.verified`. **Exploit:** a wallet settles address A (user proves ownership → topic record `verified = true`), then sends `wc_sessionUpdate` swapping to attacker address B on the same proposed chain; in-memory trust for B is correctly `false`, but on the next cold launch `false || true == true`, so B is restored into the active set as ownership-verified without ever being proven — bypassing the default `.requireVerified` policy. The `|| savedTopic.verified` fallback is legitimate for vendor-SDK families (whose store cannot carry `addressVerified`, so they always restore `false`), but strictly too permissive for the IRN transport whose session flag is authoritative.
- **Root cause:** a single OR-merge applied to two families whose `session.addressVerified` has different trust semantics — authoritative for the custom IRN transport, non-authoritative (always `false`) for vendor SDKs — with the topic-record bit never invalidated on an account-changing update.
- **Fix:** Added `WalletConnectorRuntimeFamily.restoredVerificationIsAuthoritative` (true only for `.customWalletConnectIRN`) and gated the fallback on it: for the IRN transport `ownershipProven = session.addressVerified` (the authoritative, update-maintained flag); for vendor-SDK families the connect-time topic bit is still merged (`session.addressVerified || savedTopic.verified`) so a previously-verified SDK wallet is not dropped on cold launch. `code:Sources/WalletConnectorKit/Domain/WalletConnection.swift:338-361` (new enum property), `code:Sources/WalletConnectorKit/Services/WalletConnectionLifecycleService.swift:164-181` (gated merge).
- **Sources used to verify:** `code:` as above; `code:Sources/WalletConnectorKit/Transport/WalletConnectIRNTransportClient.swift:823-864` (`handleUpdate` clears `addressVerified` on account change — confirms the IRN flag is authoritative); `build:` BuildProject → success, 11.5s, 0 errors (2026-08-07); `diag:` 0 issues on both edited files.
- **Could not fully resolve because:** n/a (fully fixed). A regression test asserting "IRN session restored as unverified after an account-swapping update despite a stale topic `verified` bit" is a recommended follow-up; the current environment's app-hosted test path is unreliable (see memory), so it is left for the AUD-022 pass.
- **Follow-up / owner:** Add the restore-after-update regression test during [[AUD-022]] device/host QA.
- **Signed:** Opus 4.8 (session P)

---

### AUD-041 — Strict report-only production-readiness re-audit: SDK-free core Verified-OK; EIP-1271 gap + two hardening follow-ups
- **Status:** 🔵 Verified-OK (SDK-free custom IRN core); 🟡 Partial (O-6 EIP-1271 + ERC-6492 implemented app-side, pending app-scheme build verification); ✅ Resolved (O-7 migration duplicate-handling — package build+suite green); O-8 (relay TLS pinning) — closed as won't-do per user direction (2026-08-07); ⛔ Blocked (AUD-022 device QA — standing blocker, deferred by user, NOT closed)
- **Type:** Audit (report-only, no fixes per user direction)
- **Severity:** No new Critical/High. O-6 Medium (functional). O-7 / O-8 Low.
- **Area:** Whole package + app-side crypto provider
- **Found by:** Opus 4.8 (session O) on 2026-08-07
- **Description:**
  - **Verdict (Verified-OK):** independent end-to-end re-read of the security-critical surface found no new critical or high-severity code defect. Concretely re-confirmed: (1) inbound authenticity never depends on topic secrecy — a leaked pairing/session topic cannot drive a forged settle/delete/request (type1 gated to a live pending proposal on a pairing topic; settle bound to a pending-proposal-derived session topic; delete guarded on a live session; response accepted only on the wire-id→topic-bound topic); (2) all keychain items are `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` + `kSecAttrSynchronizable = false` (device-local, no iCloud sync) and namespaced so the shared service never cross-reads foreign kinds; (3) `loadAll` fails closed on an unreadable keychain so a hidden session is never mistaken for "no sessions" and destructively cleaned up; (4) `nextID()` stays under 2^53 (JS-safe) with a monotonic clamp; (5) CSPRNG failures fail loud (symKey, nonce, relay subject) rather than emitting predictable material; (6) grant validation locates the EVM signer positionally (v1 vs v4) and scopes settled accounts to proposed chains.
  - **O-6 (Medium, app-side):** `Web3SwiftWalletConnectorCryptoProvider.supportsSmartContractOwnership == false` (EIP-1271 left as a documented TODO). The package fully supports the on-chain fallback (`WalletOwnershipVerifier.verifyPersonalSign(...,chain:)` + `isValidERC1271Signature`), but because the injected provider does not implement it, **under the default `.requireVerified` policy a smart-contract wallet (Safe / Coinbase Smart Wallet / most ERC-4337 accounts) fails ownership verification and cannot be connected.** For an app that lists Coinbase as a first-class wallet this is a real functional gap, not merely theoretical.
  - **O-7 (Low):** `KeychainAccessGroupMigration.migrate` counts `errSecAdd → errSecDuplicateItem` on the target-group copy as a successful move and then deletes the source item. If a prior partial/interrupted migration had already left a *divergent* copy in the target group, the newer source bytes are discarded rather than overwriting the stale target copy. Only reachable across repeated partial migrations of the same account; copy-before-delete otherwise preserves data.
  - **O-8 (Low, won't-do):** the relay WebSocket uses the default `URLSession` trust evaluation with no certificate/public-key pinning. Payloads are E2E-encrypted (ChaCha20-Poly1305) so a MITM cannot read/forge session traffic; pinning would only harden metadata/availability. **Per user direction (2026-08-07) this is closed as won't-do — not pursued until an explicit need arises; no further tracking.**
- **Root cause:** O-6 — provider composition intentionally shipped EOA-only first; O-7 — duplicate-item shortcut in an idempotent migrator; O-8 — pinning is a host-policy decision left out of the SDK.
- **Fix:** **O-6 implemented** per user direction (session O continuation): `Web3SwiftWalletConnectorCryptoProvider` now takes a per-chain `rpcEndpoints` map (public-node defaults for eth/base/polygon/optimism/arbitrum/avalanche/bnb), reports `supportsSmartContractOwnership == !rpcEndpoints.isEmpty`, and implements `isValidERC1271Signature` via a Foundation `URLSession` JSON-RPC `eth_call` to `isValidSignature(bytes32,bytes)` — `_hash` = the package's `WalletOwnershipVerifier.personalSignDigest(message:)`, accepting the `0x1626ba7e` magic return; an on-chain revert / non-magic value returns `false` (fail-closed), a missing endpoint or transport failure throws (fail-loud). Depends only on APIs already in use (`web3` keccak, package public `personalSignDigest`, Foundation) — **no new SPM dependency**. **O-6 completed** for in-scope smart-contract wallets (session O continuation 2): added **ERC-6492** handling — a signature carrying the `0x6492…6492` magic suffix is decoded (`abi.encode(factory, factoryData, innerSignature)`) to its inner ERC-1271 signature before the `isValidSignature` call, so a **deployed** Coinbase Smart Wallet / Safe that wraps its output still validates; a malformed wrapper fails closed. Coinbase Smart Wallet's replay-safe hash wrapping is applied *inside* its `isValidSignature`, so the plain EIP-191 digest is the correct input. Documented limit: a **counterfactual (not-yet-deployed)** account has no on-chain code to call and fails closed — connecting requires the wallet to already be deployed (the normal case). **Not compile-verified here:** the provider file lives in the Auralis app target, outside the `WalletConnectorKit-Package` workspace (only scheme available); build via the Auralis app scheme to compile-verify. **O-7 resolved** (package-side): `KeychainAccessGroupMigration.migrate` now, on `errSecDuplicateItem` from the target-group copy, `SecItemUpdate`s the existing target item to the source's current value/label/description before deleting the source, so a stale divergent copy from an interrupted earlier migration is reconciled rather than letting the newer bytes be discarded. Package `BuildProject` → success 6.4s, 0 errors; full suite **203 / 197 passed / 6 skipped / 0 failed**, no regression. NOTE: the keychain-migration integration tests are environment-gated (skipped on host), so the new reconcile branch is verified by inspection + no-regression, not a host-run assertion. **O-8** closed as won't-do per user direction — TLS pinning not pursued until an explicit need arises.
- **Sources used to verify:** `code:Sources/WalletConnectorKit/Transport/WalletConnectIRNTransportClient.swift` (inbound gating `:662-734`, settle binding `:991-1093`, delete guard `:775-803`, `nextID` `:1200-1222`); `code:Sources/WalletConnectorKit/Crypto/WalletConnectV2Crypto.swift`; `code:Sources/WalletConnectorKit/Crypto/WalletConnectRelayAuth.swift`; `code:Sources/WalletConnectorKit/Persistence/KeychainSessionTopicStore.swift` + `WalletConnectSessionStateStore.swift` + `KeychainAccessGroupMigration.swift`; `code:Sources/WalletConnectorKit/Requests/WalletSessionGrantValidator.swift` + `WalletRequest.swift` + `WalletPendingRequestStore.swift`; `code:Auralis/Auralis/Aura/WalletConnection/Web3SwiftWalletConnectorCryptoProvider.swift:30` (`supportsSmartContractOwnership` not overridden); `build:` BuildProject(buildForTesting:) → success, 3.3s, 0 errors (2026-08-07).
- **Could not fully resolve because:** the O-6 provider lives in the Auralis app target (outside the `WalletConnectorKit-Package` workspace), so it is verified by inspection here and must be compiled via the Auralis app scheme; and the live vendor/transport behavior (AUD-022) still requires a real wallet on a device — that remains the standing ship-gate blocker, deferred by the user to a later day (not closed this session).

### AUD-040 — Privy & Dynamic embedded-wallet clients pin the granted session to one EVM chain (multi-chain signing silently rejected) and ignore `sessionId`
- **Status:** ✅ Resolved (DEF-1 multi-chain embedded session); ✅ Resolved (DEF-2 sessionId honoring + scoped logout); 🔵 Verified-OK (DeepLinkWalletLauncher, Solana adapter); 🔴 Open / hygiene (DEF-3 dead `WalletSessionStore` — documented, not fixed)
- **Type:** Defect (DEF-1 functional / grant-vs-capability contradiction; DEF-2 ignored parameter → mis-routing + over-broad teardown)
- **Severity:** Medium (DEF-1 — multi-chain signing fails closed on every non-configured EVM chain) / Low (DEF-2 — single-embedded-wallet model made the mis-route low-impact, but `sessionId` was silently ignored)
- **Area:** Adapters (`LivePrivySDKClient`, `LiveDynamicSDKClient`)
- **Found by / fixed by:** Opus 4.8 (session N, embedded-adapter audit + fix) on 2026-08-07
- **Description:**
  - **DEF-1 (Medium):** both live clients built the settled session's namespace from a single `chain` (default `.ethereum`/`eip155:1`), advertising exactly one account `eip155:1:<addr>`. Every `request` then runs `WalletSessionGrantValidator.validate(request, in: session)` against that one-chain grant, so a request on any other EVM chain (e.g. Base `eip155:8453`) is rejected with `unsupportedChain` **before** it reaches the SDK — even though an embedded wallet is a single EOA valid on every EVM chain. The **Dynamic** client was internally self-contradictory: it computed `chainId: Int(request.chain.reference)` for `sdk.evm.request(...)` (intending per-request chain routing) while the grant guard two lines above made any non-configured chain unreachable. Net effect: a Privy/Dynamic connector could only ever sign on its one configured chain; chain switching looked like "unsupported chain."
  - **DEF-2 (Low):** `request(_:in sessionId:)` and `connect` ignored `sessionId` entirely and always operated on `embeddedEthereumWallets.first` (Privy) / `wallets.primary ?? first EVM` (Dynamic); a request routed at a specific session id was silently served by that "first" wallet. `disconnect(sessionId:)` called `logout()` unconditionally, tearing down the **entire authenticated user** regardless of the id passed.
- **Root cause:** DEF-1 — the session factory represented an inherently multi-chain EOA as a single-chain grant. DEF-2 — the embedded "one user = one wallet" model was assumed but never encoded, so `sessionId` was dropped rather than validated.
- **Fix:**
  - DEF-1: `session(address:chain:)` in both clients now advertises the account across all `WalletChain.evmChains` (configured `chain` first so `accounts.first` stays the primary network), so grant validation admits any EVM chain the key controls. This mirrors how the custom IRN transport already represents a multi-chain EVM address (same key across `eip155:1/137/8453/…`), and the lifecycle's `signingKeyIdentity` still folds them to one signature prompt.
  - DEF-2: both clients derive a stable session id via `topic(forAddress:)` (`privy-`/`dynamic-` + lowercased address). `request` now fails closed (`sessionExpired`) when `sessionId` does not name the live wallet's derived session instead of silently signing with the first wallet; `disconnect` only calls `logout()` when the id matches the live wallet (otherwise a no-op), with the single-session/whole-user-logout contract documented in-code.
- **Sources used to verify:** `code:Sources/WalletConnectorKitPrivyAdapter/LivePrivySDKClient.swift` (`session`, `topic(forAddress:)`, `request`, `disconnect`); `code:Sources/WalletConnectorKitDynamicAdapter/LiveDynamicSDKClient.swift` (same); `code:Sources/WalletConnectorKit/Requests/WalletSessionGrantValidator.swift` (chain-match rejection that DEF-1 tripped); `code:Sources/WalletConnectorKit/Domain/WalletProvider.swift:116` (`WalletChain.evmChains`); `build:` SRC-52 (BuildProject → success, iOS-sim destination so both `#if canImport` clients compile with the changes); `test:` SRC-53 (`RunAllTests` → 203 / 197 passed / 6 skipped / 0 failed, no regression).
- **Could not fully resolve because:** the live Privy/Dynamic clients have **no host-runnable behavioral tests** (they require the vendor SDK types and an authenticated user), so the multi-chain-grant and sessionId-honoring behavior is verified by compile + code inspection here and must be exercised end-to-end in the AUD-022 device pass. Fix is complete at the code level.
- **Follow-up / owner:** **DEF-3 (Low, hygiene, NOT fixed):** `WalletSessionStore` / `WalletSessionRecord` / `InMemoryWalletSessionStore` are public but used only by one test — a dead, in-memory-only parallel to `WalletConnectSessionStatePersisting` that a future integrator could wire by mistake (and lose "persistence" silently). Recommend deleting or marking deprecated/non-persistent; left in place this pass to avoid a public-API removal without sign-off. AUD-022 device QA remains the single ship gate; O-3 (relay TLS pinning), O-4 (capabilities→registry), O-5 (secret zeroization) still open.
- **Signed:** Opus 4.8 (session N)

---

### AUD-039 — Vendor-adapter tier audit: live SDK clients have no host test coverage (blocker context); Coinbase dead switch-chain mapping reconciled; `verifyOwnership(chain:)` default reviewed and kept
- **Status:** ✅ Resolved (A-2 Coinbase dead-arm reconcile); 🔵 Verified-OK (A-1 `.ethereum` default — intentional, kept); 🔵 Verified-OK (adapter readiness gating); 🔴 Open / device-QA (BLK live-tier coverage, A-3, A-4 — documented, not code-fixable here)
- **Type:** Defect (A-2, dead/inconsistent code) / Design review (A-1) / Coverage blocker (BLK) / Product note (A-3, A-4)
- **Severity:** Low (A-2) / Low (A-1, no in-package trigger) / **Blocker** (BLK — the live adapter tier is unproven, the concrete form of AUD-022)
- **Area:** Adapters (Coinbase/Reown/Privy/Dynamic connectors + live SDK clients), registry, account/namespace/JSON-RPC types
- **Found by / fixed by:** Opus 4.8 (session M, adapter-surface audit + fix) on 2026-08-07
- **Description:**
  - **BLK (Blocker, coverage):** every live client — `ReownAppKitLiveClient`, `LiveCoinbaseWalletSDKClient`, `LivePrivySDKClient`, `LiveDynamicSDKClient` — is wrapped in `#if os(iOS)` and linked against a vendor SDK. The host test plan validates the SDK-free core + mocks; the live clients' request-correlation, deep-link callback routing, namespace mapping, and SDK-id↔response binding have **no automated coverage** and have never run against a real wallet. This is the concrete mechanism behind the standing AUD-022 device-QA gate, and AUD-036 (the JS 2^53 id bug, invisible to `swift test`) is the precedent proving interop defects live exactly here. NOTE: this session's builds/tests ran on the **iPhone Air (iOS 27) Simulator** destination, so the live clients *do* compile-check (SRC-50), but compiling is not exercising — a real wallet is still required.
  - **A-2 (Low, defect — resolved):** `LiveCoinbaseWalletSDKClient.session(from:)` omits `wallet_switchEthereumChain` from the granted namespace methods (so `WalletSessionGrantValidator` rejects that method before it can reach the SDK), yet `web3RPC(for:)` still carried a `.wallet_switchEthereumChain(chainId:)` mapping arm that could never run. Dead, self-contradicting code.
  - **A-1 (Low, reviewed — kept):** `verifyOwnership(of:chain:in:statement:expiryDate:)` defaults `chain` to `.ethereum` across all connectors (and the protocol extension). Against an account settled only on a non-mainnet EVM chain, a caller relying on the default would have the challenge rejected by grant validation as `unsupportedChain`, which reads like "wallet on wrong network." Reviewed and **intentionally kept**: (1) the default backs the deliberately-documented ergonomic `verifyOwnership(of:in:)` API used across the test suite (`WalletReviewFixesTests`, `WalletConnectSignEngineTests`), so removing it is a source-breaking change; (2) every *critical* in-package caller — `WalletConnectionLifecycleService.verifyOwnershipIfNeeded` — already passes `address.chain` explicitly, so there is no in-package trigger. Downgraded to a documented convenience foot-gun.
  - **A-3 (Low, product note):** `LiveCoinbaseWalletSDKClient` stamps a synthetic 30-day expiry (`defaultSessionValidity`) because Coinbase MWP has no session-lifetime concept; a wallet reset/revoked out-of-band still reads as live locally for up to that window. Correct given the protocol; product should confirm the staleness window (shortening `sessionValidity` forces an earlier re-handshake).
  - **A-4 (Informational):** Coinbase `disconnect` calls MWP `resetSession()`, which is single-session and clears the entire SDK connection regardless of `sessionId` — already documented in-code; noted for hosts running Coinbase alongside other connectors.
- **Root cause:** A-2 — an overcautious method exclusion in `session(from:)` was never reconciled with the request mapper, leaving an unreachable arm. BLK — the live tier is vendor-SDK/`#if os(iOS)` code with no mockable seam exercised by the host plan (by design; it needs a device/wallet).
- **Fix:**
  - A-2: `web3RPC(for:)`'s `.walletSwitchEthereumChain` case now throws `WalletConnectionError.unsupportedMethod` (matching the excluded grant), with a comment explaining that enabling switch-chain requires granting the method in `session(from:)` **and** restoring the mapping. Behavior-preserving: the arm was already unreachable, so no runtime behavior changes; it removes dead/contradictory code and keeps the two sites in agreement.
  - A-1: no code change (see Description); kept as a documented note.
  - BLK/A-3/A-4: documented, not code-fixable in this package — carried to the AUD-022 device pass / product review.
- **Sources used to verify:** `code:Sources/WalletConnectorKitCoinbaseAdapter/LiveCoinbaseWalletSDKClient.swift` (`web3RPC(for:)` switch-chain arm; `session(from:)` method filter); `code:Sources/WalletConnectorKit/Domain/WalletConnection.swift:384/425` (protocol requirement + defaulted ergonomic extension); `code:Sources/WalletConnectorKit/Services/WalletConnectionLifecycleService.swift:229` (lifecycle passes `address.chain` explicitly); `build:` SRC-50 (BuildProject → success, 6.1s, 0 errors; iOS-simulator destination so the live client compiles); `test:` SRC-51 (`RunAllTests` → 203 / 197 passed / 6 skipped / 0 failed; identical to SRC-49, confirming A-2 is behavior-preserving).
- **Could not fully resolve because:** BLK is inherent — the live adapter tier cannot be validated without a real wallet on device (AUD-022). A-1 is a deliberate API-ergonomics trade-off, not a defect.
- **Follow-up / owner:** AUD-022 device QA remains the single ship gate and now explicitly covers driving each live client (Reown/Coinbase/Privy/Dynamic) through connect→request→verify→disconnect→restore against a real wallet. O-3 (relay TLS pinning), O-4 (capabilities→registry), O-5 (secret zeroization) from AUD-038 remain open. A-3 is a product decision on session staleness.
- **Signed:** Opus 4.8 (session M)

---

### AUD-038 — `wc_sessionDelete` processed with no live-session guard; pairing topic left subscribed/decryptable for the client's lifetime after settle
- **Status:** ✅ Resolved (F-1 delete-path live-session guard); ✅ Resolved (F-2 post-settle pairing-topic teardown)
- **Type:** Defect (missing defensive guard / lingering decryptable surface)
- **Severity:** Medium (a party holding the pairing bearer secret could drive a spurious teardown + `.sessionDeleted`; narrow exploitability, but a real inconsistency in an otherwise uniformly-guarded switch)
- **Area:** Transport (IRN inbound peer-request pipeline: `handlePeerRequest` delete case + `handleSettle`)
- **Found by / fixed by:** Opus 4.8 (session L, strict re-audit + fix) on 2026-08-06
- **Description:**
  - **F-1 (Transport, Medium):** `WalletConnectIRNTransportClient.handlePeerRequest` gates `settle`, `update`, `extend`, and `event` on `sessionsByTopic[topic] != nil`, but the `delete` case had **no** such guard. Any inbound `wc_sessionDelete` that merely *decrypts* on a topic with a known symKey ran the full teardown — `cleanupTopicState`, `unsubscribe`, `failPendingRequests`, and a `.sessionDeleted(WalletSessionID(rawValue: topic))` emission — regardless of whether a live session existed on that topic. Delete was the sole unguarded peer-request path.
  - **F-2 (Transport, Medium):** `handleSettle` removed the proposal/connecting mappings on a successful settle but never tore down the **pairing** topic. Because this transport mints a fresh pairing per `createPairing` and never reuses one, the pairing topic's symKey — a **bearer secret** exchanged out-of-band via the pairing URI (QR/deeplink) — stayed subscribed and decryptable for the whole client lifetime. Combined with F-1, a party who saw the pairing URI could inject a `wc_sessionDelete` on the lingering pairing topic and drive a spurious `.sessionDeleted` (carrying a non-session id) and pairing-key teardown — including mid-handshake, before settle. Payload authenticity was never at risk (E2E crypto holds), but the transport should not present a post-settle attack surface keyed on a short-lived bearer secret, nor emit teardown events for a non-session topic.
- **Root cause:** F-1 — the delete case was written to be maximally forgiving (ack + clean up even when local state looks torn down) and, in doing so, omitted the live-session precondition every sibling case enforces. F-2 — pairing lifecycle was never explicitly closed after settle because the session path keys everything under the derived session topic; the pairing entry was simply orphaned rather than removed.
- **Fix:**
  - F-1: `handlePeerRequest`'s `delete` case now `guard sessionsByTopic[topic] != nil` — when there is no live session it sends the idempotent `sessionDeleteResponse` ack (so a genuine peer stops retrying) and returns without any state change or event. The live-session teardown path is unchanged.
  - F-2: on a successful settle, `handleSettle` now tears down the pairing topic (`cleanupTopicState(pairingTopic)` + a detached `relayClient.unsubscribe`) once `contextByTopic[topic]?.pairingTopic` differs from the session topic, so post-settle traffic must ride the session key and the pairing symKey is no longer a live decryptable surface. `cleanupTopicState` touches only the pairing topic; the session's own keys live under the session topic and are untouched.
- **Sources used to verify:** `code:Sources/WalletConnectorKit/Transport/WalletConnectIRNTransportClient.swift` (`handlePeerRequest` delete guard; `handleSettle` pairing teardown after `.sessionApproved`); `test:WalletConnectSignEngineTests.pairingTopicDeleteIsIgnored` (new regression — settles a session, injects a `wc_sessionDelete` on the pairing topic via the pairing bearer secret, asserts the session survives, `.sessionDeleted` count stays 0, and the session key still round-trips a `personal_sign`); `build:` SRC-48 (BuildProject buildForTesting → success, 7.9s, 0 errors); `test:` SRC-49 (`RunAllTests` → 203 total / 197 passed / 6 skipped / 0 failed; +1 vs SRC-47).
- **Could not fully resolve because:** Fully closed at the code level. The one residual guarantee — that no legitimate flow depends on the pairing topic surviving settle — holds because this transport never reuses a pairing (a fresh symKey + `wc_sessionPropose` per `createPairing`); a future change that reuses pairings would need to revisit F-2.
- **Follow-up / owner:** None required for F-1/F-2. **Deferred (not fixed this pass), recorded as open follow-ups:**
  - **O-3 (Low/Medium) — relay TLS certificate/SPKI pinning.** `URLSessionWalletConnectRelayTaskFactory` uses `URLSession.shared` with default trust. Payloads are E2E encrypted, but a trusted-cert MITM sees topic ids, timing, and the relay `client_id`/`sub` correlation and can selectively drop settle/response traffic. The fix is host-side (inject a pinned `URLSession` via the existing `taskFactory` seam — no core change). **Intentionally not "fixed" here:** hardcoding an SPKI pin for `relay.walletconnect.org` without the operator's real, rotation-planned pin set would be worse than nothing (false assurance, or a hard connectivity outage on rotation). Owner: app composition, to pin with a maintained backup-pin policy.
  - **O-4 (Low) — `WalletConnectorCapabilities` advertised but not wired into the registry.** Either consume it or keep it clearly marked forthcoming so callers do not assume capability gating exists.
  - **O-5 (Low/Informational) — no zeroization of in-memory secrets.** Symmetric keys and X25519 private keys live as `Data`/CryptoKit objects for the client lifetime with no wipe on teardown. Standard for CryptoKit on iOS; note only if the threat model grows to include memory forensics.
  - **AUD-022 device QA remains the single standing ship gate.** This pass reconfirms the SDK-free core is fail-closed and adversarially tested; no new *critical* code defect was found. AUD-036 (JS 2^53 id ceiling) remains the standing evidence that live-wallet interop bugs are invisible to `swift test`, so the end-to-end device pass is a genuine blocker, not a formality.
  - **Log hygiene:** the Sources Registry has duplicate IDs (`SRC-23`, `SRC-24` each appear twice; `SRC-38` is defined after `SRC-39`). Left as-is to preserve existing citations (append-only doc), but future sessions should cite these ranges with care; new IDs continue from SRC-49.
- **Signed:** Opus 4.8 (session L)

---

### AUD-037 — Corrupt relay-identity keychain record never self-heals (permanent client_id instability); access-group migration body ran outside its lock (redundant concurrent migrations)
- **Status:** ✅ Resolved (F-1 relay-identity self-heal); ✅ Resolved (F-2 migration lock scope)
- **Type:** Defect (F-1, silent persistence degradation) / Concurrency-robustness (F-2)
- **Severity:** Medium (F-1 — silent, permanent loss of cross-launch `client_id` stability, fail-safe) / Low (F-2 — redundant work + a read-before-migration window; already idempotent so never corrupting)
- **Area:** Crypto (relay DID-JWT identity persistence) / Persistence (Keychain access-group migration)
- **Found by / fixed by:** Opus 4.8 (session K) on 2026-08-06
- **Description:**
  - **F-1 (Crypto, Medium):** `WalletConnectKeychainRelayAuthProvider.loadOrCreateKey()` treated **every** thrown load error identically — falling back to a process-lifetime ephemeral key **without overwriting** the stored record. But `loadKey()` throws `WalletSessionTopicStoreError.invalidTopicData` when a record *exists* yet its bytes do not decode to a valid `Curve25519.Signing.PrivateKey` (corrupt/truncated bytes, or a foreign item that landed on the `relay-auth-identity` account). Because the undecodable bytes are still present on every subsequent launch, the provider takes the same branch forever: the relay `client_id` is permanently unstable across launches with **no recovery path**, silently. It fails safe (relay auth still succeeds with the ephemeral key), which is exactly why it would go unnoticed. The single `catch` conflated a *corrupt* record (safe to purge and regenerate) with a *transient* failure such as a locked device or missing entitlement (must NOT overwrite — the record may simply be temporarily unreadable). Missed by prior audits because the existing tests only simulate a transient `keychainFailure(errSecMissingEntitlement)` and a valid stored key, never an existing-but-undecodable record.
  - **F-2 (Persistence, Low):** `KeychainAccessGroupMigration.migrateServiceIfNeeded` locked only around the `completed`-set check and insert, releasing the lock before running `migrate()`. All three stores (topic, session-state, relay-identity) call this for the **same** `(service, targetGroup)` on the first launch of a Keychain-Sharing build, so up to three threads could each observe `!completed` and run a full-service `SecItemCopyMatching` + copy concurrently — and a caller could proceed to read the service before a concurrent migration finished moving items into the shared group. The migration is copy-before-delete and idempotent (`SecItemAdd`→`errSecDuplicateItem` OK, `SecItemDelete`→`errSecItemNotFound` OK), so it was never *corrupting*, only redundant and racy.
- **Root cause:** F-1 — a single `catch` conflated a corrupt persisted record with a transient/unreadable one. F-2 — the lock guarded the completion flag but not the (idempotent) migration body it gates.
- **Fix:**
  - F-1: `loadOrCreateKey()` now catches `WalletSessionTopicStoreError.invalidTopicData` distinctly — it purges the bad record via a new `deleteKey()` → `WalletRelayIdentityKeychain.deleteIdentityData()` seam and falls through to mint + persist a fresh identity on this launch; every other (transient) error keeps the prior non-overwriting ephemeral fallback. Added `deleteIdentityData()` to the internal keychain protocol and implemented it on `SecItemRelayIdentityKeychain` as a `SecItemDelete` that tolerates `errSecItemNotFound`. The self-heal happens once: the freshly persisted key is a stable `client_id` on the next launch.
  - F-2: `migrateServiceIfNeeded` now holds `lock` across the whole `(service, targetGroup)` migration (`lock()` + `defer lock.unlock()`), so the first caller performs the one-shot move while the rest block briefly and then observe `completed`. `migrate()` never re-enters the method, so the non-recursive `NSLock` cannot deadlock. Comment updated to explain the widened scope.
- **Sources used to verify:** `code:Sources/WalletConnectorKit/Crypto/WalletConnectRelayAuth.swift:loadOrCreateKey/deleteKey/SecItemRelayIdentityKeychain.deleteIdentityData`; `code:Sources/WalletConnectorKit/Persistence/KeychainAccessGroupMigration.swift:migrateServiceIfNeeded`; `test:WalletReviewFixesTests.relayIdentityCorruptRecordSelfHeals` (new regression — asserts the corrupt record is purged once, a fresh identity persisted, and the `client_id` then stays stable) alongside the retained `relayIdentityLoadErrorFallsBackWithoutOverwrite` (transient error still never overwrites); `build:` SRC-45 (BuildProject buildForTesting → success, 11.5s, 0 errors); `test:` SRC-46 (`WalletReviewFixesTests` → 12 passed, 0 failed); `diag:` XcodeRefreshCodeIssuesInFile clean on all three edited files.
- **Could not fully resolve because:** Fully closed at the code level. F-1's transient-vs-corrupt distinction relies on the store surfacing `invalidTopicData` only for genuine decode failures (it does); a real device pass under AUD-022 will exercise the production `SecItem` path end-to-end.
- **Follow-up / owner:** None required. AUD-022 device QA remains the standing ship gate. Prior-pass enhancements (relay TLS pinning O-1, capabilities→registry wiring O-2, `wc_sessionExtend`-unsupported caching O-5) remain open opportunities, not defects.
- **Signed:** Opus 4.8 (session K)

---

### AUD-036 — Wallet-facing JSON-RPC ids exceeded JavaScript's 2^53 safe-integer ceiling (silently breaks signing against JS/RN wallets); relay `sub` churn + "canonical SIWE" wording tightened; app secp256k1 provider verified
- **Status:** ✅ Resolved (BLK-3 — the id ship blocker); ✅ Resolved (F-2 relay `sub` churn, F-3 SIWE docstring); 🔵 Verified-OK (app-side secp256k1 provider return shape — prior info gap #1)
- **Type:** Defect (BLK-3, ship blocker) / Faulty assumption (F-1/F-2/F-3) / Verification (info gap)
- **Severity:** **Critical** (BLK-3 — silent, total signing/session-settle failure against a large class of real wallets) / Low (F-2, F-3)
- **Area:** Transport (id minting) / Crypto (relay DID-JWT auth) / Transport (DApp connector docs) / app composition (crypto provider)
- **Found by / fixed by:** Opus 4.8 (session J) on 2026-08-06
- **Description:**
  - **BLK-3 (Transport, Critical):** `WalletConnectIRNTransportClient.nextID()` minted wallet-facing Sign RPC ids as `Int64(now*1000) * 1_000_000 + rand(0..<1_000_000)` ≈ **1.79e18** with a 2026 clock — roughly **198× above `Number.MAX_SAFE_INTEGER` (2^53 ≈ 9.007e15)**. These ids ride on `wc_sessionPropose` / `wc_sessionRequest` / `wc_sessionPing` / `wc_sessionExtend`, i.e. messages the **wallet** parses and echoes. Any JavaScript / React-Native wallet (a large fraction of the ecosystem, incl. MetaMask Mobile) stores JSON numbers as IEEE-754 doubles, so it rounds the id and echoes a **different** value; the transport's `handleRequestResponse` binds a response to its request via `requestTopicByWireID[id] == topic` (and `handleProposeResponse` / the ack path key on the exact id), so the rounded id never matches — the response is dropped and every signing request hangs to expiry. The in-code comment ("match WalletConnect's relay-id entropy guidance", **F-1**) was the faulty assumption: it cited the *relay* id tier for a *wallet-facing* id. The vendored reference proves the two-tier design is deliberate — reown uses `JSONRPC/RPCID` = `ms * 1_000 + rand(0..<1_000)` (≈1.8e15, under 2^53) for Sign/wallet traffic and `WalletConnectRelay/RPC/WalletConnectRPCID` = `ms * 1_000_000 + rand(0..<1_000_000)` for the Rust relay only. This codebase's **relay** client (`WalletConnectIRNRelayClient.nextRequestID`, `ms * 1_000_000`) was already correct (relay preserves full Int64); only the **transport** id was on the wrong tier. Invisible to every prior audit and to `swift test` because Swift `Int64` handles 1.8e18 and the in-process mock wallet preserves ids exactly — it only manifests against a real JS wallet, i.e. exactly the deferred AUD-022 device QA. This is the concrete evidence that AUD-022 is a true blocker, not a formality.
  - **F-2 (Crypto):** `WalletConnectRelayAuth` minted a fresh random `sub` per token; reown mints it once per client and reuses it as a stable correlation value. Harmless for plain socket authorization today, but a latent trap if Notify/Echo (which treat `sub` as a stable client id) are ever enabled.
  - **F-3 (Transport docs):** `WalletConnectDAppConnector.verifyOwnership` docstring called the ownership challenge "a canonical SIWE message". It is a SIWE-*shaped* `personal_sign` challenge (address not EIP-55 checksummed, ABNF not guaranteed) — correct because the app both mints and verifies it over the exact bytes, but the wording risked a future maintainer wiring it into a real SIWE-authenticating backend that would reject it.
  - **Info gap #1 (Verified-OK):** `Web3SwiftWalletConnectorCryptoProvider` (app side, `Auralis/Aura/WalletConnection/`) confirmed correct — it returns the 64-byte `X‖Y` key (drops the `0x04` SEC1 prefix), runs raw secp256k1 recovery over the 32-byte digest with no EIP-191 re-prefixing/re-hashing, and sets `supportsRecovery = true`, exactly what `WalletOwnershipVerifier.addressMatches` expects. EIP-1271 remains a documented `supportsSmartContractOwnership == false` TODO (deliberate fail-closed for contract wallets; not an EOA-shipping blocker).
- **Root cause:** BLK-3 — the transport copied the relay id tier (`* 1_000_000`) for wallet-facing ids instead of reown's Sign tier (`* 1_000`), breaching the JS double-precision integer ceiling.
- **Fix:**
  - BLK-3/F-1: `nextID()` now computes `Int64(now*1000) * 1_000 + rand(0..<1_000)` (mirroring reown `JSONRPC/RPCID`), keeping every id well under 2^53; the monotonic `max(candidate, lastIssuedID + 1)` clamp still guarantees strict uniqueness/ordering even at a fixed timestamp. The relay client's `* 1_000_000` is intentionally left unchanged (Rust relay, full Int64). Comment rewritten to explain the JS-double constraint and the two-tier distinction.
  - F-2: `WalletConnectKeychainRelayAuthProvider` mints `sub` once (lazily, under its lock) and reuses it; `WalletConnectEphemeralRelayAuthProvider` mints it once at init. `WalletConnectRelayAuth.createToken` already accepted a `subject:` seam; docstring updated.
  - F-3: docstring reworded to describe a SIWE-shaped `personal_sign` ownership challenge and why full EIP-4361 conformance is intentionally not required here.
- **Sources used to verify:** `code:Sources/WalletConnectorKit/Transport/WalletConnectIRNTransportClient.swift:nextID`; `spec:` reown-swift `Sources/JSONRPC/RPCID.swift:12-13` (Sign tier, `ms*1000+rand(0..1000)`) vs `Sources/WalletConnectRelay/RPC/WalletConnectRPCID.swift:6-7` (relay tier, `ms*1000000+rand(0..1000000)`); `web:` ECMA-262 `Number.MAX_SAFE_INTEGER` = 2^53−1; `code:Sources/WalletConnectorKit/Crypto/WalletConnectRelayAuth.swift` (stable `sub`); `code:Sources/WalletConnectorKit/Transport/WalletConnectDAppConnector.swift` (docstring); `code:Auralis/Aura/WalletConnection/Web3SwiftWalletConnectorCryptoProvider.swift` (info gap #1, 64-byte X‖Y return); `test:WalletTransportHardeningTests.nextIDStaysUnderJavaScriptSafeInteger` (new regression) + `.nextIDsAreDistinctWithinSameMillisecond` + `.relayRequestIDsUseWalletConnectShape`; `build:` SRC-43 (BuildProject buildForTesting → success, 11.4s, 0 errors); `test:` SRC-44 (`swift test` full package: **177/177 passed, 0 failed**).
- **Could not fully resolve because:** Live confirmation that a specific JS wallet now correlates responses is part of the deferred AUD-022 device QA (the fix makes the ids spec-compliant with reown's Sign tier, which the whole ecosystem interoperates with). EIP-1271 contract-wallet ownership is still out of scope (app-side TODO).
- **Follow-up / owner:** (1) AUD-022 device QA against at least one JS/RN wallet (e.g. MetaMask Mobile) is now the single remaining ship gate and will directly exercise the BLK-3 fix. (2) Enhancements from this pass left open (not defects): relay TLS pinning (O-1), wiring `WalletConnectorCapabilities` into registry filtering (O-2), caching "peer does not support wc_sessionExtend" to avoid repeated keepalive timeouts (O-5).
- **Signed:** Opus 4.8 (session J)

---

### AUD-035 — Cross-launch restore silently clobbered the active-wallet selection; relay reconnect could be wedged by one oversized-mailbox topic; AUD-034 gap #3 + C-1 confirmed closed in-app
- **Status:** ✅ Resolved (BLK-2 active-wallet restore, relay resubscribe isolation); 🔵 Verified-OK (AUD-034 gap #3 + C-1 now closed in app composition; "type0 propose-response" reconsidered and dismissed)
- **Type:** Defect (BLK-2) / Robustness (relay) / Verification (gap-closure + dismissal)
- **Severity:** Medium (BLK-2 — user-visible multi-wallet correctness, not security) / Low (relay)
- **Area:** Services (BLK-2) / Transport (relay) / Crypto+Persistence (app-side closure)
- **Found by / fixed by:** Opus 4.8 (session I) on 2026-08-06
- **Description:**
  - **BLK-2 (Services):** `WalletConnectionLifecycleService.restoreSavedSessions()` unconditionally set the active wallet to `restored.last?.account.address` and only cleared when `restored.isEmpty`. `restored` is ordered by the topic store's account-key sort (`session-topic:<caip2>:<address>`), **not** by selection recency, so for any user with ≥2 connected wallets the active wallet silently switched to an arbitrary, address-lexicographic pick on **every** cold launch — ignoring the `UserDefaultsActiveWalletStore`-persisted selection entirely. The design elsewhere clearly treats active-wallet identity as meaningful (`remove()` falls back via `mostRecentlyUsedActiveAddress`), so this was a genuine regression. Secondary: restore re-stamps every restored address with `selectedAt: now()`, flattening MRU order (accepted — the primary fix preserves the true active wallet so the MRU fallback is rarely reached; recording per-address recency would need a topic-record schema change and is deferred). Missed by all prior audits because the lifecycle tests use `InMemoryActiveWalletStore` with single-wallet fixtures.
  - **Relay robustness (Transport):** `WalletConnectIRNRelayClient.resubscribeAll()` did `try await recoverTopic(topic)` per topic and was awaited with `try` in `performConnect`, so a single topic whose queued mailbox exceeds the 20-page `recoverTopic` cap would throw out of the whole reconnect and strand **every other** subscription until the next outbound call.
  - **AUD-034 gap #3 + C-1 (closure, Verified-OK):** re-reading the live app composition (SRC-42) shows both prior open gates are now closed in-app — a real secp256k1 `Web3SwiftWalletConnectorCryptoProvider` is injected (readiness `.productionReady`, EVM ownership verifies instead of failing closed), and a runtime-resolved shared Keychain access group is threaded into all three stores with a `KeychainAccessGroupMigration`. The package README already separates App Groups from Keychain access groups.
  - **"type0 propose-response" (dismissed):** the session-H-era note that the transport accepts a `wc_sessionPropose` response over a type0 envelope is **not** a defect. The type1 sender↔responder key binding it "lacks" only matters against a party who does **not** hold the pairing symmetric key — but that key is the URI's bearer secret, and anyone who has it can equally forge a valid type1 envelope. The type0 path is also required for legitimate JSON-RPC **rejections** (sent on the pairing topic as type0). No change made.
- **Root cause:** BLK-2 — restore used positional "last" instead of the persisted selection. Relay — a best-effort reconnect step was treated as mandatory to the whole connect.
- **Fix:**
  - BLK-2: `restoreSavedSessions` now keeps the persisted active wallet when it is still among `restored` (case-insensitive for eip155 via the existing `matchesStoredAddress`), falls back to the most-recent restored address only when the prior active is gone, and clears when nothing restored.
  - Relay: `resubscribeAll()` is now non-throwing and wraps each `recoverTopic` in `try?`, so a failing topic is left in `subscribedTopics` for a later retry / on-demand recovery while every other topic re-subscribes. `performConnect` calls it with `await` (initial connect is unaffected — `subscribedTopics` is empty then).
- **Sources used to verify:** `code:Sources/WalletConnectorKit/Services/WalletConnectionLifecycleService.swift` (active-wallet preservation); `code:Sources/WalletConnectorKit/Transport/WalletConnectIRNRelayClient.swift` (`resubscribeAll` isolation); `test:WalletConnectionCoreTests.lifecycleRestorePreservesActiveWallet` + `.lifecycleRestoreFallsBackWhenActiveGone`; `build:` SRC-40; `test:` SRC-41 (200/194/6-skip/0-fail); `code:` SRC-42 (app-side gap #3 + C-1 closure).
- **Could not fully resolve because:** The MRU-flattening-on-restore is accepted rather than fixed (needs a topic-record schema change to carry per-address recency). All on-device behavior (live relay, real keychain, EIP-1271 contract wallets) remains part of the deferred AUD-022 device QA; EIP-1271 is still `supportsSmartContractOwnership == false` in the app provider (documented TODO), so Safe/Coinbase-Smart-Wallet/ERC-4337 accounts still fail closed under `.requireVerified`.
- **Follow-up / owner:** (1) AUD-022 device QA remains the hard ship gate for the live relay + real-keychain + live-vendor paths. (2) If smart-contract wallets are in scope, implement `isValidERC1271Signature` + set `supportsSmartContractOwnership = true` in `Web3SwiftWalletConnectorCryptoProvider` (on-chain `eth_call` to `isValidSignature(bytes32,bytes)` → `0x1626ba7e`). (3) Optionally persist per-address selection recency so restore preserves MRU exactly. (4) Log hygiene: `SRC-23`/`SRC-24` remain defined twice (pre-existing) — not renumbered retroactively.
- **Signed:** Opus 4.8 (session I)

---

### AUD-034 — Keychain stores set no access group (extension-sharing contract silently broken); typed-data v1 signer mis-indexed; restore aborts on one bad record
- **Status:** ✅ Resolved (C-1, F-1, F-4); 🔵 Verified-OK (gap #2); ✅ Resolved (gap #3 — closed in-app by AUD-035/SRC-42: `Web3SwiftWalletConnectorCryptoProvider` now injected + shared access group threaded through all three stores)
- **Type:** Defect (C-1, F-1) / Robustness (F-4) / Gap (gap #3)
- **Severity:** High (C-1, if extension sharing is a real requirement) / Low (F-1, F-4)
- **Area:** Persistence (C-1) / Requests (F-1) / Services (F-4) / Crypto+Adapter (gap #3)
- **Found by / fixed by:** Opus 4.8 (session H) on 2026-08-06
- **Description:**
  - **C-1 (Persistence):** All three keychain backings — `KeychainWalletConnectSessionStateStore` (`WalletConnectSessionStateStore.swift` `baseQuery()`), `KeychainSessionTopicQueryFactory`/`KeychainWalletSessionTopicStore` (`KeychainSessionTopicStore.swift` `baseQuery()`), and `SecItemRelayIdentityKeychain` (`WalletConnectRelayAuth.swift` `baseQuery()`) — wrote `kSecClassGenericPassword` items with **no** `kSecAttrAccessGroup` (grep-confirmed: the attribute appears nowhere in the package or in `Auralis/Aura/WalletConnection`). Two consequences: (1) `README.md:131-133` tells hosts to "add the same [App] group to every app extension that must share Reown/session data" — but an App Group container does **not** share keychain items; without an explicit access group + Keychain Sharing entitlement an extension sees an **empty** store and cannot restore a custom-IRN session (key material lives in `session-record:<topic>`); (2) the AUD-028 rationale (per-item store to avoid an "app+extension cross-process clobber") describes a race that **cannot occur as configured**, since the extension cannot see the items to clobber. Either the sharing requirement is real (this was a silent functional bug) or it is not (AUD-028's premise + the README section are misleading). Flagged softly in AUD-033 opportunity #6; elevated here.
  - **F-1 (Requests):** `WalletSessionGrantValidator.signerAddress(in:)` returned `request.params.first?.stringValue` for **both** `.ethSignTypedData` and `.ethSignTypedDataV4`. Correct for `eth_signTypedData_v4` (`[address, typedData]`) but wrong for legacy `eth_signTypedData` (v1, `[typedData, address]` — signer at index 1): a v1 request read the typed-data blob as the "signer," failed the account-membership check, and threw `.invalidAccount`.
  - **F-4 (Services):** `WalletConnectionLifecycleService.restoreSavedSessions()` ran `topicStore.delete` / `accountStore.deactivate` / `accountStore.upsert` with bare `try` inside the per-topic loop, so one transient store error on record *N* threw out of the whole function — records *N+1…* never restored and the active wallet was never set (user appears logged out from one flaky item).
  - **Gap #2 (Verified-OK):** relay `aud` = `WalletConnectRelayConfiguration.relayURL.absoluteString` = `wss://relay.walletconnect.org`, consistent with the reown reference pattern (aud = relay URL string). No mismatch by inspection; still device-unproven under AUD-022.
  - **Gap #3 (Open):** the app wires `WalletConnectDAppConnector` at `AuralisWalletConnectionFeature.swift:166` and `:173` with **no** `cryptoProvider:`, and no web3.swift→`WalletConnectorCryptoProvider` adapter exists anywhere outside the package. So `cryptoProvider == nil`, readiness is `.experimental`, and **all** EVM ownership verification (EOA *and* EIP-1271) fails closed today. The EVM identity flow is non-functional in the app until that adapter is written.
- **Root cause:** C-1 — access group was never parameterized, and App-Group vs. keychain-sharing-group were conflated. F-1 — one index assumed one param ordering. F-4 — best-effort per-record cleanup was treated as mandatory to the whole restore. Gap #3 — the recovery-provider seam exists but was never populated in app composition.
- **Fix:**
  - C-1: added an opt-in `accessGroup: String? = nil` to `KeychainWalletConnectSessionStateStore.init`, `KeychainWalletSessionTopicStore.init`, and `WalletConnectKeychainRelayAuthProvider.init`, threaded into each `baseQuery()` (`query[kSecAttrAccessGroup] = accessGroup` only when non-nil). `nil` default preserves the secure private-group behavior; a host that genuinely needs extension sharing passes the same group to all three (plus the Keychain Sharing entitlement). This makes the capability *possible and explicit* without the package hard-coding a group it cannot know.
  - F-1: `signerAddress` now scans the typed-data params for the first EVM-address-shaped string (`0x` + 40 hex via new `isEVMAddress`), so the signer is found for both v1 and v4 orderings; the typed-data payload (object or JSON string) never matches.
  - F-4: wrapped the per-record loop body in `do/catch { onDiagnostic; continue }` and added an optional `onDiagnostic:` sink to `WalletConnectionLifecycleService.init` (defaulted `nil`, non-breaking). The top-level `topicStore.loadAll()` still fails closed (an unreadable index does not wipe); only per-record failures are logged-and-skipped.
- **Sources used to verify:** `code:Sources/WalletConnectorKit/Persistence/WalletConnectSessionStateStore.swift`, `.../KeychainSessionTopicStore.swift`, `.../Crypto/WalletConnectRelayAuth.swift` (access-group threading); `code:Sources/WalletConnectorKit/Requests/WalletSessionGrantValidator.swift` (`isEVMAddress` + signer scan); `code:Sources/WalletConnectorKit/Services/WalletConnectionLifecycleService.swift` (per-record isolation + `onDiagnostic`); SRC-38 (app composition + relay `aud`); `build:` SRC-37 (green). Full test plan **not** re-run this pass (last green: SRC-35).
- **Could not fully resolve because:** C-1 needs a product decision (is extension sharing real?) before an access group is actually wired in app composition; the fix makes it possible but does not set a group. Gap #3 requires writing the web3.swift adapter (outside this package). The on-device behavior of all of the above remains part of the deferred AUD-022 QA.
- **Update (2026-08-06, session H):** User confirmed **extension keychain sharing is required**. App-side wiring landed: `AuralisWalletConnectionFeature` now resolves a shared Keychain access group at runtime (`WalletConnectKeychainAccessGroup` — team/app-identifier prefix probed via a throwaway keychain item + fixed base name `com.auraplay.walletconnect.shared`, so no team id is hard-coded) and passes it to all three stores (`KeychainWalletSessionTopicStore(accessGroup:)`, `KeychainWalletConnectSessionStateStore(accessGroup:)`, and the relay client's `authProvider: WalletConnectKeychainRelayAuthProvider(accessGroup:)`); a nil probe falls back to the private group. README's App-Group section corrected to distinguish App Group (files/defaults) from Keychain Sharing (items) with the exact capability steps. **Still manual (host, cannot be done from the package workspace):** enable **Signing & Capabilities → Keychain Sharing** on the app target *and* the consuming extension target with the matching group `$(AppIdentifierPrefix)com.auraplay.walletconnect.shared` — until that entitlement ships, the shared-group store ops fail closed. The package build is green (SRC-37); the app target is not in this package workspace, so its compile + the entitlement behavior are covered by AUD-022 device QA.
- **Update (2026-08-06, session H, follow-on):** Landed the remaining pieces. **Migration:** added `KeychainAccessGroupMigration` (`Persistence/KeychainAccessGroupMigration.swift`) — a one-shot, copy-before-delete, idempotent consolidation that moves every WalletConnect item for the service out of the private default group into the shared access group (kind-agnostic; preserves `kSecAttrLabel`/`kSecAttrDescription`), wired into all three stores ahead of their existing legacy migrations; it no-ops until the Keychain Sharing entitlement exists (copy fails `errSecMissingEntitlement` → not marked done → retried), so wiring the group ahead of the entitlement never loses data. **Gap #3 (now addressed in-app):** scaffolded `Web3SwiftWalletConnectorCryptoProvider` (app: `Aura/WalletConnection/Web3SwiftWalletConnectorCryptoProvider.swift`) — real secp256k1 public-key recovery (mirrors web3.swift `KeyUtil`, returns the 64-byte key the verifier needs) + `keccak256` via `Data.web3.keccak256`, `supportsRecovery = true`; injected into both `WalletConnectDAppConnector` call sites, lifting EVM readiness to `.productionReady`. EIP-1271 left as a documented TODO (`supportsSmartContractOwnership` stays `false` → smart-contract wallets still fail closed until an RPC-backed `isValidERC1271Signature` is added). Package build+tests green (SRC-39: 198/192/6-skip/0-fail). **Caveat:** the app target (incl. `import secp256k1`) is not in this package workspace and was not compiled here — app compile + the on-device entitlement/migration behavior are part of AUD-022.
- **Follow-up / owner:** (1) Host: add the Keychain Sharing entitlement (app + extension) with the matching group and verify cross-process restore + private→shared migration on device (AUD-022). (2) Confirm `import secp256k1` resolves for the app target (it is transitive via web3.swift); if not, add it as a direct product dependency. (3) Implement EIP-1271 in `Web3SwiftWalletConnectorCryptoProvider` for smart-contract wallets. (4) Original follow-ups: write additional unit coverage for the v1 typed-data signer + per-record restore isolation (`recoverPublicKey`, `supportsRecovery = true`, and `isValidERC1271Signature`/`supportsSmartContractOwnership` for smart-contract wallets) and inject it into both `WalletConnectDAppConnector` call sites. (3) Add unit coverage for the v1 typed-data signer path and the per-record restore-isolation path. (4) Sources-Registry hygiene: `SRC-23`/`SRC-24` are each defined twice — renumber future citations (not retroactively, to avoid breaking existing references).
- **Signed:** Opus 4.8 (session H)

---

### AUD-033 — Independent report-only re-audit: SDK-free core verified ship-ready; only device QA + low-sev opportunities remain
- **Status:** 🔵 Verified-OK
- **Type:** Gap (coverage) / Triage
- **Severity:** Low
- **Area:** Crypto / Transport / Persistence / Services / Requests / Domain
- **Found by:** Opus 4.8 (session G) on 2026-08-05
- **Description:** Independent strict read of the security-critical surface (see session-G scope row). I could not find a new code defect: the crypto envelope + key derivation match reown/KMS; ownership verification fails closed (EOA recovery-id-agnostic, EIP-1271 fallback opt-in, Solana ed25519 self-contained); the IRN transport binds responses to their publish topic, rejects type1 envelopes off a pending-proposal pairing topic, rejects out-of-scope/out-of-namespace settles, dedups on decrypted identity with a TTL ≥ the longest relay TTL, clamps expiry to the 7-day cap, and mints monotonic ids; the three keychain stores now namespace their accounts and filter `loadAll` (AUD-032), fail closed on unreadable, and migrate legacy layouts idempotently; the lifecycle service verifies each distinct signing key once, rolls back partial persists, and is chain-scoped on cleanup. The current **uncommitted** working tree builds clean (SRC-36).
- **Non-blocking opportunities / nice-to-haves surfaced (none block the core):** (1) `WalletConnectorCapabilities` still not wired into registry filtering (tracked AUD-031). (2) Relay socket TLS pinning intentionally absent (defense-in-depth only; documented). (3) `WalletChain` remains a closed enum — undeclared CAIP-2 chains drop fail-closed (LIM-6); a data-driven chain model is a future opportunity. (4) Link Mode (`wc_ev`) unsupported by the custom transport by design (throws `.unavailable`; use an SDK adapter). (5) MetaMask/Solana adapters are request-only stubs by design. (6) **Consistency:** AUD-028 justifies the per-topic session-state store by a cross-process (app+extension) clobber, but no store sets `kSecAttrAccessGroup`, so by default these generic-password items are not actually shared cross-process — the per-item design is still good hardening, but the premise should be reconciled or an access group added if extension sharing is real (already flagged as an AUD-032 follow-up). (7) **Log hygiene:** the Sources Registry defines `SRC-23` and `SRC-24` twice each (Privy/Dynamic web+build vs. Codex build+test) — future citations are ambiguous; renumber.
- **Root cause:** n/a (verification pass).
- **Fix:** None applied (report-only by user direction). Opportunities above are product/hardening backlog, not defects.
- **Sources used to verify:** `code:` all core files listed in the session-G scope row; `build:` SRC-36; prior green `test:` SRC-35. The live-adapter paths (`#if canImport`/`#if os(iOS)`) are excluded from the host build and remain covered only by AUD-022.
- **Could not fully resolve because:** The live vendor paths and cross-launch keychain behavior can only be proven on a device (AUD-022), which the user is deferring to a later manual pass; this audit is code-only.
- **Follow-up / owner:** Treat AUD-022 device QA as the hard ship gate for Reown/Coinbase/Privy/Dynamic. Consider the low-sev opportunities as backlog.
- **Signed:** Opus 4.8 (session G)

---

### AUD-032 — Topic store shared one keychain service with foreign record kinds and enumerated it without a discriminator (broke/corrupted cross-launch restore)
- **Status:** ✅ Resolved
- **Type:** Defect
- **Severity:** High (product-blocking for the custom-IRN cross-launch restore path — the app's actual default composition)
- **Area:** Persistence
- **Found by / fixed by:** Opus 4.8 (session F) on 2026-08-05
- **Description:** Three keychain record kinds all default to the **same** service `com.auraplay.walletconnect`, stored as `kSecClassGenericPassword` with no access-group/type discriminator: `WalletConnectKeychainRelayAuthProvider` (account `relay-auth-identity`, 32 raw Ed25519 bytes), `KeychainWalletConnectSessionStateStore` (accounts `session-record:<topic>`, session JSON — per-topic since AUD-028), and `KeychainWalletSessionTopicStore` (accounts `<address>`/`<caip2>:<address>`, topic string). The app wires all three with defaults (`AuralisWalletConnectionFeature.swift:154,:164`; relay client's default `authProvider`), so they collide in one `(class, service)` namespace. `KeychainWalletSessionTopicStore.loadAll()` queried by **service only** (`allItemsQuery()` = `baseQuery()`, no `kSecAttrAccount` filter) with `kSecMatchLimitAll` and treated **every** returned row as a topic record — it could not tell its own records from foreign ones (the `WalletKeychainRecordKind.sessionTopic = "session-topic"` discriminator existed in the enum but was never applied to the account key). Two concrete failure modes on the first relaunch after a real connect: **(1)** the `relay-auth-identity` row's 32 random bytes are (almost always) not valid UTF-8, so `String(data:encoding:.utf8)` returns nil and `loadAll()` throws `.invalidTopicData` — `WalletConnectionLifecycleService.restoreSavedSessions()`/`remove()` (both `try await topicStore.loadAll()`) propagate the throw and restore never works; **(2)** the `session-record:<topic>` rows decode as bogus records with `address = "session-record:<topic>"`, so `restoreSavedSessions` finds no live session and calls `topicStore.delete(walletAddress: "session-record:<topic>")`, whose lookup key is exactly the session-state store's own item — **restore deletes the persisted session key material it was meant to rehydrate.** The app's own `topicStore.load(walletAddress:)` not-found fallback also routes through `loadAll()`.
- **Root cause:** Topic records carried no account-kind discriminator, and `loadAll`/the query factory enumerated the whole shared service, so foreign items (relay identity, per-topic session-state records) were indistinguishable from topic records. Masked by every prior audit because it only manifests with real, mixed-kind keychain items on device — exactly the host-skipped ("4 skipped") integration path; the in-memory stores don't share a namespace so unit tests stayed green.
- **Fix:** Namespaced the topic store's keychain accounts with the `session-topic:` discriminator (`KeychainSessionTopicQueryFactory.accountPrefix` + prefixed `recordIdentifier`, prefix-tolerant `parseRecordIdentifier`). `loadAll()` now filters rows to the `session-topic:` prefix (foreign rows are skipped, never parsed or thrown on). Added a one-shot, idempotent, best-effort `migrateLegacyTopicRecordsIfNeeded()` that re-keys any legacy un-prefixed topic record under the namespaced account and deletes the original — guarded so it never touches another known record kind (relay identity / `session-record:` items). Called at the top of `save`/`load`/`loadAll`/`delete`.
- **Sources used to verify:** `code:Sources/WalletConnectorKit/Persistence/KeychainSessionTopicStore.swift` (prefix, filter, migration); `code:Sources/WalletConnectorKit/Crypto/WalletConnectRelayAuth.swift:106,:194` + `code:Sources/WalletConnectorKit/Persistence/WalletConnectSessionStateStore.swift:164,:179` (shared service); `code:Auralis/Aura/WalletConnection/AuralisWalletConnectionFeature.swift:154,:164` (app composition); `test:WalletConnectDeepLinkTests.topicStoreAccountKeysAreNamespaced` (host-runnable discriminator/round-trip/no-collision), `test:WalletConnectDeepLinkTests.keychainTopicStoreLoadAllIgnoresForeignRecords` + `.keychainTopicStoreMigratesLegacyUnnamespacedRecord` (environment-gated); SRC-34, SRC-35.
- **Could not fully resolve because:** The two new keychain integration tests are environment-gated (skipped on the CI host, like the other 4), so the on-device foreign-record filtering + legacy migration are validated as part of the deferred AUD-022 device QA. The host-runnable discriminator test proves the namespacing/round-trip/no-collision invariant on every run.
- **Follow-up / owner:** Include the cross-store `loadAll` isolation + legacy-topic migration in the AUD-022 device-QA pass. Reconcile the AUD-028 cross-process premise with the absence of a `kSecAttrAccessGroup` on any store (secondary note from this session's report).
- **Signed:** Opus 4.8 (session F)

---

### AUD-027 — Ownership verification was EOA-only; smart-contract (EIP-1271) wallets failed closed under the default policy
- **Status:** ✅ Resolved
- **Type:** Defect / Feature gap
- **Severity:** High (product-blocking for Coinbase Smart Wallet / Safe / ERC-4337 / smart-account embedded wallets)
- **Area:** Crypto / Adapter:* (all EVM connectors)
- **Found by / fixed by:** Opus 4.8 (session E) on 2026-08-05
- **Description:** `WalletOwnershipVerifier.verifyPersonalSign` only performed secp256k1 EOA recovery (`ecrecover` → `keccak256(pubkey)[12:]`). A smart-contract account has no recoverable private key — it validates signatures on-chain via EIP-1271 `isValidSignature(bytes32,bytes)` — so recovery could never match its address and verification silently returned `false` (its returned signature is also not the 65-byte EOA layout, so it hit `.invalidResponse` before verification). Under the package default `ownershipPolicy: .requireVerified`, a legitimate Coinbase Smart Wallet / Safe / ERC-4337 / smart-account Privy/Dynamic user could not persist a session at all — a silent "couldn't verify ownership."
- **Root cause:** Verification modeled only EOA key recovery; the package deliberately vends no RPC, so on-chain EIP-1271 validation had no seam.
- **Fix:** Added an **opt-in** provider hook: `WalletConnectorCryptoProvider.supportsSmartContractOwnership` (default `false`) + `isValidERC1271Signature(address:message:signature:chain:)` (default throws `.unavailable` so a misconfigured provider fails loud). Added an additive async overload `WalletOwnershipVerifier.verifyPersonalSign(...signatureHex:chain:using:)` that tries EOA recovery first and, when the provider opts in, falls back to the on-chain EIP-1271 check for the raw signature. Switched all five EVM connectors (`WalletConnectDAppConnector`, `Reown`, `Coinbase`, `Privy`, `Dynamic`) to the async overload. The existing sync method is unchanged (back-compat; still used by tests). Fail-closed preserved: no recovery provider still rethrows; an EOA wallet with a malformed sig and no SC support still throws `.invalidResponse`; a contract wallet with no injected validator surfaces the provider's `.unavailable` guidance. README documents injecting an RPC-backed provider or using `.allowUnverified` for non-sensitive flows.
- **Sources used to verify:** `code:Sources/WalletConnectorKit/Crypto/WalletConnectorCryptoProvider.swift` (protocol hook + async overload), five connector call sites; `code:README.md` ("Smart-contract wallets (EIP-1271)"); `test:WalletMultiChainOwnershipTests` (`asyncVerifyPersonalSignEOA`, `asyncVerifyPersonalSignERC1271`, `asyncVerifyPersonalSignNoSmartContractSupport`, `smartContractDefaultImplementationThrows`); SRC-32, SRC-33.
- **Could not fully resolve because:** The package still cannot itself perform the on-chain `eth_call` — the host must inject an RPC-backed provider. Live proof against a real contract wallet is part of the deferred AUD-022 device QA.
- **Follow-up / owner:** Auralis web3.swift provider owner: implement `isValidERC1271Signature` + set `supportsSmartContractOwnership = true`.
- **Signed:** Opus 4.8 (session E)

---

### AUD-028 — Session-state keychain store kept every session in one JSON blob (cross-process clobber)
- **Status:** ✅ Resolved
- **Type:** Defect / Hardening (concurrency)
- **Severity:** Medium
- **Area:** Persistence
- **Found by / fixed by:** Opus 4.8 (session E) on 2026-08-05
- **Description:** `KeychainWalletConnectSessionStateStore` stored all sessions in a single generic-password item (account `session-record`) as a JSON array, and `save`/`delete` did read-modify-write on it. The `actor` serializes that within one process, but not across processes: since the README requires an App Group for Reown and tells hosts to share session data with extensions, the app and an extension writing **different** sessions could clobber each other (last-writer-wins on the whole blob). (The topic store was already one item per address and is unaffected.)
- **Root cause:** Shared single-record read-modify-write with no cross-process lock and no CAS at the keychain layer.
- **Fix:** Converted the store to **one keychain item per session topic** (account `session-record:<topic>`), so `save`/`delete` mutate only the affected topic's item and can never clobber other sessions. `loadAll` enumerates the service and filters the `session-record:` prefix (a single undecodable item is purged as lost without dropping the rest); unreadable still fails closed (throws `.unreadable`) so the lifecycle does not destructively clean up. Added a one-shot, idempotent migration that splits any legacy single-blob record into per-topic items and then removes it (partial-failure-safe: the blob is only deleted once every session survives the split). Same-topic concurrent cross-process writes still last-writer-win (acceptable).
- **Sources used to verify:** `code:Sources/WalletConnectorKit/Persistence/WalletConnectSessionStateStore.swift`; `build:` SRC-32; `test:` SRC-33 (full plan green; the real-keychain integration/migration paths remain environment-gated skips and are covered by AUD-022 device QA).
- **Could not fully resolve because:** The 4 real-keychain integration tests are skipped on the CI host, so the on-device per-item behavior + legacy migration are validated as part of the deferred AUD-022 device QA.
- **Follow-up / owner:** Include the per-topic store + legacy-blob migration in the device-QA pass.
- **Signed:** Opus 4.8 (session E)

---

### AUD-029 — A keychain hiccup could turn a successful ownership proof into a thrown error
- **Status:** ✅ Resolved
- **Type:** Defect (robustness)
- **Severity:** Low
- **Area:** Transport
- **Found by / fixed by:** Opus 4.8 (session E) on 2026-08-05
- **Description:** In `WalletConnectDAppConnector.verifyOwnership`, after the signature cryptographically verified, the code called `transport.markOwnershipVerified` with `try await`. That call persists the `addressVerified` flag and throws on a keychain failure, so a transient keychain hiccup (device locked, momentary unavailability) would make `verifyOwnership` throw even though ownership was genuinely proven.
- **Root cause:** Best-effort flag persistence was treated as mandatory to the verification result.
- **Fix:** The `markOwnershipVerified` call is now best-effort (`try?`). Ownership is already proven at that point; the worst case is the flag is not persisted and the wallet re-verifies on the next launch (a re-prompt, not a security regression). The persistence failure still surfaces on the transport's own event stream.
- **Sources used to verify:** `code:Sources/WalletConnectorKit/Transport/WalletConnectDAppConnector.swift` (verifyOwnership); `build:` SRC-32; `test:` SRC-33.
- **Could not fully resolve because:** n/a
- **Follow-up / owner:** —
- **Signed:** Opus 4.8 (session E)

---

### AUD-030 — Cold-launch restore silently swallowed re-subscribe failures
- **Status:** ✅ Resolved
- **Type:** Gap (observability)
- **Severity:** Low
- **Area:** Transport
- **Found by / fixed by:** Opus 4.8 (session E) on 2026-08-05
- **Description:** `WalletConnectIRNTransportClient.performRestore` re-subscribed rehydrated topics in a detached `Task` using `try?`, swallowing any error. A topic that could not be re-subscribed (e.g. a very large queued mailbox exceeding the relay fetch-page cap) would restore in memory but silently miss peer-initiated update/delete traffic until the next outbound call on it.
- **Root cause:** Best-effort re-subscribe discarded the error entirely instead of reporting it.
- **Fix:** The detached re-subscribe now captures `onDiagnostic` and emits a per-topic diagnostic on failure (still best-effort — the relay re-subscribes on its own reconnect and `request()` subscribes on demand, so the restore is never failed on it).
- **Sources used to verify:** `code:Sources/WalletConnectorKit/Transport/WalletConnectIRNTransportClient.swift` (performRestore); `build:` SRC-32; `test:` SRC-33.
- **Could not fully resolve because:** n/a
- **Follow-up / owner:** —
- **Signed:** Opus 4.8 (session E)

---

### AUD-031 — `WalletConnectorCapabilities` was defined but unused, with no signal that it is forthcoming
- **Status:** ✅ Resolved
- **Type:** Gap (maintainability / docs)
- **Severity:** Low
- **Area:** Domain
- **Found by / fixed by:** Opus 4.8 (session E) on 2026-08-05
- **Description:** The `WalletConnectorCapabilities` OptionSet was defined but not yet consumed by `WalletConnectorRegistry`/catalog filtering, with no doc note explaining whether it was dead code or scaffolding — a reader could not tell.
- **Root cause:** Vocabulary landed ahead of the registry wiring without a marker.
- **Fix:** Added a doc comment marking it a host-facing capability vocabulary that is deliberately available ahead of internal registry filtering, with that wiring called out as forthcoming work. No behavior change.
- **Sources used to verify:** `code:Sources/WalletConnectorKit/Domain/WalletConnectorCapabilities.swift`; `build:` SRC-32.
- **Could not fully resolve because:** n/a (documentation decision; wiring into registry filtering is deferred product work, not a defect)
- **Follow-up / owner:** Wire capabilities into `WalletConnectorRegistry` filtering when that feature is scheduled.
- **Signed:** Opus 4.8 (session E)

---

### AUD-026 — Dead duplicate challenge builders in `WalletConnectDAppConnector`
- **Status:** ✅ Resolved
- **Type:** Gap (dead code / maintainability)
- **Severity:** Low
- **Area:** Transport
- **Found by:** Opus 4.8 (session D) on 2026-08-05
- **Description:** After AUD-014R routed all EVM/Solana ownership-challenge construction through the shared `WalletOwnershipChallengeMessageBuilder`, four private static methods in `WalletConnectDAppConnector` were left behind and are now **never called**: `siweMessage(...)` (:299), `solanaChallengeMessage(...)` (:332), `challengeNonce()` (:368), and `iso8601Formatter(_:)` (:362, only used by the first two). `verifyEVMOwnership`/`verifySolanaOwnership` use `WalletOwnershipChallengeMessageBuilder.evmSIWEMessage` / `.solanaMessage` / `.nonce()` instead. This is a live source of drift risk: a future edit to the real challenge shape in the shared builder would not touch these copies, and a reader could mistake them for the production path. Separately, `SRC-12` in this log still cites `WalletConnectDAppConnector.siweMessage` as the EIP-4361 verification anchor — that citation is stale; the live anchor is `WalletOwnershipChallengeMessageBuilder.evmSIWEMessage`.
- **Root cause:** Refactor to a shared builder (AUD-014R) did not delete the superseded connector-local helpers.
- **Fix:** Deleted the four unused `private static` helpers (`siweMessage`, `solanaChallengeMessage`, `iso8601Formatter`, `challengeNonce`) from `WalletConnectDAppConnector`, and removed the now-unused `import Security` (its only user was the deleted `challengeNonce`'s `SecRandomCopyBytes`). The live path (`WalletOwnershipChallengeMessageBuilder.evmSIWEMessage` / `.solanaMessage` / `.nonce()`) is unchanged. Corrected the stale `SRC-12` citation to point at `WalletOwnershipChallengeMessageBuilder.evmSIWEMessage`.
- **Sources used to verify:** `code:Sources/WalletConnectorKit/Transport/WalletConnectDAppConnector.swift:222-264` (live path uses shared builder; helpers now gone); post-deletion grep of the file for `Sec*/Security/kSec/errSec` returns only nothing (import removed); `build:` SRC-30 (compiles clean after deletion); `test:` SRC-31 (188→ still green, no behavior change). Original finding evidence: SRC-27, SRC-28.
- **Could not fully resolve because:** n/a
- **Follow-up / owner:** —
- **Signed:** Opus 4.8 (session D)

---

### AUD-010F — Keccak-256 KAT coverage extended to the multi-block path (closes AUD-010 follow-up)
- **Status:** ✅ Resolved
- **Type:** Hardening (test coverage)
- **Severity:** Low
- **Area:** Crypto
- **Found by / fixed by:** Opus 4.8 (session D) on 2026-08-05
- **Description:** AUD-010 left open that the from-scratch `EthereumKeccak256` was exercised only *indirectly* (via SIWE/address tests) and that its explicit KAT suite (`WalletCryptoProviderTests.keccakMatchesKnownVectors`) covered only `""` and `"abc"` — both single sponge blocks (< the 136-byte rate). The multi-block absorption loop (`while offset + rate <= bytes.count`) had no direct known-answer coverage.
- **Fix:** Extended the parameterized vector set with authoritative **original-Keccak-256** vectors (Ethereum `0x01` padding — not FIPS-202 SHA3-256, which uses `0x06`): the two "quick brown fox" sentences (44-byte boundary) and a **341-byte** MD5-description string that crosses the 136-byte rate and exercises multi-block absorption. Vectors taken verbatim from the `emn178/js-sha3` reference test suite. The test asserts `DefaultWalletConnectorCryptoProvider().keccak256(input).hexString == expected`; the green run confirms both the vectors and the implementation's multi-block path.
- **Sources used to verify:** `code:Tests/WalletConnectorKitTests/WalletConnectorKitTests.swift` (`WalletCryptoProviderTests.keccakMatchesKnownVectors`, 5 vectors incl. the 341-byte input); SRC-29 (vector source); SRC-30 (build); SRC-31 (test — `keccakMatchesKnownVectors` passes for all 5 cases, total 191/187/4/0).
- **Could not fully resolve because:** n/a
- **Follow-up / owner:** —
- **Signed:** Opus 4.8 (session D)


### Template (copy this)

```
### AUD-000 — <short title>
- **Status:** 🔴 Open | 🟡 Partial | ✅ Resolved | 🔵 Verified-OK | ⛔ Blocked
- **Type:** Defect | Gap | Blocker | Hardening | Spec-conformance
- **Severity:** Critical | High | Medium | Low
- **Area:** Crypto | Transport | Persistence | Registry | Requests | Domain | Adapter:<name>
- **Found by:** <model / session> on YYYY-MM-DD
- **Description:** What is wrong or missing.
- **Root cause:** Why it happened (be specific — API misuse, spec gap, race, etc.).
- **Fix:** What changed. Reference `code:` paths+lines.
- **Sources used to verify:** SRC-x, `test:...`, `build:...`, `doc:...`. Be specific.
- **Could not fully resolve because:** (only if 🟡/⛔) the concrete blocker, and what's needed to close it.
- **Follow-up / owner:** Linked entries or next action.
- **Signed:** <model / session>
```

---

### AUD-025 — Semantic EVM personalSign now hex-encodes text instead of sending raw strings
- **Status:** ✅ Resolved
- **Type:** Defect / API footgun
- **Severity:** Medium
- **Area:** Requests
- **Found by / fixed by:** Codex GPT-5 on 2026-08-04
- **Description:** `EVMWalletOperation.personalSign(address:message:)` looked like a user-readable semantic API but routed to `WalletRequestBuilder.personalSign`, whose `message` parameter is documented as already-encoded `0x` hex. The existing semantic-operation test expected `"Hello"` to pass through raw, which can produce invalid WalletConnect `personal_sign` payloads.
- **Root cause:** The semantic operation reused the low-level raw builder instead of the existing text helper.
- **Fix:** `EVMWalletOperation.personalSign(message:)` now routes through `WalletRequestBuilder.personalSignText`, so human-readable text is UTF-8 hex encoded. `WalletRequestBuilder.personalSign(message:)` remains the explicit raw hex builder, and the README calls out the distinction.
- **Sources used to verify:** `code:Sources/WalletConnectorKit/Requests/WalletOperation.swift`; `code:README.md` (`personal_sign` message encoding); `test:WalletConnectionCoreTests/semanticWalletOperationsProduceChainSpecificRequests`; SRC-23; SRC-24.
- **Could not fully resolve because:** n/a
- **Follow-up / owner:** n/a
- **Signed:** Codex GPT-5

---

### AUD-024 — Custom IRN readiness no longer claims production without EVM recovery support
- **Status:** ✅ Resolved
- **Type:** Defect / Hardening
- **Severity:** High
- **Area:** Transport / Crypto / Lifecycle
- **Found by / fixed by:** Codex GPT-5 on 2026-08-04
- **Description:** `WalletConnectDAppConnector` defaulted `readiness` to `.productionReady` even when no recovery-capable `WalletConnectorCryptoProvider` was injected. The transport can complete WalletConnect v2, but the default strict lifecycle requires EVM ownership verification before identity persistence; without secp256k1 recovery, that verification throws fail-closed.
- **Root cause:** Readiness modeled transport completeness but not the ownership dependency required by the package's default production lifecycle.
- **Fix:** The initializer now accepts an optional readiness override; when omitted, readiness is derived from `cryptoProvider?.supportsRecovery`. Missing recovery support reports `.experimental`, a recovery-capable provider reports `.productionReady`, and explicit host overrides remain possible. README and QA checklist now document the split.
- **Sources used to verify:** `code:Sources/WalletConnectorKit/Transport/WalletConnectDAppConnector.swift`; `code:README.md` (connector readiness); `code:WalletConnectorKit-QA-Checklist.md` (Connector readiness); `test:WalletConnectionCoreTests/dAppConnectorReadinessIsGatedOnOwnershipDependenciesByDefault`; SRC-23; SRC-24.
- **Could not fully resolve because:** Live-wallet/device QA remains a separate gate tracked by AUD-022.
- **Follow-up / owner:** Host composition must still inject the production recovery provider before routing strict EVM identity flows.
- **Signed:** Codex GPT-5

---

### AUD-023 — Make MetaMask/Privy/Dynamic/Solana "working": full-lifecycle Privy/Dynamic + WalletConnect routing for MetaMask/Solana
- **Status:** 🟡 Partial (in-package structure done; vendor SDK live clients + device QA remain)
- **Type:** Gap / Feature
- **Severity:** High (these four were previously non-functional as production providers)
- **Area:** Adapter:Privy / Adapter:Dynamic / Adapter:MetaMask / Adapter:Solana
- **Found by / worked by:** Opus 4.8 (session C) on 2026-08-04, per user direction ("Route external wallets through WalletConnect/Reown AND scaffold real Privy/Dynamic embedded-wallet adapters").
- **Description:** The four adapters were stubs (AUD-015): protocols covered only connect/request/disconnect, so wrappers could never delegate sessions/callbacks/events/ownership, and readiness could not honestly reach production.
- **What was done:**
  - **Privy + Dynamic — full connector lifecycle.** `PrivySDKClient` / `DynamicSDKClient` now cover the complete surface: `events`, `connect(wallet:) -> WalletConnectorSession` (embedded wallets provision an account, like Coinbase MWP — no pairing URI), `request`, `handleCallback`, `sessions()`, `disconnect`. The `PrivyWalletConnector` / `DynamicWalletConnector` wrappers delegate all of it and add EVM `verifyOwnership` via the shared `WalletOwnershipChallengeMessageBuilder` + `WalletOwnershipVerifier` (identical to Coinbase). Readiness is gated exactly like Reown/Coinbase: unconfigured → `.unavailable`; configured but missing a recovery-capable provider or real metadata → `.experimental`; configured + both → `.productionReady`. Root cause of AUD-015 (protocol did not cover the full lifecycle) is closed for these two.
  - **MetaMask — route via WalletConnect/Reown.** The native MetaMask iOS SDK is archived (`Package.swift`), so there is no live client to link. Documented (README Products + QA checklist) that MetaMask connects through the custom IRN transport or the Reown adapter; the bespoke `MetaMaskWalletConnector` stays a request-only `.experimental` stub.
  - **Solana — route via WalletConnect/Reown, execute here.** No Solana session SDK exists; the adapter remains request-only by design. Documented that Solana wallets connect through Reown/WC (or deep link) and route Solana requests through the adapter.
- **SDK verification + wiring (2026-08-05 follow-up):** Confirmed against live sources (SRC-23) that **Privy and Dynamic ship viable native-Swift SPM SDKs**, while **MetaMask (archived) and Solana (no native dApp SPM SDK) do not.** Added the two viable deps to `Package.swift` and their adapter targets (iOS-conditional, matching Reown/Coinbase): `Privy` (product name — module is `PrivySDK`) and `DynamicSDKSwift`. `swift package resolve` + `swift build` + full test plan all green (SRC-24, SRC-22 re-run 188/184/4/0). MetaMask/Solana deps were **not** added and never will be — route through WalletConnect/Reown.
- **Live clients written + compile-verified (2026-08-05 follow-up):** `LivePrivySDKClient` and `LiveDynamicSDKClient` are now implemented against the **real** vendor APIs read from the vendored `.swiftinterface` files (SRC-26), not inferred. Both are guarded by `#if canImport(PrivySDK)` / `#if canImport(DynamicSDKSwift)` so they compile only where the SDK is linked (iOS), and both were **compile-verified by an iOS-simulator `xcodebuild` (BUILD SUCCEEDED, SRC-25)** — the macOS host build/test can't exercise them. Design: both SDKs are auth-first embedded wallets, so `connect` surfaces the *already-authenticated* embedded EVM wallet as a settled session (the host owns the login UI), `request` routes JSON-RPC through the wallet provider (`EmbeddedEthereumWalletProvider.request` / `DynamicSDK.evm.request`), and `disconnect` logs out. The Dynamic client is nonisolated `@unchecked Sendable` with `nonisolated(unsafe) let sdk` because `DynamicSDK` is a non-`Sendable` binary class (the first `@MainActor` attempt failed compilation with region-isolation "sending" errors — caught by SRC-25 and fixed).
- **What is STILL NOT done (and why):** (1) **Runtime composition** — a host must construct `LivePrivySDKClient(config:)` / `LiveDynamicSDKClient(sdk:)` with its **own app ID / environment ID**, then wrap it as `PrivyWalletConnector(client:cryptoProvider:metadata:)` with a **recovery-capable secp256k1 provider** (the package deliberately does not vend one — `DefaultWalletConnectorCryptoProvider` throws) **and real `WalletConnectionMetadata`**. Only then does readiness flip to `.productionReady`. The package cannot fabricate credentials or the app's web3.swift recovery provider, so this final wiring is host code by design. The shipped default remains the `Unconfigured…` stub (`.unavailable`). (2) **No on-device QA** — the live clients compile but have never run against a real Privy/Dynamic account. AUD-022 explicitly covers Privy/Dynamic.
- **Sources used to verify:** `code:Sources/WalletConnectorKitPrivyAdapter/PrivyWalletConnector.swift`, `code:Sources/WalletConnectorKitDynamicAdapter/DynamicWalletConnector.swift`, `code:README.md` (Products), `code:WalletConnectorKit-QA-Checklist.md` (Direct SDK Adapters + Connector readiness); `test:StubAdapterReadinessTests/configuredEmbeddedAdaptersReachProductionWithOwnershipDependencies` (new), `test:StubAdapterReadinessTests/configuredPartialProviderAdaptersRemainExperimental`, `test:StubAdapterReadinessTests/unconfiguredStubsAreUnavailable`; SRC-22.
- **Could not fully resolve because:** Vendor SDKs are not linkable/verifiable here and no device is available. To reach `.productionReady`: (1) add the Privy/Dynamic SPM deps in the host or package, (2) implement `PrivySDKClient`/`DynamicSDKClient` against the real SDK, (3) inject a recovery-capable secp256k1 provider + real `WalletConnectionMetadata`, (4) pass the device QA (AUD-022).
- **Follow-up / owner:** Embedded-wallet integration owner. Supersedes AUD-015 for Privy/Dynamic (protocol-lifecycle root cause closed); MetaMask/Solana routing is a documented product decision, not a code defect.
- **Signed:** Opus 4.8 (session C)

---

### AUD-022 — No live-wallet / on-device QA has been executed; the two live adapters are unproven end-to-end
- **Status:** ⛔ Blocked (environment) — cannot be closed by an AI session; requires a device + real wallets. Ship gate for Reown/Coinbase adapters; **not** a core blocker.
- **Type:** Gap / Blocker (validation)
- **Severity:** High (for anyone shipping Reown or Coinbase as a production route)
- **Area:** Adapter:Reown / Adapter:Coinbase / Runtime
- **Found by:** Opus 4.8 (session C) on 2026-08-04
- **Description:** Every test in the suite exercises **in-process mocks** — mock relay sockets, mock SDK clients, stub crypto providers. That is exactly why the unit suite is trustworthy for the *core*, but it means the live vendor paths have **zero** executed (runtime) verification. This now covers **four** live clients: `ReownAppKitLiveClient`, `LiveCoinbaseWalletSDKClient`, and (added 2026-08-05) `LivePrivySDKClient` + `LiveDynamicSDKClient`. All four are now **compile-verified for iOS** (Reown/Coinbase via the existing build; Privy/Dynamic via SRC-25's iOS-simulator `xcodebuild`), but **none has been run against a real wallet/account on a device.** The `WalletConnectorKit-QA-Checklist.md` "Manual Live-Wallet Suite" is entirely unchecked. This is the decisive gap between "compiles + green unit tests" and "good to ship the adapters."
- **Root cause:** No linked device or real provider account/credentials in any audit session; live paths are SDK-dependent and cannot execute under `swift test` / the package test plan (which run on the macOS host where the `#if canImport`/`#if os(iOS)` code is excluded).
- **Fix:** Not fixable in-package. Before enabling Reown, Coinbase, Privy, or Dynamic as a production route: run the Manual Live-Wallet Suite on a device; for Reown/Coinbase confirm the deep-link return round-trips through `handleCallback`; for Privy/Dynamic confirm login → embedded-wallet `connect` → `request` (`personal_sign`) → `disconnect`; and for all four confirm `verifyOwnership` recovers the connected address with the **real** injected secp256k1 provider (not a stub).
- **Sources used to verify:** `code:…ReownAdapter/ReownAppKitLiveClient.swift`, `code:…CoinbaseAdapter/LiveCoinbaseWalletSDKClient.swift`, `code:…PrivyAdapter/LivePrivySDKClient.swift`, `code:…DynamicAdapter/LiveDynamicSDKClient.swift` (all vendor-SDK-gated); `WalletConnectorKit-QA-Checklist.md` "Manual Live-Wallet Suite" (unexecuted); SRC-20, SRC-25; prior acknowledgement AUD-007.
- **Could not fully resolve because:** No device or real provider credentials in this environment. Compile-verification (SRC-25) is as far as an AI session can take it.
- **Follow-up / owner:** Wallet integration owner — treat device QA as a hard gate for shipping Reown/Coinbase/Privy/Dynamic.
- **Signed:** Opus 4.8 (session C)

---

### AUD-021 — QA checklist "Connector readiness" row describes stale readiness values
- **Status:** ✅ Resolved
- **Type:** Gap (documentation drift)
- **Severity:** Low
- **Area:** Registry / Docs
- **Found by / fixed by:** Opus 4.8 (session C) on 2026-08-04
- **Description:** `WalletConnectorKit-QA-Checklist.md` (Connector readiness row) stated that configured MetaMask/Privy/Dynamic/Solana/Reown/Coinbase clients "report `readiness == .unavailable`." That was no longer true after AUD-015R/AUD-018R: configured MetaMask/Privy/Dynamic report `.experimental`, and Reown/Coinbase report `.experimental` (until a recovery provider + real metadata are injected) and only then `.productionReady`. Only *unconfigured* clients report `.unavailable`.
- **Root cause:** The checklist row predated the AUD-015R/018R readiness-gating changes and was not updated alongside them.
- **Fix:** Rewrote the "Connector readiness" row to state per-state expectations: unconfigured → `.unavailable`; configured MetaMask/Privy/Dynamic → `.experimental`; configured Solana → `.experimental` (request-only); Reown/Coinbase → `.experimental` until a recovery provider + real metadata are injected, then `.productionReady`.
- **Sources used to verify:** `code:WalletConnectorKit-QA-Checklist.md` "Connector readiness" (updated); `code:Sources/WalletConnectorKitMetaMaskAdapter/MetaMaskWalletConnector.swift:33-37`, `code:Sources/WalletConnectorKitReownAdapter/ReownWalletConnector.swift:54-65`, `code:Sources/WalletConnectorKitCoinbaseAdapter/CoinbaseWalletConnector.swift:47-58`; `test:StubAdapterReadinessTests/configuredPartialProviderAdaptersRemainExperimental`.
- **Could not fully resolve because:** n/a
- **Follow-up / owner:** —
- **Signed:** Opus 4.8 (session C)

---

### AUD-020 — `WalletConnectorRegistry.init` traps on duplicate provider IDs from caller input
- **Status:** ✅ Resolved
- **Type:** Defect / Hardening (robustness)
- **Severity:** Low
- **Area:** Registry
- **Found by / fixed by:** Opus 4.8 (session C) on 2026-08-04
- **Description:** `WalletConnectorRegistry.init(providers:)` built its index with `Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0) })`, which **traps at runtime** if two providers share an `id`. The initializer is `public` and accepts arbitrary caller-supplied `[ThirdPartyWalletProvider]`, so a host appending a custom provider whose id collided with a catalog id crashed the process. `WalletConnectionLifecycleService.restoreSavedSessions` already avoided this exact trap at the connector boundary with `uniquingKeysWith: { first, _ in first }`.
- **Root cause:** Trapping dictionary initializer used on externally-supplied input that has no uniqueness guarantee.
- **Fix:** Switched to `Dictionary(providers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })` (first occurrence wins), mirroring the lifecycle service.
- **Sources used to verify:** `code:Sources/WalletConnectorKit/Registry/WalletConnectorRegistry.swift:6-15` (safe init); `test:WalletConnectorRegistryTests/registryToleratesDuplicateProviderIDs` (new regression, passes — SRC-21); full plan still green (SRC-21).
- **Could not fully resolve because:** n/a
- **Follow-up / owner:** —
- **Signed:** Opus 4.8 (session C)

---

### AUD-017R / AUD-018R / AUD-019R / LIM-6 — Fixes applied and verified
- **Status:** ✅ Resolved
- **Type:** Defect / Gap / Hardening
- **Severity:** Medium / Medium / Low / (limitation)
- **Area:** Services / Persistence / Adapter:Reown / Adapter:Coinbase / Domain
- **Found by / fixed by:** Opus 4.8 on 2026-08-04
- **AUD-017 fix — SDK session cold-launch restore:** `WalletSessionTopicRecord` now carries a `verified` flag persisted by both the in-memory and keychain topic stores (keychain uses `kSecAttrDescription`, legacy records default to `false` = fail-closed). `WalletConnectionLifecycleService.persistApprovedSession` writes `verified: session.addressVerified || policy == .requireVerified`; `restoreSavedSessions` merges `session.addressVerified || savedTopic.verified`, so a Reown/Coinbase wallet proven at connect time re-activates on cold launch **without** re-prompting, while genuinely unverified/legacy records still land in `unverifiedSessionTopics`.
  - Verified by `test:WalletConnectionCoreTests/lifecycleStrictRestoreMergesPersistedOwnershipProof`, `test:WalletConnectionCoreTests/lifecyclePersistsOwnershipProofOntoTopicRecord`, and the still-passing `lifecycleStrictRestoreLeavesUnverifiedSessionsInactive` (legacy records stay inactive).
- **AUD-018 fix — SDK connector readiness gating:** `WalletConnectorCryptoProvider` gained `supportsRecovery` (default `false`; `DefaultWalletConnectorCryptoProvider` inherits `false`). `ReownWalletConnector` and `CoinbaseWalletConnector` now report `.experimental` (not `.productionReady`) unless a recovery-capable provider **and** explicit `WalletConnectionMetadata` were injected, so `allowsProductionUse` is false until the connector can actually complete `.requireVerified` ownership. Unconfigured → still `.unavailable`.
  - Verified by `test:WalletConnectorKitTests/sdkConnectorReadinessRequiresOwnershipDependencies`.
- **AUD-019 fix — Coinbase synthetic expiry/global reset:** `LiveCoinbaseWalletSDKClient` exposes `sessionValidity` (default `defaultSessionValidity` = 30d) so the synthetic expiry is caller-tunable, and `disconnect` now documents that MWP `resetSession` is a global single-session teardown.
- **LIM-6 fix — chain coverage:** `WalletChain` gained `avalanche` (43114), `bnb` (56), `zksync` (324), `linea` (59144); all exhaustive switches, `evmChains`, and the default V1 optional proposal updated. Arbitrary/undeclared CAIP-2 chains are still dropped fail-closed (the enum stays closed by design), so LIM-6 is narrowed, not eliminated.
  - Verified by `test:WalletConnectorRegistryTests/extendedEVMChainsResolveCAIP2`.
- **Sources used to verify:** `build:BuildProject(buildForTesting:) → success`; `test:RunAllTests → 186 total, 182 passed, 4 skipped, 0 failed (2026-08-04 13:10 MDT)`.
- **Could not fully resolve because:** LIM-6 remains a bounded enum (approved scope: add popular chains, not a data-driven refactor). Live Reown/Coinbase device QA still pending per the QA checklist.
- **Follow-up / owner:** Host composition must inject a recovery-capable provider + real metadata to flip Reown/Coinbase to `.productionReady`; keychain-integration tests for the new `verified` attribute remain environment-gated (skipped on this runner).
- **Signed:** Opus 4.8

---

### AUD-019 — Live Coinbase adapter uses a synthetic 30-day expiry and a global session reset
- **Status:** ✅ Resolved (see AUD-019R above)
- **Original status:** 🔴 Open
- **Type:** Gap / Hardening
- **Severity:** Low
- **Area:** Adapter:Coinbase
- **Found by:** Opus 4.8 on 2026-08-04
- **Description:** `LiveCoinbaseWalletSDKClient.session(from:)` stamps every Coinbase session with `expiryDate = now + 30 days` because Coinbase Mobile Wallet Protocol has no session-expiry concept. A wallet that was reset/revoked server-side still reads as "live" locally for up to 30 days (`sessions()`/restore will surface it). Separately, `disconnect(sessionId:)` calls `CoinbaseWalletSDK.shared.resetSession()`, which clears the **entire** SDK session regardless of the `sessionId` argument, then removes only that one topic from `sessionsByTopic`. Both are acceptable given MWP is single-session and EVM-only, but they are silent assumptions.
- **Root cause:** MWP has no persistent WalletConnect session or expiry, so the adapter fabricates one.
- **Fix:** Not fixed (report-only). Consider a shorter/refreshable synthetic expiry, or treat Coinbase sessions as non-restorable, and document that `disconnect` is a global reset.
- **Sources used to verify:** `code:Sources/WalletConnectorKitCoinbaseAdapter/LiveCoinbaseWalletSDKClient.swift:104-108` (global reset), `:163-181` (30-day synthetic expiry); README "no persistent WalletConnect session."
- **Could not fully resolve because:** Report-only; live SDK/device not exercisable in this environment.
- **Follow-up / owner:** Coinbase adapter owner.
- **Signed:** Opus 4.8

---

### AUD-018 — Reown/Coinbase connectors default to a crypto provider that cannot verify ownership
- **Status:** ✅ Resolved (see AUD-017R/018R/019R above)
- **Original status:** 🔴 Open
- **Type:** Gap / Composition footgun
- **Severity:** Medium
- **Area:** Adapter:Reown / Adapter:Coinbase
- **Found by:** Opus 4.8 on 2026-08-04
- **Description:** `ReownWalletConnector.init` and `CoinbaseWalletConnector.init` both default `cryptoProvider` to `DefaultWalletConnectorCryptoProvider()`, whose `recoverPublicKey` **throws** (no secp256k1 recovery vended). Their own EVM `verifyOwnership` therefore throws unless the host explicitly injects a recovery-capable provider. Combined with `WalletConnectionLifecycleService`'s default `ownershipPolicy: .requireVerified`, a host that composes `CoinbaseWalletConnector(client:)` / `ReownWalletConnector(client:)` with the *default* initializer gets a connector that reports `.productionReady` but whose sessions can **never** be persisted (persist fails closed on the throwing verify). This is safe (fail-closed, no false "verified"), but it is a sharp edge: readiness says production-ready while the default composition cannot complete the default lifecycle. The same applies to the default `metadata` (a `walletconnectorkit.local` placeholder), so a challenge is domain-bound to a fake domain unless overridden.
- **Root cause:** Readiness is a property of the wrapper/live-client presence, not of whether the ownership-verification dependencies (recovery provider + real metadata) were injected.
- **Fix:** Not fixed (report-only). Either fail readiness to `.experimental` until a recovery-capable provider + real metadata are injected, or make production composition require them at the type level, or document them as mandatory in the host wiring checklist and add a test that `.requireVerified` + default provider throws.
- **Sources used to verify:** `code:Sources/WalletConnectorKitReownAdapter/ReownWalletConnector.swift:30-38,143-150`, `code:Sources/WalletConnectorKitCoinbaseAdapter/CoinbaseWalletConnector.swift:28-36,111-118`, `code:Sources/WalletConnectorKit/Crypto/WalletConnectorCryptoProvider.swift:45-49` (default throws), `code:Sources/WalletConnectorKit/Services/WalletConnectionLifecycleService.swift:68,84-85`.
- **Could not fully resolve because:** Report-only.
- **Follow-up / owner:** Host composition owner; treat injected secp256k1 provider + real `WalletConnectionMetadata` as mandatory for Reown/Coinbase before enabling them.
- **Signed:** Opus 4.8

---

### AUD-017 — SDK sessions (Reown/Coinbase) silently drop from the active set on every cold launch
- **Status:** ✅ Resolved (see AUD-017R/018R/019R above)
- **Original status:** 🔴 Open
- **Type:** Defect / Gap
- **Severity:** Medium (High if Reown/Coinbase is a primary production route)
- **Area:** Services / Adapter:Reown / Adapter:Coinbase
- **Found by:** Opus 4.8 on 2026-08-04
- **Description:** Ownership verification for SDK connectors happens once at connect time (`persistApprovedSession` → `verifyOwnershipIfNeeded` → `connector.verifyOwnership`). But that proof is **not persisted onto the SDK's session record**: `ReownAppKitLiveClient.connectorSession(from:)` and `LiveCoinbaseWalletSDKClient.session(from:)` both build `WalletConnectorSession` with the default `addressVerified == false`. On the next launch, `restoreSavedSessions` reads live sessions from `connector.sessions()` (still `addressVerified == false`) and, under the default `.requireVerified` policy, routes them to `unverifiedSessionTopics` — **not upserted, not made active**. It also never *re-verifies*; it only trusts the persisted flag, which for SDK connectors is always false. Net effect: a Reown/Coinbase user appears disconnected after every cold launch until the host manually re-runs `verifyOwnership` and re-persists — and no lifecycle API guides that. The custom IRN transport is unaffected because it re-persists `addressVerified == true` into its own restorable record. Test `lifecycleStrictRestoreLeavesUnverifiedSessionsInactive` locks in this behavior, so it is intentional at the unit level, but the product consequence for the two `productionReady` adapters is not addressed.
- **Root cause:** `addressVerified` lives on the session record, but SDK vendor stores (outside this package) do not carry it, and `restoreSavedSessions` has no re-verification path for connectors whose stores can't persist the flag.
- **Fix:** Not fixed (report-only). Options: (a) add a re-verify-on-restore path for connectors flagged as SDK-backed; (b) persist an `addressVerified` marker in the kit's own topic/state store keyed by topic and merge it onto restored SDK sessions; (c) document that `.requireVerified` + SDK connectors requires the host to re-verify from `unverifiedSessionTopics` on launch, and surface that as a first-class step.
- **Sources used to verify:** `code:Sources/WalletConnectorKit/Services/WalletConnectionLifecycleService.swift:124-160` (restore guard), `code:Sources/WalletConnectorKitReownAdapter/ReownAppKitLiveClient.swift:194-211` (no `addressVerified`), `code:Sources/WalletConnectorKitCoinbaseAdapter/LiveCoinbaseWalletSDKClient.swift:163-181` (no `addressVerified`); `test:WalletConnectionCoreTests/lifecycleStrictRestoreLeavesUnverifiedSessionsInactive`.
- **Could not fully resolve because:** Report-only; no live SDK/device to confirm the end-to-end relaunch UX.
- **Follow-up / owner:** Wallet lifecycle owner; decide whether Reown/Coinbase ship with automatic restore or a documented host re-verify step.
- **Signed:** Opus 4.8

---

### AUD-016 — WidgetRenderer_Default simulator watchdog is not a WalletConnectorKit ship blocker
- **Status:** 🔵 Verified-OK
- **Type:** Triage
- **Severity:** Low
- **Area:** Runtime / Simulator
- **Found by:** User-provided crash report, triaged by Codex GPT-5 on 2026-08-04
- **Description:** The crash report is for Apple's `com.apple.chrono.WidgetRenderer-Default` process, killed by FRONTBOARD `0x8BADF00D` during `scene-create` after a 10-second watchdog. The crashing stack is RenderBox/Metal/QuartzCore in the simulator renderer, not an Auralis or WalletConnectorKit binary stack.
- **Root cause:** Not established from package code. The report points to simulator WidgetRenderer scene creation and Metal pipeline compilation/rendering work. WalletConnectorKit is a Swift package with wallet domain, persistence, transport, and adapter targets; it has no WidgetKit extension, SwiftUI rendering surface, or Metal/RenderBox call path.
- **Fix:** No WalletConnectorKit code change. Treat as simulator/OS/widget-renderer triage unless the host app can produce a reproducible widget input tied to this package.
- **Sources used to verify:** User crash report process/bundle `WidgetRenderer_Default`, termination `scene-create watchdog transgression`, thread stack `RenderBox`/`Metal`; project file list contains only WalletConnectorKit package sources/tests, no WidgetKit target; SRC-18, SRC-19.
- **Could not fully resolve because:** The report does not include host app/widget source or a reproducible render case.
- **Follow-up / owner:** Host app UI/widget owner only if reproducible outside the simulator renderer process.
- **Signed:** Codex GPT-5

---

### AUD-015R — Partial provider adapter wrappers no longer claim production readiness
- **Status:** ✅ Resolved
- **Type:** Gap / Blocker
- **Severity:** High
- **Area:** Adapter:MetaMask / Adapter:Privy / Adapter:Dynamic
- **Found by:** Codex GPT-5 on 2026-08-04
- **Description:** AUD-015 was real in the configured-client case. The shipped unconfigured stubs already returned `.unavailable`, but a configured MetaMask/Privy/Dynamic client still made wrappers report `.productionReady` while the wrapper protocols did not delegate sessions, callbacks, events, or ownership semantics.
- **Root cause:** Readiness treated `isConfigured == true` as a complete connector lifecycle, even though these adapter protocols only cover connect/request/disconnect.
- **Fix:** Configured MetaMask, Privy, and Dynamic wrappers now report `.experimental(...)`, so `readiness.allowsProductionUse` remains false until their full lifecycle surface is implemented. Unconfigured stubs still report `.unavailable`.
- **Sources used to verify:** `code:Sources/WalletConnectorKitMetaMaskAdapter/MetaMaskWalletConnector.swift:33-36`, `code:Sources/WalletConnectorKitPrivyAdapter/PrivyWalletConnector.swift:33-36`, `code:Sources/WalletConnectorKitDynamicAdapter/DynamicWalletConnector.swift:33-36`, `test:StubAdapterReadinessTests/configuredPartialProviderAdaptersRemainExperimental`, SRC-18, SRC-19.
- **Could not fully resolve because:** No live MetaMask/Privy/Dynamic SDK implementation is linked in this package; this closes the misleading production routing but not future provider integration work.
- **Follow-up / owner:** Provider integration owner; expand the SDK-client protocols before changing these adapters to `.productionReady`.
- **Signed:** Codex GPT-5

---

### AUD-014R — Reown and Coinbase EVM ownership challenges share canonical SIWE
- **Status:** ✅ Resolved
- **Type:** Hardening / Spec-conformance
- **Severity:** High
- **Area:** Adapter:Reown / Adapter:Coinbase / Crypto
- **Found by:** Codex GPT-5 on 2026-08-04
- **Description:** AUD-014 was real. Reown and Coinbase proved key control for a one-off string, but the signed text did not bind the relying app domain, URI, displayed address, or chain id the way the custom IRN connector did.
- **Root cause:** Challenge construction lived in adapter-local helpers and drifted from the canonical EIP-4361 message shape.
- **Fix:** Added shared `WalletOwnershipChallengeMessageBuilder` and routed the custom IRN connector, Reown adapter, and Coinbase adapter through it for EVM SIWE messages. Reown also uses the shared Solana challenge builder for Solana verification. Reown/Coinbase initializers now accept `WalletConnectionMetadata` so host composition can bind challenges to the real app URL.
- **Sources used to verify:** `code:Sources/WalletConnectorKit/Crypto/WalletConnectorCryptoProvider.swift:56-111`, `code:Sources/WalletConnectorKit/Transport/WalletConnectDAppConnector.swift:229-280`, `code:Sources/WalletConnectorKitReownAdapter/ReownWalletConnector.swift:88-128`, `code:Sources/WalletConnectorKitCoinbaseAdapter/CoinbaseWalletConnector.swift:80-89`, `test:ReownAdapterTests/reownWalletConnectorVerifiesOwnershipThroughPersonalSign`, `test:ReownAdapterTests/coinbaseWalletConnectorVerifiesOwnershipThroughClientRequest`, SRC-12, SRC-18, SRC-19.
- **Could not fully resolve because:** Host apps still need to inject their real `WalletConnectionMetadata` and a recovery-capable secp256k1 crypto provider for EVM verification.
- **Follow-up / owner:** Host app composition owner; pass production metadata into Reown/Coinbase connectors.
- **Signed:** Codex GPT-5

---

### AUD-013R — Same-address multi-chain session cleanup is chain-scoped
- **Status:** ✅ Resolved
- **Type:** Defect / Blocker
- **Severity:** High
- **Area:** Services / Persistence
- **Found by:** Codex GPT-5 on 2026-08-04
- **Description:** AUD-013 was real. Account persistence is chain-scoped, but the session-topic index was address-scoped; a same-address EVM session across Ethereum and Base could overwrite the topic record and later deactivate only one stale account.
- **Root cause:** `WalletSessionTopicStoring` keyed records by bare address while `WalletConnectionLifecycleService` persisted and deactivated `(address, chain)` records.
- **Fix:** `WalletSessionTopicStoring` now supports chain-aware save/load/delete, and the keychain/in-memory stores key new records by CAIP-2 chain plus address while preserving legacy bare-address reads. Lifecycle restore filters live sessions by stored chain, deletes the exact stale topic record, and deactivates the chain associated with that record.
- **Sources used to verify:** `code:Sources/WalletConnectorKit/Persistence/KeychainSessionTopicStore.swift:48-99`, `code:Sources/WalletConnectorKit/Persistence/KeychainSessionTopicStore.swift:141-292`, `code:Sources/WalletConnectorKit/Services/WalletConnectionLifecycleService.swift:97-153`, `test:WalletConnectionCoreTests/lifecycleCleanupDeactivatesEveryStaleSameAddressEVMChain`, `test:WalletConnectDeepLinkTests/keychainSessionTopicStorePersistsRealRecords`, SRC-18, SRC-19.
- **Could not fully resolve because:** Real-keychain integration tests were skipped on this runner by their existing environment gate; the in-memory regression and full package test plan passed.
- **Follow-up / owner:** No blocker remains for package ship-readiness.
- **Signed:** Codex GPT-5

---

### AUD-015 — Stub adapter wrappers can claim production readiness without full connector semantics
- **Status:** 🔴 Open
- **Type:** Gap / Blocker
- **Severity:** High
- **Area:** Adapter:MetaMask / Adapter:Privy / Adapter:Dynamic
- **Found by:** Codex GPT-5 on 2026-08-04
- **Description:** The MetaMask, Privy, and Dynamic adapter protocols only require `connect`, `request`, and `disconnect`, plus `isConfigured`. When `isConfigured == true`, the wrapper reports `.productionReady`, but the wrapper-owned `handleCallback` is a no-op, `sessions()` always returns `[]`, and the event stream is permanently finished. A future injected live client can therefore be marked production-ready while lifecycle restore, callback routing, session enumeration, and ownership-policy restore cannot work through the connector contract.
- **Root cause:** The shipped adapters are stubs, but the wrapper readiness model treats any configured client as complete even though the protocol does not include the complete `WalletConnector` surface.
- **Fix:** Not fixed in this audit. Before shipping these providers, either keep them unavailable/experimental until the protocols delegate callback/session/event/ownership behavior, or expand each SDK-client protocol to cover the full connector lifecycle and verify it with tests/on-device QA.
- **Sources used to verify:** `code:Sources/WalletConnectorKitMetaMaskAdapter/MetaMaskWalletConnector.swift:33-44`, `code:Sources/WalletConnectorKitPrivyAdapter/PrivyWalletConnector.swift:33-44`, `code:Sources/WalletConnectorKitDynamicAdapter/DynamicWalletConnector.swift:33-44`, `test:StubAdapterReadinessTests/configuredClientIsProductionReady`, SRC-16, SRC-17.
- **Could not fully resolve because:** No live MetaMask/Privy/Dynamic SDK implementation is linked in this package, so only the wrapper contract could be audited here.
- **Follow-up / owner:** Provider integration owner; block production routing for these adapters until the lifecycle surface is real.
- **Signed:** Codex GPT-5

---

### AUD-014 — Reown and Coinbase ownership challenges are not canonical SIWE/domain-bound
- **Status:** 🔴 Open
- **Type:** Hardening / Spec-conformance
- **Severity:** High
- **Area:** Adapter:Reown / Adapter:Coinbase
- **Found by:** Codex GPT-5 on 2026-08-04
- **Description:** `WalletConnectDAppConnector.verifyOwnership` builds a canonical EIP-4361 message containing domain, address, URI, version, chain id, nonce, issued-at, and expiration. The Reown and Coinbase adapter implementations instead sign only the caller statement, a random nonce, and expiration. Signature recovery still proves control of the expected address for that one challenge, but the signed text is not bound to the relying app domain, URI, chain id, or displayed account, and the tests only assert the method/address params, not SIWE message shape.
- **Root cause:** Adapter-specific `ownershipChallengeMessage` helpers drifted from the custom connector's canonical SIWE builder instead of sharing one challenge-construction path.
- **Fix:** Not fixed in this audit. Share the canonical SIWE builder across EVM connectors, add adapter tests that decode the `personal_sign` payload and assert domain/address/URI/chain/nonce/issued-at/expiration, and keep Solana on its explicit Solana challenge shape.
- **Sources used to verify:** `code:Sources/WalletConnectorKit/Transport/WalletConnectDAppConnector.swift:228-318`, `code:Sources/WalletConnectorKitReownAdapter/ReownWalletConnector.swift:85-130`, `code:Sources/WalletConnectorKitCoinbaseAdapter/CoinbaseWalletConnector.swift:77-107`, `test:WalletConnectSignEngineTests/ownershipChallengeIsSIWE`, `test:WalletConnectorKitTests/reownWalletConnectorVerifiesOwnershipThroughPersonalSign`, `test:WalletConnectorKitTests/coinbaseWalletConnectorVerifiesOwnershipThroughClientRequest`, SRC-12, SRC-16, SRC-17.
- **Could not fully resolve because:** This audit was report-only by request.
- **Follow-up / owner:** Wallet security owner; treat as blocking if Reown/Coinbase verified addresses authorize sensitive flows.
- **Signed:** Codex GPT-5

---

### AUD-013 — Same-address multi-chain sessions can leave stale active accounts after restore cleanup
- **Status:** 🔴 Open
- **Type:** Defect / Blocker
- **Severity:** High
- **Area:** Services / Persistence
- **Found by:** Codex GPT-5 on 2026-08-04
- **Description:** `WalletConnectionLifecycleService.persistApprovedSession` upserts every extracted `(address, chain)` pair, but `WalletSessionTopicStoring` persists topics by bare wallet address. A normal EVM wallet can expose the same address on several proposed chains (`eip155:1`, `eip155:137`, `eip155:8453`, etc.). Each save for that address overwrites the previous topic record's chain label. Later, when restore finds the topic stale/expired, it deletes one topic record and deactivates only one chain, leaving the other previously-upserted chains active without a live session/topic. The existing tests cover one non-mainnet chain, but not the same-address multi-chain case.
- **Root cause:** Account persistence is chain-scoped, while the topic index and stale-cleanup loop are address-scoped. The fallback cleanup chooses one `WalletChain` per saved topic record.
- **Fix:** Not fixed in this audit. Store topic records by `(address, chain)` or store all chains per address, then make stale restore/remove deactivate every chain originally persisted for that session/address.
- **Sources used to verify:** `code:Sources/WalletConnectorKit/Domain/SessionAddressExtractor.swift:41-55`, `code:Sources/WalletConnectorKit/Services/WalletConnectionLifecycleService.swift:93-103`, `code:Sources/WalletConnectorKit/Services/WalletConnectionLifecycleService.swift:134-141`, `code:Sources/WalletConnectorKit/Persistence/KeychainSessionTopicStore.swift:61-82`, `code:Sources/WalletConnectorKit/Persistence/KeychainSessionTopicStore.swift:92-118`, `test:WalletConnectorKitTests/lifecyclePersistsChainForStaleNonMainnetEVMTopics`, SRC-16, SRC-17.
- **Could not fully resolve because:** This audit was report-only by request; `RunCodeSnippet` could not complete a local fake reproduction before timeout, but the source-level state mismatch is direct.
- **Follow-up / owner:** Wallet lifecycle owner; add a regression test for one EVM address on two EIP-155 chains before fixing.
- **Signed:** Codex GPT-5

---

### AUD-012 — Test suite is adversarial and specification-anchored (quality review)
- **Status:** 🔵 Verified-OK
- **Type:** Gap (coverage quality)
- **Severity:** Medium
- **Area:** Tests
- **Found by:** Opus 4.8 on 2026-08-04
- **Description:** Reviewed the security-critical suites for *logic*, not just pass/fail. They are
  genuinely adversarial rather than happy-path: a mock wallet that **forges a response on the pairing
  topic** before the legit one and asserts the forgery is dropped; a wallet that **re-settles with a
  different account** and asserts the account set is not swapped; **ChaCha20-Poly1305 tamper detection**;
  **reown parity vectors** for X25519+HKDF and envelopes; **recovery-id-agnostic** EVM verification with
  two stub providers (0/1 and 27/28); Solana wrong-message/wrong-key/short-signature negatives;
  fail-fast-on-disconnect; concurrent-restore race; keepalive dead-peer; SIWE message-shape assertions.
  Mocks encrypt/decrypt with the real crypto, so they exercise the true wire path.
- **Root cause:** n/a
- **Fix:** None needed.
- **Sources used to verify:** `test:WalletCrossSessionResponseTests` (forged-response + re-settle),
  `test:WalletConnectV2CryptoTests` (parity vectors + tamper), `test:WalletMultiChainOwnershipTests`
  (recovery-id + Solana negatives), `test:WalletConnectSignEngineTests` (handshake, SIWE, fail-fast,
  concurrent restore, ping timeout); SRC-11.
- **Could not fully resolve because:** Not every suite was read line-by-line — `WalletReviewFixesTests`,
  `WalletShipHardeningTests`, `WalletTransportHardeningTests`, `WalletConnectSessionRestoreTests`,
  `WalletConnectorRegistryTests`, and `WalletConnectorKitTests` were confirmed present and green (SRC-11)
  but their internal assertions were not individually audited this pass.
- **Follow-up / owner:** No live end-to-end integration test against a real relay exists (by design —
  all relay tests use in-process mock sockets). A future pass could add one gated environment test.
- **Signed:** Opus 4.8

---

### AUD-011 — DApp connector SIWE ownership flow fails closed and binds the challenge
- **Status:** 🔵 Verified-OK
- **Type:** Spec-conformance
- **Severity:** Critical
- **Area:** Transport (public entry point)
- **Found by:** Opus 4.8 on 2026-08-04
- **Description:** `WalletConnectDAppConnector.verifyOwnership` issues a canonical EIP-4361 SIWE
  `personal_sign` challenge (EVM) or an ed25519 `solana_signMessage` challenge (Solana), binding the app
  domain, URI, chain id, a 16-byte `SecRandomCopyBytes` nonce, and an issued-at/expiration window so a
  captured signature cannot be replayed cross-domain or after expiry. EVM verification **throws** if no
  secp256k1-capable `cryptoProvider` was injected (never reports false success). The connector also gates
  the pairing URI on `isCanonicalV2` before it can drive key derivation, and defaults its return-URL
  handler to one **scoped to the app's own scheme/host** ([[LIM-4]] mitigation). `WalletEthereumSignature(hexSignature:)`
  requires exactly 65 bytes and a valid `v`, failing closed otherwise.
- **Root cause:** n/a
- **Fix:** None needed.
- **Sources used to verify:** `code:Transport/WalletConnectDAppConnector.swift:86-89` (URI gate),
  `:215-257` (EVM fail-closed), `:292-319` (SIWE message), `:414-441` (signature parse); SRC-12, SRC-13;
  `test:WalletConnectSignEngineTests` "verifyOwnership issues a canonical EIP-4361 SIWE challenge".
- **Could not fully resolve because:** n/a
- **Follow-up / owner:** Depends on the host injecting a real secp256k1 provider (the default
  `DefaultWalletConnectorCryptoProvider` cannot recover — see [[AUD-010]]).
- **Signed:** Opus 4.8

---

### AUD-010 — Ownership verifiers fail closed (EVM secp256k1 + Solana ed25519)
- **Status:** 🔵 Verified-OK
- **Type:** Hardening
- **Severity:** Critical (a false positive here trusts an address the user does not control)
- **Area:** Crypto / Domain
- **Found by:** Opus 4.8 on 2026-08-04
- **Description:** `WalletOwnershipVerifier.verifyPersonalSign` recovers over the EIP-191 digest, tries
  **both** recovery-id conventions (27/28 and 0/1) so a provider mismatch cannot cause a false negative,
  and **rethrows** if every recovery attempt fails (e.g. no recovery-capable provider) rather than
  returning `false` — and the shipped `DefaultWalletConnectorCryptoProvider.recoverPublicKey` throws, so
  EVM ownership cannot be spoofed as "verified" without a real secp256k1 provider. Recovered keys are
  length-checked (64 or 65-with-0x04) before the keccak256→last-20-bytes address derivation.
  `WalletSolanaOwnershipVerifier` is self-contained ed25519 (a Solana address *is* its public key):
  it requires a 64-byte signature and 32-byte decoded key and uses CryptoKit `isValidSignature`. The
  bundled `EthereumKeccak256` is a from-scratch Keccak-f[1600] (comment claims it is audited against
  standard vectors).
- **Root cause:** n/a
- **Fix:** None needed.
- **Sources used to verify:** `code:Crypto/WalletConnectorCryptoProvider.swift:44-48` (default throws),
  `:83-149` (EVM verify + address match), `:157-221` (Solana verify/parse/challenge); SRC-13, SRC-15;
  `test:WalletMultiChainOwnershipTests` (recovery-id agnostic, rethrow-without-provider, Solana negatives).
- **Could not fully resolve because:** The `EthereumKeccak256` "audited against standard vectors" claim
  was **not** independently re-verified this pass; it is exercised indirectly via the SIWE/address tests.
  A future pass should add/confirm explicit NIST/Ethereum Keccak-256 KATs.
- **Follow-up / owner:** —
- **Signed:** Opus 4.8

---

### AUD-009 — IRN relay socket: coalesced connect, backoff reconnect, bounded caches
- **Status:** 🔵 Verified-OK
- **Type:** Hardening
- **Severity:** High
- **Area:** Transport (relay socket)
- **Found by:** Opus 4.8 on 2026-08-04
- **Description:** `WalletConnectIRNRelayClient` refuses a non-`wss` relay and an empty projectID before
  connecting; coalesces concurrent `connect()` into one in-flight socket (actor re-entrancy guard);
  reconnects on drop with capped exponential backoff **plus full jitter** (anti–thundering-herd) and
  re-subscribes retained topics; times out un-acked requests; buffers acks that beat their waiter and
  **bounds** that buffer (256) oldest-first; decodes relay acks as `WalletJSONValue` so subscribe (id
  string) / fetch (object) / publish (bool) shapes are all recognized; replays `irn_fetchMessages`
  mailbox onto the event stream (dedup downstream makes redelivery safe); paginates fetch with a 20-page
  ceiling. Relay RPC ids are millis×1e6+entropy, clamped monotonic against clock rollback.
- **Root cause:** n/a
- **Fix:** None needed.
- **Sources used to verify:** `code:Transport/WalletConnectIRNRelayClient.swift:160-253` (connect/
  reconnect/backoff), `:255-311` (subscribe/recover/fetch), `:363-413` (ack wait/timeout), `:442-524`
  (incoming routing + fetch replay); SRC-14; SRC-11 (test "Messages in an irn_fetchMessages ack are
  replayed", "Concurrent connect() calls open exactly one socket").
- **Could not fully resolve because:** n/a
- **Follow-up / owner:** —
- **Signed:** Opus 4.8

---

### AUD-008 — Session-state store fails closed and never clobbers hidden state
- **Status:** 🔵 Verified-OK
- **Type:** Hardening
- **Severity:** High
- **Area:** Persistence
- **Found by:** Opus 4.8 on 2026-08-04
- **Description:** `KeychainWalletConnectSessionStateStore` keeps all sessions in one device-local,
  non-syncing, unlocked-only generic-password blob. Its `LoadOutcome` distinguishes
  `records/notFound/corrupt/unreadable`: a **read-modify-write refuses to proceed when the record is
  unreadable** (locked / missing entitlement) so a blind write can never wipe the sessions it simply
  could not see; corrupt JSON is purged as already-lost; a degradation callback surfaces the OSStatus so
  a "looks persisted but wasn't" state is not silent.
- **Root cause:** n/a
- **Fix:** None needed.
- **Sources used to verify:** `code:Persistence/WalletConnectSessionStateStore.swift:172-237`
  (save/delete guards), `:270-289` (load outcome classification); SRC-9.
- **Could not fully resolve because:** n/a
- **Follow-up / owner:** See [[LIM-5]] (read-modify-write only atomic within one actor instance).
- **Signed:** Opus 4.8

---

### AUD-007 — Adapters gate production use behind `isConfigured`; no silent routing
- **Status:** 🔵 Verified-OK
- **Type:** Hardening
- **Severity:** High
- **Area:** Adapters
- **Found by:** Opus 4.8 on 2026-08-04
- **Description:** All six adapters (Coinbase, MetaMask, Reown, Privy, Dynamic, Solana) follow one safe
  shape: a `…SDKClient` protocol whose shipped `Unconfigured…` stub sets `isConfigured = false`, so the
  connector reports `.unavailable` (Solana: `.experimental`, request-only) and composition never routes
  production traffic through an unlinked SDK. Adapters are thin pass-throughs to the injected client;
  Coinbase/Reown add SIWE/ed25519 `verifyOwnership` reusing the shared verifiers. The live Reown client
  re-runs `WalletRequestValidation` + `WalletSessionGrantValidator` before submitting, correlates the
  response by the **SDK's own wire id** (the caller id never travels), and routes an error response to
  `fail` (not `resolve`), so an error is never surfaced as a successful result.
- **Root cause:** n/a
- **Fix:** None needed.
- **Sources used to verify:** `code:…CoinbaseAdapter/CoinbaseWalletConnector.swift`,
  `…MetaMaskAdapter/MetaMaskWalletConnector.swift`, `…SolanaAdapter/SolanaWalletConnector.swift`,
  `…ReownAdapter/ReownWalletConnector.swift` + `ReownAppKitLiveClient.swift:83-161`; SRC-6;
  `test:WalletConnectSignEngineTests` suite "Stub adapter readiness".
- **Could not fully resolve because:** The **live vendor SDK paths cannot execute in this environment**
  (no linked Coinbase/Reown/MetaMask/Privy/Dynamic SDK, no device). Only the adapter-boundary logic and
  the `Unconfigured…`/stub paths were verifiable; real SDK behavior (deep-link round-trips, actual
  signatures) needs on-device manual QA — see `WalletConnectorKit-QA-Checklist.md`.
- **Follow-up / owner:** On-device QA of each live adapter before shipping that provider.
- **Signed:** Opus 4.8

---

### AUD-006 — Grant validator binds signer-address checks per method
- **Status:** 🔵 Verified-OK
- **Type:** Spec-conformance
- **Severity:** High (a gap here would let a session sign for an address it was not granted)
- **Area:** Requests
- **Found by:** Opus 4.8 on 2026-08-04
- **Description:** `WalletSessionGrantValidator` gates every request on (a) a namespace/chain grant,
  (b) the method being granted, and (c) — where the method carries a signer — that the signer address
  is one of the session's granted accounts. `eth_sendTransaction` reads `from`; `personal_sign` /
  `solana_signMessage` read the address param; typed-data reads param[0]. `wallet_switchEthereumChain`
  additionally checks the target chain is granted.
- **Root cause:** n/a — audited as correct.
- **Fix:** None needed.
- **Sources used to verify:** `code:Requests/WalletSessionGrantValidator.swift:12-86`; SRC-6 (EIP-155
  signer params); SRC-11 (tests: "A request using an ungranted method/chain is rejected before
  publish", "A chain switch to an ungranted target chain is rejected before publish").
- **Could not fully resolve because:** n/a
- **Follow-up / owner:** When new signing methods are added, confirm `signerAddress(in:)` is extended
  so the ownership gate is not silently skipped (methods currently returning `nil` bypass the check by
  design — e.g. `wallet_watchAsset`).
- **Signed:** Opus 4.8

---

### AUD-005 — Keychain storage attributes are device-local and non-syncing
- **Status:** 🔵 Verified-OK
- **Type:** Hardening
- **Severity:** High
- **Area:** Persistence
- **Found by:** Opus 4.8 on 2026-08-04
- **Description:** Both the session/topic store and the relay-identity keychain use
  `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and `kSecAttrSynchronizable = false`, so session key
  material and topics are readable only while unlocked and never sync to iCloud Keychain. macOS also
  sets `kSecUseDataProtectionKeychain`. Symmetric session keys are persisted (needed for cross-launch
  restore), which is the reference design; their exposure is bounded by these attributes.
- **Root cause:** n/a
- **Fix:** None needed.
- **Sources used to verify:** `code:Persistence/KeychainSessionTopicStore.swift:221-255`;
  `code:Crypto/WalletConnectRelayAuth.swift:191-238`; SRC-9.
- **Could not fully resolve because:** n/a
- **Follow-up / owner:** See [[LIM-3]] (keychain-unavailable fallback).
- **Signed:** Opus 4.8

---

### AUD-004 — Inbound envelope authenticity does not rely on topic secrecy
- **Status:** 🔵 Verified-OK
- **Type:** Hardening
- **Severity:** Critical
- **Area:** Transport
- **Found by:** Opus 4.8 on 2026-08-04
- **Description:** The Sign engine defends the handshake against several injection classes: a type1
  (key-carrying) envelope is accepted **only** on a pairing topic with a live pending proposal (never
  on an established session), settle is bound to the derived session topic (a settle forged on the
  cleartext pairing topic is rejected), a request response is accepted only on the same topic its wire
  id was published on (blocks cross-session id-guessing), and the envelope sender key must match the
  body `responderPublicKey`. Inbound messages are deduped on decrypted identity (not ciphertext) so
  relay redelivery and peer re-sends both fire side effects once.
- **Root cause:** n/a
- **Fix:** None needed.
- **Sources used to verify:** `code:Transport/WalletConnectIRNTransportClient.swift:651-706`
  (envelope routing), `:968-986` (settle topic binding), `:1060-1077` (response topic binding),
  `:1494-1497` (sender/responder match); SRC-1, SRC-3; SRC-11 (tests: "A settle forged on the pairing
  topic is rejected", "A response forged on a different topic is ignored…", "A redelivered settle
  produces only one sessionApproved event").
- **Could not fully resolve because:** n/a
- **Follow-up / owner:** Peer-supplied provider name/metadata is trusted as a display fallback only
  (`:1030`); confirm no security decision keys off it.
- **Signed:** Opus 4.8

---

### AUD-003 — Peer-supplied expiries and accounts are clamped/scoped
- **Status:** 🔵 Verified-OK
- **Type:** Hardening
- **Severity:** High
- **Area:** Transport
- **Found by:** Opus 4.8 on 2026-08-04
- **Description:** A settle/extend expiry is clamped to the 7-day protocol cap so a peer cannot keep
  key material or a subscription alive indefinitely; an already-expired settle is rejected. Settled
  and updated accounts are scoped to the chains the dApp actually proposed (`allowedChains`), dropping
  accounts on unrequested chains; required namespaces (methods/events/chains) must be satisfied or the
  session is rejected/deleted. Chain-keyed namespace maps (`eip155:1`) are normalized to bare
  namespaces so a CAIP-25-shaped settle stays signable.
- **Root cause:** n/a
- **Fix:** None needed.
- **Sources used to verify:** `code:Transport/WalletConnectIRNTransportClient.swift:96-99`
  (`maxSessionLifetime`), `:988-1026` (settle clamp + scope), `:1330-1479` (required-namespace +
  scoping helpers); SRC-1, SRC-4; SRC-11 (tests: "A settle granting an unproposed chain drops that
  account", "A wc_sessionExtend beyond the 7-day cap is ignored", "A chain-indexed settle (eip155:1)
  normalizes to a signable session").
- **Could not fully resolve because:** n/a
- **Follow-up / owner:** —
- **Signed:** Opus 4.8

---

### AUD-002 — Relay auth DID-JWT construction matches the spec
- **Status:** 🔵 Verified-OK
- **Type:** Spec-conformance
- **Severity:** High
- **Area:** Crypto
- **Found by:** Opus 4.8 on 2026-08-04
- **Description:** `WalletConnectRelayAuth` builds the Ed25519 `client_auth` DID-JWT the IRN relay
  requires: header `{alg:EdDSA, typ:JWT}`, `iss = did:key:z<base58btc(0xed01 ‖ pubkey)>`, `aud = relay
  URL`, `act = client_auth`, base64url with padding stripped. A 60s backdate on `iat` absorbs device
  clock skew. `randomSubject()` fails loudly (throws) if `SecRandomCopyBytes` does not succeed, rather
  than emitting a predictable all-zero subject.
- **Root cause:** n/a
- **Fix:** None needed.
- **Sources used to verify:** `code:Crypto/WalletConnectRelayAuth.swift:35-84`,
  `:253-291` (base58btc encoder, ported from reown `Base58.swift`); SRC-2, SRC-7, SRC-8.
- **Could not fully resolve because:** n/a
- **Follow-up / owner:** See [[LIM-1]] (fresh random `sub` per token vs reference's persisted `sub`).
- **Signed:** Opus 4.8

---

### AUD-001 — Core v2 crypto primitives match the reference envelope/key scheme
- **Status:** 🔵 Verified-OK
- **Type:** Spec-conformance
- **Severity:** Critical
- **Area:** Crypto
- **Found by:** Opus 4.8 on 2026-08-04
- **Description:** `WalletConnectV2Crypto` implements the v2 KMS primitives with CryptoKit: X25519 ECDH
  → HKDF-SHA256 (empty salt, empty info, 32-byte output) for the shared symmetric key; ChaCha20-Poly1305
  `combined` sealbox (`nonce(12) ‖ ciphertext ‖ tag(16)`); topic = lowercase hex of `SHA256(symKey)`.
  Envelope type0 (`0x00 ‖ sealbox`) and type1 (`0x01 ‖ senderPubKey(32) ‖ sealbox`) parse/serialize
  with correct length guards (type1 rejects `< 33` bytes). `randomBytes` fails loudly on RNG error so a
  predictable zero key can never be produced.
- **Root cause:** n/a
- **Fix:** None needed.
- **Sources used to verify:** `code:Crypto/WalletConnectV2Crypto.swift:40-157`; SRC-3, SRC-8;
  SRC-11 (suite "WalletConnect v2 Sign engine", "Full handshake settles a session and answers a
  request").
- **Could not fully resolve because:** n/a
- **Follow-up / owner:** —
- **Signed:** Opus 4.8

---

## 4. Cross-Session Completeness Checklist

Track coverage so no area is silently skipped across sessions/models. Mark the last model + date that
verified each area, and link the governing entries.

| Area | Last verified by | Date | Verdict | Entries |
|------|------------------|------|---------|---------|
| Crypto (relay auth, v2 crypto) | Opus 4.8 (session P) | 2026-08-07 | 🔵 OK (re-verified, component A) | AUD-001, AUD-002, AUD-044 |
| Crypto — ownership verifiers (secp256k1 / ed25519 / keccak) | Opus 4.8 (session P) | 2026-08-07 | 🔵 OK (re-verified, component A) | AUD-010, AUD-044 |
| Transport — Sign engine + URI | Opus 4.8 | 2026-08-04 | 🔵 OK | AUD-003, AUD-004 |
| Transport — relay/IRN socket, sign-protocol tags, relay config | Opus 4.8 | 2026-08-04 | 🔵 OK | AUD-009 |
| Transport — DApp connector (SIWE), return-URL/inbound-URL, deep link | Opus 4.8 | 2026-08-04 | 🔵 OK | AUD-011 |
| Transport — JSON-RPC, boundaries, lifecycle service | Opus 4.8 (session P) | 2026-08-07 | 🔵 OK (B-1 disconnect delete-drop fixed) | AUD-013, AUD-043 |
| Persistence (Keychain topic store, relay identity) | Opus 4.8 (session P) | 2026-08-07 | 🔵 OK (component C re-verified; multi-chain cleanup nuance still tracked in AUD-013) | AUD-005, AUD-013, AUD-044 |
| Persistence (WalletConnectSessionStateStore) | Opus 4.8 | 2026-08-04 | 🔵 OK | AUD-008 |
| Persistence (ActiveWalletStore, WalletSessionStore) | Codex GPT-5 | 2026-08-04 | 🟡 Skimmed; no secret-storage blocker found, but active wallet is address-only | AUD-013 |
| Requests (grant validator) | Opus 4.8 (session P) | 2026-08-07 | 🔵 OK (re-verified, component D) | AUD-006, AUD-044 |
| Requests (pending store, JSON value) | Codex GPT-5 | 2026-08-04 | 🔵 OK | AUD-007 (Reown store), SRC-17 |
| Requests (WalletOperation, WalletRequest builders/validation) | Codex GPT-5 | 2026-08-04 | 🟡 No compile/test blocker; adapter SIWE challenge coverage gap remains | AUD-014 |
| Domain (address extraction, namespaces, accounts) | Opus 4.8 (session P) | 2026-08-07 | 🔵 OK (E-1 restore ownership-trust seam fixed) | AUD-004, AUD-013, AUD-042 |
| Registry / Catalog | Codex GPT-5 | 2026-08-04 | 🟡 Catalog is descriptive; production routing must honor readiness and support status | AUD-015 |
| Adapters — boundary logic + stub gating | Codex GPT-5 | 2026-08-04 | 🔴 Some wrappers can report production-ready while omitting callback/session/event semantics | AUD-007, AUD-015 |
| Adapters — **live vendor SDK paths** (device) | Codex GPT-5 | 2026-08-04 | ⛔ Blocked (no SDK/device in env); Reown/Coinbase challenge shape gap found by code review | AUD-007, AUD-014, AUD-015 |
| Tests coverage & quality | Opus 4.8 | 2026-08-04 | 🔵 OK (adversarial, spec-anchored) | AUD-012, SRC-11 |

---

## 5. Known Limitations & Deliberate Non-Fixes

Things intentionally left as-is. Recording these prevents future sessions from "re-fixing" or flagging
them as regressions.

| ID | Item | Reason left as-is | Revisit when | Signed |
|----|------|-------------------|--------------|--------|
| LIM-1 | Relay JWT mints a **fresh random `sub` per token** instead of persisting one like reown | Harmless for relay auth — the relay derives `client_id` from `iss` (the persisted Ed25519 identity key), not `sub`. Documented in `WalletConnectRelayAuth.swift:29-32`. | The relay ever begins keying rate-limits/analytics on `sub` stability | Opus 4.8 |
| LIM-2 | `WalletConnectURI.init?(absoluteString:)` accepts short/even-length hex keys and an unconstrained topic (no 32-byte enforcement) | Keeps the value type round-trippable for test fixtures. Externally-sourced URIs must use `init?(externalScannedString:)`, which gates on `isCanonicalV2` (64-hex topic + 64-hex symKey) before pairing. Documented at `WalletConnectURI.swift:96-111`. | A caller ingests an external URI via the lenient initializer — that would be the bug, not this. | Opus 4.8 |
| LIM-3 | Relay identity key falls back to an **in-memory** key when the keychain is unavailable (e.g. missing entitlement on a test host, `errSecMissingEntitlement`) | Prevents relay auth from hard-failing; only cross-launch `client_id` stability is lost, and the fallback never clobbers a real persisted record. Documented at `WalletConnectRelayAuth.swift:96-152`. | Seen firing in production (not just test hosts) — would indicate a real entitlement/provisioning gap. | Opus 4.8 |
| LIM-4 | `WalletReturnURLHandler`'s default allow-list is `nil` = **accept any scheme/host** | The public entry point (`WalletConnectDAppConnector`) already **defaults to a scoped handler** derived from the app's redirect scheme + callback host, so untrusted inbound URLs are origin-checked in practice. The permissive default only applies if a caller constructs the handler directly and passes nothing. Documented at `WalletReturnURLHandler.swift:8-24`. | A new caller wires the handler directly without scoping — audit that path if one appears. | Opus 4.8 |
| LIM-5 | `KeychainWalletConnectSessionStateStore` read-modify-write is atomic **only within a single actor instance**, not across two instances (or an external keychain writer) pointed at the same service/account | Concurrent RMW on the shared JSON blob could lose an update. Mitigated by shipping a `.shared` singleton and injecting it everywhere, so all IRN transports serialize through one actor. Documented at `WalletConnectSessionStateStore.swift:144-153`. | An app composition creates a second store instance for the same service — use `.shared`. | Opus 4.8 |
| LIM-6 | `WalletChain` is a **fixed enum of 6 chains** (ethereum, polygon, base, optimism, arbitrum, solana). Any other CAIP-2 chain (Avalanche, BNB, zkSync, Optimism-testnets, etc.) has no case, so `WalletChain(caip2:)` returns nil and `SessionAddressExtractor` drops those accounts | Keeps the chain model closed and exhaustively switchable; unknown-chain accounts are dropped **safely** (fail-closed, never mis-scoped) rather than mishandled. This is a scope limitation, not a defect. | The product needs to support a chain outside the fixed set — this becomes a feature request requiring a data-driven chain model (namespace + reference) rather than an enum. | Opus 4.8 |
