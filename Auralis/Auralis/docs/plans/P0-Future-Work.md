# P0 Future Work

**Last reconciled with code:** 2026-10-22.

Phase 0 is in the "working baseline" state, not the "nothing left to learn here" state. This file is the backlog for the next engineer who opens the repo and asks, "what actually matters next?"

## Priority Order

1. Stabilize and deepen the real product paths users touch every session.
2. Pay down the architectural seams that are good enough for P0 but too loose for long-term growth.
3. Expand automation so manual confidence stops carrying the whole release story.
4. Improve trust, identity clarity, and failure handling before adding flashy new scope.

## Tier 1: Highest-value next work

### 1. Finish audio/video engine validation and playlist convergence

Why it matters:

- the old app-local `AudioEngine.swift` has been replaced by package-owned `AuraPlayAudioEngine` and `AuraPlayVideoEngine` paths
- playback is still one of the easiest places for "works once" code to turn into sticky lifecycle bugs
- the old `MusicApp/AI/Audio Engine/Playlist/` namespace has been removed, but playlist durability still needs proof across app-owned receipt helpers and the MusicFeature playlist service

Recommended direction:

- run the physical-device pass for interruption, backgrounding, route changes, repeated track swaps, video PiP/AirPlay, and offline/cache behavior
- keep cancellation and stale-load replacement covered through the package engine seams and `AuraPlayPlaybackRuntime`
- keep app-owned primary-store playlist helpers under `MusicApp/AuraPlay/Playlist/` only as an explicit
  compatibility/test path; migrate their remaining consumers deliberately, then remove them rather than synchronizing
  or converging their store with the package-owned MusicFeature playlist service
- add automated coverage around queue advancement, replacement cleanup, and playlist mutations where package/app boundaries meet

Success looks like:

- playback state stays correct across tab switches, app backgrounding, and repeated track changes
- temp files and cached media have clear owners and deterministic cleanup policies
- UI surfaces read state from stable playback/playlist models instead of inferring it from engine internals
- playlist capability remains available without any code living under the old engine namespace

### 2. Finish the ERC-20 manual QA gap and broaden token validation

Why it matters:

- `P0-Hard-Closeout-Report.md` identifies manual UI QA for `P0-461` as the remaining closeout gap.
- The token surface now has real provider-backed state, which means stale-scope bugs and degraded-state bugs are expensive if left vague.

Recommended direction:

- run the physical-device suite in `P0-Physical-Device-QA-Suite.md`
- validate cached-holdings behavior after failure, chain switch, logout, relaunch, and privacy reset
- add follow-on tests for token-detail enrichment, pricing, and history once those land

### 3. Expand no-bypass and end-to-end smoke coverage

Why it matters:

- the repo has good targeted tests, but Phase 0 still leans hard on manual validation for cross-feature flows
- the shell/router/context/provider stack is exactly where regressions cross file boundaries

Recommended direction:

- script the highest-value journeys: valid address entry, account switch, search route, open token detail, open music detail, privacy reset
- keep these flows narrow and stable instead of trying to automate every flourish
- add guardrails around receipt emission for critical shell actions

### 4. Tighten identity and trust presentation

Why it matters:

- address handling is intentionally strict and lowercase-canonical for P0, but the UX is still more "safe parser" than "confidence-inspiring identity layer"
- phishing resistance is mostly deferral right now

Recommended direction:

- add checksum-aware display formatting while preserving canonical storage
- improve ENS presentation rules and trust labeling around resolved names
- make provider-backed provenance clearer in token, balance, and profile surfaces

## Tier 2: Important architectural follow-ons

### 5. Break up oversized files and mixed-responsibility types

Focus areas:

- `Auralis/Auralis/DataModels/NFT.swift`
- `Auralis/Auralis/MusicApp/AuraPlay/Playlist/` app-owned playlist receipt helpers
- shell files that own multiple unrelated view and routing concerns

Goal:

- shrink the amount of code a person or model must load to make a safe change
- move from "god object with helper methods" toward smaller ownership seams

### 6. Deepen provider abstraction and degraded-mode contracts

Why:

- the current read-only provider spine is good enough for P0, but richer token/history/media work will stress it fast
- fallback behavior exists, but it is still somewhat flow-specific

Next moves:

- normalize degraded-state contracts across NFTs, holdings, ENS, and gas
- make freshness and provenance more uniform in UI-facing models
- reduce the chance that thinner provider payloads trigger decoding churn or persistence edge cases

### 7. Strengthen privacy-reset and local-retention verification

Why:

- the app now has a real privacy reset, which means it needs real proof

Next moves:

- verify every local store that should clear actually clears
- document expected retained vs deleted state after reset
- add smoke automation for reset and relaunch behavior

### 8. Carry verifiable wallet proof across Social relay joins

Why:

- the current wallet connector ownership seam returns a local Boolean and intentionally discards the
  wallet signature
- a remote installation therefore cannot verify a peer's join challenge and correctly keeps that peer
  `.pending`, which means peer-authored votes and queue mutations remain fail-closed

Next moves:

- change the wallet boundary to return the actual EIP-191 signature and exact signed message rather than
  promoting a local Boolean attestation into portable trust
- carry the bounded `SocialParticipantProof` with `participantJoined`
- verify the signature against `challenge.signingMessage` and `caip10Account` at
  `SocialRelayCoordinator.handleInbound` before recording remote-verification provenance
- add positive, wrong-account, tampered-message, expired-challenge, replay, and missing-proof tests; keep
  existing peers `.pending` when no independently verifiable proof is present

### 9. Populate and bridge the Phase 1 ownership vocabulary

Status relationship: this is post-completion adoption work. The ownership and sovereignty restructuring
is complete; this item applies its optional vocabulary to individual production writers and does not
reopen the completed architecture initiative.

Why:

- `PrincipalID`, `OwnershipDescriptor`, and the four receipt contribution-provenance fields exist and
  are integrity-bound, but nothing in production writes one, so the audit record cannot yet answer
  "which principal did this" for any real receipt
- the fields are optional precisely so this was not a blocking dependency; the cost is that the
  vocabulary is currently expressible and unused

Next moves:

- populate `principal` / `affectedResource` / `producedResult` / `parentReceiptIDs` on production
  receipt writers. Per-writer work with its own correctness question — which principal, which resource
  namespace — so do it with the feature that needs to read the field, not as a sweep
- define the explicit `RuntimeCore.ActorRef` ↔ `PrincipalID` bridge once there is a consumer to define
  what "stable" means for an `ActorRef`. It must refuse to invent a principal where stable identity is
  unavailable, per `OWNERSHIP.md` constraint 3. Until it exists, a receipt's `actorDetail` and its
  `principal` are independently supplied and can disagree
Deferred deliberately beyond the completed Phase 1 restructuring; rationale and scope are recorded as
post-completion follow-ons A-2 and A-3 in
`Auralis/docs/audits/Phase-1-Authority-Audit.md`.

## Tier 3: Product and UX improvements after the foundations harden

### AuraPlay follow-ons

- Add a reviewed editor surface for the implemented user-owned title, creator, collection, and artwork override contract; the persistence and indexing behavior already exists.
- Promote auto-organization beyond preview only if product approves an apply contract. Applying must use the receipt-backed active playlist manager and show the exact proposed mutations before confirmation.
- Add representative live assistant/Spotlight relevance evaluation in a slower, nondeterministic lane; deterministic precomputed semantic ranking is already covered in the fast package suite.
- Profile the current bounded 5,000-item search snapshot before introducing a trie or another specialized index.
- Remove the primary-store playlist compatibility helpers only when their remaining tests and non-AuraPlay consumers have migrated; never synchronize them with AuraPlay playlists.

### 10. Improve Home from dashboard shell to real control center

Possible directions:

- richer pinned modules
- better recent-activity storytelling
- more useful chain/account context summaries
- clearer paths into Search, Music, Tokens, and Receipts

### 11. Expand search from local-first routing to better discovery

Possible directions:

- richer ranking and grouping
- better mixed-result presentation
- stronger no-results recovery suggestions
- more explicit provenance language for different result classes

### 12. Add deeper token and NFT detail enrichment

Possible directions:

- token pricing/history
- collection-level context
- clearer provenance and trust cues
- richer media handling for unusual NFT payloads

## Things to resist

- do not widen wallet-affecting behavior casually; Observe remains read-only, while Assist and Operate require their
  existing approval, policy-evidence, confirmation, and receipt boundaries
- do not rebuild design primitives unless they are actually blocking product quality
- do not hide architectural debt under "one more feature" if the next feature obviously leans on a weak seam

## Suggested next sprint

1. Complete physical-device QA for the token and music surfaces.
2. Write or tighten the highest-value end-to-end smoke tests.
3. Run the package-owned audio/video engines through the physical-device lifecycle checklist and fix findings at the
   owning package or app-adapter seam; do not restart the completed app-local engine extraction.
4. Tighten identity/trust presentation for addresses and ENS without changing the canonical storage contract.
