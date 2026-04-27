# Phase 0 LLM Handoff

This file keeps the durable context from the deleted `P0-*.md` planning bundle.

Use it as the Phase 0 memory layer for future sessions. Do not resurrect the old ticket-by-ticket markdown swarm unless there is a real planning need.

## What Still Exists

These Phase 0 docs remain the source of truth for active follow-on work and manual review:

- `P0-Future-Work.md`
- `P0-Physical-Device-QA-Suite.md`
- `P0-UI-Design-Audit-Checklist.md`

## Phase 0 Status Snapshot

- Treat Phase 0 as delivered for its current product slice.
- `P0-801` was canceled. Guest passes remain, but bundled demo data and a dedicated offline-mode product slice are not active work.
- `P0-802` was completed for the current release-readiness slice.
- `P0-803` was completed for the current privacy/security review slice.
- The one explicitly recorded closeout gap was manual UI QA for the provider-backed ERC-20 holdings flow (`P0-461`).

## Durable Product And Architecture Decisions

- `AccountStore` is the account CRUD seam. Do not scatter account persistence logic across views.
- Account identity uses strict validation and lowercase canonical `0x...` normalization for Phase 0 storage and copy behavior. Checksum-display UX is still deferred.
- Per-account chain scope persists and drives visible shell state plus refresh behavior.
- `ContextSnapshot` and `ContextService` are the shell-facing context contract. Chrome and inspector should read shared context instead of re-deriving parallel shell state.
- The read-only provider abstraction is real and should stay centralized. NFT fetches, gas reads, and native balance reads should continue flowing through shared provider seams.
- Receipt logging is a real product seam, not debug confetti. Keep payload sanitization, explicit provenance, and reset behavior intact.
- `P0-502` was intentionally incremental. `P0-502B` was the verification and cleanup pass. Keep that split in mind if receipt work expands again.
- `P0-701` was intentionally split:
  - `701A`: structural scaffolding
  - `701B`: first enforcement pass
- Deeper boundary cleanup and broader smoke coverage are follow-on hardening, not evidence that the current baseline is missing.
- Home, Search, Music, and token surfaces are all mounted product paths now. Treat placeholder-era assumptions in older notes as stale.

## Release-Readiness Rules Worth Preserving

- The two benchmark flows defined for the first baseline were:
  - valid address submit to first usable shell
  - opening the ERC-20 holdings screen
- Measure perceived usability, not just network completion. Cached, degraded, and partial-content states count because they are part of the real product path.
- Release confidence still requires:
  - clean build state
  - core wallet-to-shell journey working on a clean install
  - safe account switching and scope changes
  - no stale-scope leakage across NFTs, holdings, or routed detail state

## Privacy And Safety Deferrals Still Worth Knowing

- Checksum-display and stronger phishing-resistant identity presentation are still deferred.
- Audio temp-file lifecycle deserves another review around app termination and background edge cases.
- Trust-label rollout should continue if new provider-backed or outbound-action surfaces are added.
- Keep treating unknown receipt payload strings as suspicious until explicitly classified.

## Practical Planning Rules

- Prefer newer completion-facing artifacts and the code itself over stale dependency notes.
- Do not treat deleted planning docs as missing requirements. Most of them were temporary execution scaffolding.
- If future work needs Phase 0 context, start with:
  - `AGENTS.md`
  - `LLM_CONTEXT.md`
  - this file
  - the three retained Phase 0 docs
  - the code and tests

## Code Areas That Mattered In Phase 0

- Shell and chrome: `Auralis/Aura/MainAuraView.swift`, `Auralis/Aura/MainAuraShell.swift`, `Auralis/Aura/GlobalChromeView.swift`
- Account and scope: `Auralis/Accounts/AccountStore.swift`, `Auralis/DataModels/EOAccount.swift`, `Auralis/DataModels/Chain.swift`
- Search: `Auralis/Aura/Search/`
- Home: `Auralis/Aura/Home/`
- Providers and refresh: `Auralis/Networking/ReadOnlyProviderSupport.swift`, `Auralis/Networking/NFTService.swift`, `Auralis/Networking/NFTFetcher.swift`
- Receipts: `Auralis/Receipts/`
- Music: `Auralis/MusicApp/AI/`
- Token holdings: `Auralis/Accounts/TokenHoldingsStore.swift`, `Auralis/DataModels/TokenHolding.swift`
