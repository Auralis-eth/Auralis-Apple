# AuraPlay UI And Design Audit Checklist

This checklist audits whether AuraPlay feels like a coherent rebuilt music product instead of a technically correct migration seam with a pretty coat of paint.

The current audit target is the shipped Phase 2 persistence seam. That means the checklist should judge the real user-facing state honestly:

- persisted wallet-scoped library data is part of the current product contract
- the active AuraPlay root is still a migration surface, not the final Library/Now Playing/search product
- search, playlists, and durable playback history are later-phase items and should be treated as deferred scope unless they are explicitly activated

## Audit Rules

- review on at least one real device, not only simulator
- review both healthy data and sparse/degraded states
- review both the legacy-root path and AuraPlay-root path if both are still available
- treat misleading playback, scope, or provenance communication as design failures, not just implementation details

## 1. Visual System Integrity

- [ ] AuraPlay surfaces look like part of Auralis rather than a second app with different instincts
- [ ] Card styles, spacing, corner radii, and material treatment feel intentional and repeatable
- [ ] Typography hierarchy makes artwork, title, artist, availability, and controls easy to scan
- [ ] Decorative treatment never overpowers playback readability
- [ ] Loading, empty, and failure states use the same visual language as healthy states

## 2. Music Identity Clarity

- [ ] The Music tab clearly communicates that it is NFT-backed music, not a generic audio utility
- [ ] Playable items are visibly distinct from unsupported or unavailable items
- [ ] Availability and failure messaging uses product language instead of engineering jargon
- [ ] Sparse accounts still get a designed empty state rather than placeholder scaffolding

## 3. Shell And Routing Audit

- [ ] The global shell still feels stable when entering and leaving Music
- [ ] The Music tab does not visually fight the surrounding app chrome
- [ ] Routed detail flows feel like continuations of the Music experience, not abrupt context switches
- [ ] Account and chain scope remain understandable while browsing music content

## 4. Library Audit

- [ ] The current Music root does not misrepresent itself as a fake “foundation” placeholder when persistence is already live
- [ ] If a real library browse surface is active, it feels like a real browse surface rather than a temporary migration summary
- [ ] Artwork, metadata, and action affordances have a clear hierarchy
- [ ] Scroll density is comfortable on device
- [ ] Library rows or cards do not repeat the same information with slightly different labels
- [ ] Empty, loading, and degraded states all have clear next-step guidance
- [ ] Persisted-library state does not feel like a cold-start loading screen every time the tab opens

## 5. Mini Player And Now Playing Audit

- [ ] If mini player or Now Playing are active on the current path, the mini player is easy to understand at a glance
- [ ] If mini player or Now Playing are active on the current path, the mini player does not obscure other content unnecessarily
- [ ] If Now Playing is active on the current path, it has a strong hierarchy: artwork, title, artist, progress, primary controls
- [ ] If playback controls are exposed on the current path, they communicate current state clearly while playing, paused, loading, and failed
- [ ] If progress UI is exposed on the current path, timing feels stable instead of jumpy or haunted

## 6. Queue And Playlist Audit

- [ ] Queue context is understandable when next/previous controls are visible
- [ ] Deferred playlist flows are not implied by misleading affordances on the current path
- [ ] If playlist flows are active later, they feel native to Auralis rather than bolted on from an older experiment
- [ ] If playlist editing is active later, reordering, editing, and artwork selection do not feel like they belong to a different design language

## 7. Trust, Provenance, And Scope Communication

- [ ] The user can tell which account and chain the visible music data belongs to
- [ ] Persisted wallet-scoped content never looks like it belongs to a different account or chain after switching scope
- [ ] External or provider-derived content is not presented with more certainty than the app actually has
- [ ] Outbound links are obviously outbound before the tap
- [ ] Degraded states are honest without sounding catastrophic

## 8. Interaction Audit

- [ ] Major playback and browse actions are buttons, not fragile gesture-only targets
- [ ] Touch targets feel comfortable on a real phone
- [ ] Repeated actions do not create stale overlays, double sheets, or duplicated navigation
- [ ] Loading indicators appear where the user expects them
- [ ] Switching tracks feels orderly rather than chaotic

## 9. Accessibility And Readability Audit

- [ ] Text remains readable at larger Dynamic Type sizes
- [ ] Long NFT titles, artist names, and addresses truncate gracefully
- [ ] Important controls have accessible labels
- [ ] Information is not conveyed by color alone
- [ ] Primary controls remain legible against artwork-heavy backgrounds

## 10. Migration Smell Checklist

- [ ] No screen still feels like a misleading “foundation placeholder” now that the persistence seam is live
- [ ] No legacy `AI/V1` styling leak makes the module feel split-brain
- [ ] No duplicate playback state is implied by the UI
- [ ] No shell-owned state looks like it is secretly being re-owned inside Music
- [ ] Deferred later-phase features are not teased by dead buttons, fake rows, or placeholder copy

## Suggested Audit Output

For each issue found, capture:

- screen/flow
- severity: blocker, major, minor
- what the user sees
- why it matters
- proposed fix direction

## Severity Rubric

- `Blocker`: makes the music flow unusable, deceptive, or visibly broken
- `Major`: damages trust, playback comprehension, or cross-screen consistency
- `Minor`: polish issue that does not break the flow but still lowers product quality
