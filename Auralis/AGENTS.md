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

### Ownership And Package Boundaries (Phase 1)

**Status: Complete (2026-10-22).** The ownership and sovereignty restructuring is implemented,
audited, documented, and guarded by architecture tests for its defined Phase 1 scope. Optional
production provenance population and any future governance or economic system remain separately
scoped follow-ons and do not make this restructuring incomplete.

Each concept resolves in exactly one package. Do not merge them into a generalized identity,
permissions, or ownership system — the separation is what lets a protocol be lifted out of this app.

| Package | Answers |
| --- | --- |
| `AuralisFoundation` | which principals have which *stated* relationships to a resource (`PrincipalID`, `OwnershipDescriptor`) |
| `RuntimeCore` | who acted in a governed runtime event (`ActorRef`, rich attribution) |
| `AuralisFoundation` (`CapabilitiesCore` target) | what an actor may do |
| `PolicyCore` | under what rules an action may proceed |
| `ReceiptsCore` | what actually happened, and its contribution provenance |
| `ArtifactCore` | what resulted |

- `PrincipalID` is a **stable, non-empty, opaque** label. Compare, store, serialize and pass it; never
  parse `rawValue` to infer whether the principal is a person, agent, organization, wallet, address,
  DID, protocol or network, and never branch authorization, presentation, routing or persistence on
  its contents. It does not replace `ActorRef`; any bridge must be explicit and must not invent a
  principal where stable identity is unavailable.
- `OwnershipDescriptor` keeps creator, owner, controller, custodian and beneficiary **independently
  optional**, with beneficiaries ordered-unique. Absent means *not stated*, never *held by us*.
- **Ownership metadata grants no authority.** Nothing in `PolicyCore`, `CapabilitiesCore`,
  `RuntimeCore`, `RuntimeKit` or `TrustedUIKit` may read an `OwnershipDescriptor`; a rule like "the
  owner may do X" belongs in policy, with ownership as one input and the decision on a receipt.
- Contribution provenance and economic ownership stay separate. No receipt or package may carry
  `tokensEarned`, `equityPercentage`, `ownershipPercentage`, `financialReward`, `governanceWeight` or
  a vesting schedule.
- `AuralisFoundation` declares **no dependencies at all**, and the ownership sources import only
  `Foundation`. This is what "architecturally capable of separation" means structurally; it is also
  why `AgentIdentityCore` stays retired.

All six constraints are enforced by `AuralisTests/ArchitectureBoundaryTests.swift`. The reasoning is
in `OWNERSHIP.md`; the position behind it is in `FOUNDERS_COVENANT.md`.

## Important Conventions

- Prefer SwiftUI-first, state-driven code.
- Prefer Swift Concurrency over callback-heavy APIs.
- Prefer instance methods and injected dependencies over `static` helpers unless type-level behavior is genuinely the right model.
- Prefer Swift Testing over XCTest for unit and integration-style tests.
- Prefer parameterized tests over many near-duplicate individual tests.
- XCUI tests still use XCTest/XCUIAutomation because that is the platform tool.
- Keep route logic centralized in the shell/router rather than scattering ad hoc navigation state across views.
- Model routing has two separate responsibilities: `ModelRouting` chooses a `ModelRoute`, and `ModelInferring` performs routed provider inference. Do not stamp remote/provider telemetry unless that provider inference seam actually ran; local fallbacks must remain visibly local or unmodeled.
- Policy authorization receives canonical `RuntimeCore.ActorRef` attribution. Do not pass `ReceiptActorDetail` through `PolicyActionGating`; convert runtime attribution to receipt wire models only at a receipt-writing boundary.
- `@Query` may project shell-scoped SwiftData data for presentation, detail lookup, and the single `MainAuraView` account resolver bridge. It must not become a shell coordinator: active account, active chain, logout/privacy reset, account removal, route reset, refresh, and deep-link readiness changes flow through `ShellStore.send(_:)` or collaborators invoked by `ShellStore`.
- Treat NFT IDs and Ethereum wallet addresses as public identifiers in this product. They may be shown in UI, logs, and receipts when useful; do not flag their mere presence as a privacy issue. Secrets, API keys, auth tokens, cookies, private keys, seed material, copied sensitive text, and provider internals still require redaction or hashing.
- Mission Control exposes all three crypto modes: Observe, Assist, and Operate. Observe is read-only for wallet actions; Assist is approval-gated preparation; Operate still requires policy evidence, confirmation, and receipts before high-risk crypto execution. Do not describe Assist or Operate as ungated hidden power.
- Third-party wallet support is a hardware-proven claim, not a compile-time claim. Do not list Rabby, Rainbow, Coinbase Wallet, MetaMask, Phantom, Backpack, Solflare, Privy, or Dynamic as production-supported until the matching physical-device QA route proves connect, reject/cancel, ownership verification, disconnect, restore/fail-closed, and callback round-trip behavior.
- Accessibility identifiers used by UI tests, VoiceOver automation, or Voice Control labels must be registered in `AuraUI/Sources/AuraUI/A11yID.swift`. Conventions: lowercased dot-namespaced strings of the form `area.control` (e.g. `tab.home`, `search.queryField`, `nftTokens.row.{id}`). Per-instance identifiers expose a static helper that interpolates the instance ID. New flows must list their primary controls, empty states, errors, and destructive confirmations in the registry before merge.

## Build And Run

- Use the `Auralis` scheme.
- Build with Xcode or the MCP `BuildProject` tool.
- Unit tests live in `AuralisTests`.
- UI tests live in `AuralisUITests`.
- **A green app test plan says nothing about the local packages.** `Auralis-Fast` and `Auralis-Full`
  contain only `AuralisTests`/`AuralisUITests`; every package test target runs as its own CI lane.
  So a change that crosses package boundaries needs the package suites run locally as well —
  `DEVELOPER_DIR=<Xcode-beta>/Contents/Developer swift test --package-path <Pkg>` — or it is not
  validated until CI. Audit Round 13 shipped seven compile-breaking call sites past a 771/0 app run
  this way.

## High-Value Docs

- `Auralis/docs/strategy/Auralis_Sovereign_Human_Agent_Strategy_PRD.md` is the product and sovereignty source of truth: the human remains principal; identity, memory, context, policy, authority and receipts are durable; models and external capabilities are replaceable.
- `Auralis/docs/strategy/Auralis_Executive_Function_Operating_System.md` defines the intention-to-commitment operating-system thesis and the distinction between durable commitments, execution state and verified outcomes.
- `LLM_CONTEXT.md` is the fastest repo orientation file for engineers or models that need the working mental model without rereading the entire codebase.
- `Auralis/docs/reference/Runtime-Kernel.md` is the phase-free contract reference for the governed runtime: the action boundary, tool registry and hooks, event bus, context bundles, trusted UI requests, actor attribution, worklogs, deterministic checks, and outcome specs. Read it before adding a tool, check, event consumer, context source, or agent-facing trust surface. It records the invariant each primitive enforces and the test that proves it, so prefer updating it over restating kernel behavior in a phase plan.
- `P0-Future-Work.md` is the post-Phase-0 backlog and should be updated when hardening or architecture follow-on work becomes clearer.
- `P0-Physical-Device-QA-Suite.md` is the real-device manual QA contract for Phase 0.
- `P0-UI-Design-Audit-Checklist.md` is the product/design quality checklist for Phase 0 surfaces.
- `AuralisPrimaryModels/` owns pure domain values in `AuralisPrimaryModels`, the remaining shared SwiftData schema cluster in `AuralisPrimaryPersistence`, and domain-specific NFT fixtures in the test-only consumer product `PrimaryModelsTestSupport`.
- `AuralisFoundation/` is the dependency-free home of portable cross-domain vocabulary. Its
  `AuralisFoundation` target owns `PrincipalID`, `OwnershipDescriptor`, and generic `JSONValue`; its independent
  `CapabilitiesCore` target owns stable capability vocabulary and the conservative registry;
  `SwiftDataAdapters` and `UserDefaultsAdapters` own generic persistence mechanics. Do not use these
  targets as landing zones for models whose account, receipt, NFT, music, search, or domain-storage
  owner is known.
- `AuralisShellCore/` is the local Swift package for shell state, shell actions, `ShellStore`, dependency protocols, and deep-link routing rules. Keep live app infrastructure out of this package.
- `MusicFeature/` is the local Swift package for the AuraPlay music feature boundary. It owns AuraPlay domain values and service protocols; concrete app composition and SwiftData live adapters stay in the app target, while playback engine internals live as the `AuraPlayMediaCore`, `AuraPlayAudioEngine`, and `AuraPlayVideoEngine` targets inside `AuraPlayEngines/`.
- `SwiftDataAdapters` is an independent target/product inside `AuralisFoundation/` for shared SwiftData mechanics such as rollback-safe and undoable mutation helpers. It provides tools, not domain-specific stores.
- `AccountStorage` is an internal target/product of `AccountsCore/` for SwiftData-backed account persistence. Keep protocol consumers on `AccountsCore.AccountStoring`; only composition and storage tests should import `AccountStorage`.
- `ReceiptStorage` is an internal target/product of `ReceiptsCore/` for SwiftData-backed receipt persistence and destructive receipt reset adapters. Keep protocol/logging consumers on `ReceiptsCore`; only concrete builders and storage tests should import `ReceiptStorage`.
- Receipt integrity is a local tamper-evidence contract. Receipts are hash-chained in SwiftData and checked against Keychain-protected account heads on the same device; externally enforceable proof requires trusted infrastructure or signed receipt-head sync.
- Receipt export verification must pin `provenanceTrustAnchor()` through a channel separate from the exported JSON. Never treat the fingerprint embedded in an export as its own trust proof.
- Receipt integrity history is **versioned, never rewritten**. A new provenance field is bound by a new `ReceiptIntegrityEnvelopeVersion` and old rows keep verifying under the version they were written with. Every schema change touches `ReceiptsCore` contracts, `ReceiptStorage` persistence, envelope hashing, export, verification, backward-compatible decoding, migration, and the storage/tamper tests **together**; the per-version golden vectors in `ReceiptEnvelopeSpecificationTests` are the no-rehash proof and the older ones must never change.
- Receipt causality is **stated, never inferred**. `parentReceiptIDs` means "this earlier receipt caused or enabled the action", is validated before the write (no duplicates, no self-reference, parents must already exist), and must never be derived from timestamps, correlation IDs, artifact links, sequence order, or `previousReceiptHash` — that last one is an integrity-chain link with no semantic content.
- `OWNERSHIP.md` and `FOUNDERS_COVENANT.md` are the repository-level ownership architecture and the position behind it. `Auralis/docs/audits/Phase-1-Authority-Audit.md` records the authority review that confirms authorization is principal + capability + policy + resource.
- Runtime execution isolation is capability isolation inside the app process: app callers enter through `RuntimeHost`/`GovernedToolPipeline`, which resolves registered tools, validates schemas, checks capability/impact/leases/restrictions, judges, executes, and receipts. It is not an OS process sandbox; introduce an XPC or Enhanced Security extension before accepting hostile native plugin code.
- Runtime event delivery has two contracts: UI/activity consumers use bounded live streams, while receipt and performance observers use named lossless streams with durable checkpoints and history replay. New audit-critical consumers must use the reliable contract and expose subscriber health in Mission Control.
- Adaptive improvement is advisory and approval-gated. `EvalCore` derives deterministic, evidence-linked recommendations; `OperatorRuntimeStorage` persists their lifecycle; Mission Control may accept, reject, or mark them applied. Recommendation handling must never directly widen authority, mutate policy, or edit playbooks, and every human lifecycle transition must emit a worklog entry and receipt.

## Quirks And Gotchas

- `NFT.swift` is oversized and contains multiple responsibilities.
- Account, chain, logout, and deep-link shell transitions should go through `ShellStore.send(_:)`, not direct binding mutation.
- Account changes should reset routed detail stacks to root.
- Guest passes are a lightweight onboarding shortcut to curated public wallets, not a separate demo-data product mode.
- Deep links may arrive during cold start; queue them until shell state is ready.
- Receipt routing is intentionally safe-fail for now. Full receipt support is deferred.
- The shipping music UI lives under `MusicApp/AuraPlay/` and `MusicFeature/`; audio/video playback internals are owned by the corresponding targets in `AuraPlayEngines/`. App-owned playlist receipt helpers live under `MusicApp/AuraPlay/Playlist/`; do not reintroduce music code under the old `MusicApp/AI/` namespace.
- Provider-facing UI expects typed failures. Prefer mapping transport/provider errors into `ProviderAbstractionError` or `NFTProviderFailure` instead of leaking raw `URLError`s upward.
- Reuse the shared `RetryAfterSupport` helper for backoff parsing. The stack now supports both numeric and HTTP-date `Retry-After` headers.
- Shared SwiftUI motion should flow through `AuraMotionPolicy` from AuraUI. Build it from `@Environment(\.accessibilityReduceMotion)` so decorative loops and state-change animations honor Reduce Motion consistently.
- `AuraHaptics` intentionally remains tied to Reduce Motion for 0.1.0. A separate haptics preference is a future product/settings decision, not a Phase 4 behavior change.
