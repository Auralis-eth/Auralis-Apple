# P0 Future Work

Phase 0 is in the "working baseline" state, not the "nothing left to learn here" state. This file is the backlog for the next engineer who opens the repo and asks, "what actually matters next?"

## Priority Order

1. Stabilize and deepen the real product paths users touch every session.
2. Pay down the architectural seams that are good enough for P0 but too loose for long-term growth.
3. Expand automation so manual confidence stops carrying the whole release story.
4. Improve trust, identity clarity, and failure handling before adding flashy new scope.

## Tier 1: Highest-value next work

### 1. Rebuild or significantly re-architect the audio engine

Why it matters:

- `AudioEngine` is a long-lived shared service with download, temp-file, queue, and playback-state responsibilities mixed together.
- `P0-803` already calls out temp-file lifecycle review as deferred work.
- Music is one of the easiest places for "works once" code to turn into sticky lifecycle bugs.

Recommended direction:

- split transport/download, temp-file management, playback session, and queue coordination into clearer seams
- make cancellation and stale-load replacement explicit contracts instead of side effects hidden in one type
- add a focused physical-device pass for interruption, backgrounding, route changes, and repeated track swaps
- add automated coverage around queue advancement and replacement cleanup

Success looks like:

- playback state stays correct across tab switches, app backgrounding, and repeated track changes
- temp files have a clear owner and deterministic cleanup policy
- UI surfaces read state from a stable playback model instead of inferring it from engine internals

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
- `Auralis/Auralis/MusicApp/AI/Audio Engine/AudioEngine.swift`
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

## Tier 3: Product and UX improvements after the foundations harden

### 8. Improve Home from dashboard shell to real control center

Possible directions:

- richer pinned modules
- better recent-activity storytelling
- more useful chain/account context summaries
- clearer paths into Search, Music, Tokens, and Receipts

### 9. Expand search from local-first routing to better discovery

Possible directions:

- richer ranking and grouping
- better mixed-result presentation
- stronger no-results recovery suggestions
- more explicit provenance language for different result classes

### 10. Add deeper token and NFT detail enrichment

Possible directions:

- token pricing/history
- collection-level context
- clearer provenance and trust cues
- richer media handling for unusual NFT payloads

## Things to resist

- do not add signing-wallet behavior casually; the app's safety posture currently benefits from being read-only
- do not rebuild design primitives unless they are actually blocking product quality
- do not hide architectural debt under "one more feature" if the next feature obviously leans on a weak seam

## Suggested next sprint

1. Complete physical-device QA for the token and music surfaces.
2. Write or tighten the highest-value end-to-end smoke tests.
3. Start the audio-engine refactor plan with a concrete seam split and lifecycle checklist.
4. Tighten identity/trust presentation for addresses and ENS without changing the canonical storage contract.
