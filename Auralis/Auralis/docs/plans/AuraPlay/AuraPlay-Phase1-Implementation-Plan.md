# AuraPlay Phase 1 Implementation Plan

Phase 1 is no longer best represented as a ticket-by-ticket execution checklist.

The module foundation work has been translated into the retained follow-on docs below so the next engineer does not need to read stale ticket scaffolding to understand what remains, how to validate it, and how to start Phase 2 safely.

## Retained AuraPlay Docs

1. `AuraPlay-Future-Work.md`
   The backlog of incomplete and intentionally deferred work after the Phase 1 foundation pass.
2. `AuraPlay-Physical-Device-QA-Suite.md`
   The real-device manual QA pass for the rebuilt music stack and the legacy-to-AuraPlay seam.
3. `AuraPlay-UI-Design-Audit-Checklist.md`
   The product and interaction audit checklist for the music rebuild.
4. `AuraPlay-Phase2-Handoff.md`
   The practical handoff notes for starting Phase 2 feature migration work.
5. `AuraPlay-LLM-Context.md`
   The compact memory layer for future LLM sessions that need the AuraPlay mental model fast.

## What Phase 1 Established

- AuraPlay now lives inside `Auralis` as the rebuild path for the Music tab.
- The module uses native SwiftUI with `@Observable` presentation state and initializer-based dependency injection.
- The Music tab routes through `AuraPlayTabRootView`, which can preserve the legacy `AI/V1` root or switch to the AuraPlay root.
- The first service seams now exist for library, playback, queue, artwork, logging, and bundle configuration concerns.
- Repo-level lint, CI, privacy, and documentation now recognize the AuraPlay module as a first-class surface.

## What This File Is Not Anymore

- not a source of truth for ticket status
- not a backlog tracker
- not the best place to start if you need implementation detail

For implementation detail, start with:

- `Auralis/MusicApp/AuraPlay/AuraPlay-README.md`
- `docs/decisions/ADR-001-auraplay-architecture.md`
- the retained AuraPlay docs listed above
