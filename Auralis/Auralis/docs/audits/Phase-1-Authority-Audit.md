# Phase 1 Authority Audit

> **Status: Complete (2026-10-22).** This audit closes the authority-review portion of the ownership
> and sovereignty restructuring. Findings A-2 and A-3 are deliberately scoped post-completion
> adoption work: neither weakens the completed package, authority, or integrity boundaries.

The audit artifact required by Phase 1, item 8: a review for subsystems that assume Auralis Inc. is
the permanent root owner, or that answer an authorization question from ambient state instead of from
explicit context.

## Scope

| Field | Value |
| --- | --- |
| Repository revision reviewed | `5486b6f` (branch `phased-build-out`) |
| Date reviewed | 2026-10-21 |
| Reviewer | Claude Opus 5 via Claude Code, on behalf of pharms.eth (`idaniel@me.com`) |
| Method | Literal search + per-entry-point signature review of the subsystems listed below |
| Conclusion | **Authorization remains conceptually principal + capability + policy + resource.** No subsystem assumes Auralis Inc. is the permanent root owner. |

### Directories and packages included

The subsystems Phase 1 names as the minimum, all reviewed at the revision above:

- app composition — `Auralis/Assemblies/`, `Auralis/AppServices.swift`
- `RuntimeCore` — checks, judges, hooks, context governance, actor attribution
- `CapabilitiesCore` — the capability registry and descriptors
- `PolicyCore` — standing policy gates and signing readiness
- `ReceiptsCore` — receipt contracts, integrity envelope, contribution provenance
- account identity — `AccountsCore`, `AccountStorage`, `AccountsFeature`
- wallet connectors — `WalletConnectorKit` and its Privy, Reown, Dynamic and Coinbase adapters
- operators — `OperatorCore`, `OperatorsFeature`, `AutopilotCore`, `PlaybookCore`
- trusted UI approval paths — `TrustedUIKit`, `MissionControlFeature`

### Excluded, and why

- `**/.build/**` and `SourcePackages/checkouts/**` — vendored third-party sources. The only ownership
  vocabulary found there is `web3.swift`'s ERC-721 `ownerOf(contract:tokenId:)`, which is an on-chain
  contract call and not an authorization decision in this codebase.
- `AuralisUITests/` — XCUI automation; it exercises surfaces rather than deciding about them.
- Generated SwiftPM sources (`test_entry_point.swift`).

## Literal search terms

The six terms Phase 1 names, re-run at this revision across all first-party Swift sources:

| Term | Occurrences |
| --- | --- |
| `Auralis.shared.currentUser` | 0 |
| `Auralis.shared.owner` | 0 |
| `Auralis.shared.isAuthorized(...)` | 0 |
| `globalOwner` | 0 |
| `systemOwner` | 0 |
| `isAuralisAuthorized` | 0 |

Extended to the differently-named forms the same assumption usually takes, since the point of this
item is that the literal names are the least likely spelling:

| Term | Occurrences | Note |
| --- | --- | --- |
| `currentUser`, `currentPrincipal`, `currentOwner`, `rootOwner` | 0 | — |
| `isOwner`, `isAdmin`, `isPrivileged`, `superuser` | 0 | — |
| `rootActor`, `ambientActor`, `implicitActor` | 0 | — |
| `firstParty`, `isTrusted`, `trustedByDefault` | 0 | — |
| `bootstrapOwner`, `builtInOwner`, `auralisOwned` | 0 | — |
| `defaultOwner*` | 0 | The misleading connector helper name found during the audit was corrected; see below. |
| `ownerOf` | 0 first-party | `web3.swift` only |
| `"auralis"` string literal | 1 | A URL-scheme check in `AuraPlayModuleConfiguration`, not identity |

## Semantic entry points examined

Rather than trusting the term list, each function that *returns a decision* was read for whether its
inputs arrive as arguments:

| Entry point | Context it receives | Ambient reads |
| --- | --- | --- |
| `Judge.judge(_:checkResults:)` | `ActionProposal` + check results | none |
| `ObserveModeJudge` / `DomainJudge` | proposal, injected `isObserveMode` / `cryptoMode` | none |
| `DeterministicCheck.evaluate(_:)` | `ActionProposal` | none |
| `DeterministicCheckRegistry.evaluate(ids:for:)` | explicit check ids + proposal | none |
| `ToolPolicyEvaluating.evaluate(_:checkResults:)` | proposal + check results | none |
| `BeforeToolCallHook.evaluate(...)` | proposal | none |
| `ContextGovernanceBoundary.authorize(...)` | explicit bundle and contract | none |
| `StandingToolPolicy.evaluate(action:mode:isCryptoCapability:requiresConfirmation:intent:)` | five explicit arguments | none |
| `PolicyExecutionReadiness.evaluate(...)` | explicit arguments | none |
| `CapabilityRegistry.descriptor(for:)` | `CapabilityID` | none |
| `TrustedUIComponentRegistry.performApprovalDecision(rendered:dispatched:outcome:handler:)` | both requests, compared whole | none |

`ActionProposal` — the value every governance decision is taken over — carries `actor: ActorRef`,
`capability: CapabilityID`, `authorityState`, `impact`, `workflowRun`, `correlationID` and
`parameters`. That is the four-legged shape this audit was asked to confirm: the **principal** (actor),
the **capability**, the **policy** (the judge/standing-policy evaluation applied to it), and the
**resource** (the capability-scoped parameters). None of the four is read from a global.

## Acceptable authority seams

Seams that legitimately concentrate authority, recorded so they are visible rather than discovered
later:

1. **`ReceiptSignerFactory.deviceSigner()`** — one device signing identity per install, held in the
   Keychain. Authority over the receipt ledger's attestation is necessarily device-local; the package
   already documents that anyone who can write both the row store and the Keychain can rewrite history
   into `.unattested`, and that this is conceded by design.
2. **`ReceiptStores.live` / `persistenceStore(for:)`** — a per-`ModelContainer` memoized actor. It
   concentrates *serialization*, not authority: the ledger lock has to be one object or the chain
   forks. No authorization decision reads it.
3. **`RuntimeKit` composition** — only `RuntimeKit` may construct `GovernedToolPipeline`,
   `ToolRegistry` or `ToolExecutionAuthorization`, enforced structurally by
   `ArchitectureBoundaryTests`. This is a *narrowing* of who may mint authority, which is the opposite
   of the assumption this audit looks for.
4. **`KeychainWalletConnectSessionStateStore.shared`** — a Keychain-backed session store. It persists
   which wallet session exists; it does not decide what that session may do. Wallet action
   authorization runs through `StandingToolPolicy` and the signing-readiness gate.
5. **Caches with `static let shared`** — `GasPriceCache`, `ENSResolvers.sharedCacheStore`,
   `NFTImageCache`. Pure caches, no decisions.

## Corrections made

The private `defaultOwnershipMetadata()` helper in each of the four `WalletConnectorKit` adapters was
renamed to `defaultConnectionMetadata()`. The value is `WalletConnectionMetadata` carrying the dapp
name, description and URL presented during a wallet handshake; it is unrelated to resource ownership
and defaults no role to any principal. Each helper had one same-file call site, so correcting the
misleading name changed no API surface or runtime behavior.

## Post-completion follow-ons

| # | Finding | Where | Why deferred |
| --- | --- | --- | --- |
| A-2 | No bridge exists between `RuntimeCore.ActorRef` and `PrincipalID`, so a receipt's `actorDetail` and its `principal` are independently supplied and can disagree. | `ReceiptsCore`, `RuntimeCore` | Deliberately outside the completed restructuring. `OWNERSHIP.md` constraint 3 requires any bridge to be explicit and to refuse to invent a principal where stable identity is unavailable, and there is no consumer yet to define what "stable" means for an `ActorRef`. Revisit when the first reader of `principal` is built. |
| A-3 | Nothing yet *writes* `principal`, `affectedResource` or `producedResult` on a production receipt. | all receipt writers | Deliberately outside the completed restructuring. Phase 1 establishes the vocabulary and integrity contract; populating it is per-writer feature work with its own correctness question (which principal, which resource namespace). The fields are optional precisely so adoption is not a blocking dependency. |

## Confirmation

Authorization in Auralis remains conceptually **principal + capability + policy + resource**, with each
leg supplied explicitly at every decision point reviewed. No subsystem assumes Auralis Inc. is the
permanent root owner, and no bootstrap exception was found that has hardened into a domain invariant.

Ownership metadata added in Phase 1 grants no authority: `OwnershipDescriptor` is consulted by nothing
in `PolicyCore`, `CapabilitiesCore`, `RuntimeCore` or the governed tool pipeline, which is asserted
structurally by `ArchitectureBoundaryTests.ownershipMetadataGrantsNoAuthority()`.
