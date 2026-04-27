# P0 UI And Design Audit Checklist

This checklist audits whether Phase 0 looks and feels like a coherent product. It is not a pixel-police exercise. The goal is to catch places where the app accidentally feels unfinished, misleading, or internally inconsistent.

## Audit Rules

- review on at least one real device, not only simulator
- review both best-case data and empty/degraded states
- review at least one account with useful NFT/token data and one sparse account if possible
- treat broken trust/provenance communication as a design issue, not just a copy issue

## 1. Visual system integrity

- [ ] Aura surfaces look like they belong to one design system rather than a pile of screen-level experiments
- [ ] Card styles, corner radii, spacing, and elevation feel consistent across Home, Search, Tokens, Music, and Receipts
- [ ] Typography hierarchy is clear and repeatable
- [ ] Decorative treatment never overpowers legibility
- [ ] Color communicates meaning consistently for active, disabled, degraded, and destructive states
- [ ] Loading, empty, and error states use the same visual language as populated states

## 2. Gateway and onboarding quality

- [ ] Gateway screen feels intentional on first launch, not like a placeholder gate
- [ ] Primary action is visually obvious
- [ ] Manual address entry field is easy to identify and use
- [ ] Validation feedback is visible, readable, and not overly technical
- [ ] Guest pass cards feel like real choices, not debug shortcuts
- [ ] QR scan entry communicates trust sensitivity clearly

## 3. Shell and chrome audit

- [ ] Global chrome is visibly stable across tabs and does not jump awkwardly during state changes
- [ ] Context and mode indicators are readable and understandable
- [ ] Root-tab destinations feel clearly distinct
- [ ] Tab icons and labels match the feature the user reaches
- [ ] The shell does not look "busy by default" when data is loading in the background

## 4. Home audit

- [ ] Home reads like a dashboard/control center, not a random list of modules
- [ ] Active account identity is prominent enough to anchor the page
- [ ] Chain/scope context is clear
- [ ] Quick links and modules feel prioritized rather than equally loud
- [ ] Recent activity is understandable at a glance
- [ ] Empty-state Home still feels designed, not abandoned

## 5. Search audit

- [ ] Search entry points are easy to discover
- [ ] Search UI clearly signals what kinds of inputs work
- [ ] Query parsing/type detection feedback is useful without being noisy
- [ ] Result grouping and labels make provenance obvious
- [ ] No-results state gives the user a next move
- [ ] Search history looks intentional and scoped, not creepy or random

## 6. News/NFT browsing audit

- [ ] NFT cards are readable and scannable
- [ ] Media, metadata, and action affordances do not compete for attention
- [ ] Trust or outbound-link cues are visible before launch
- [ ] Empty/degraded states do not look like broken content loading
- [ ] Sort/filter controls feel connected to the list they affect

## 7. Token surfaces audit

- [ ] ERC-20 holdings screen feels like part of Auralis, not a bolted-on utility page
- [ ] Readability of token symbol, amount, and supporting metadata is strong
- [ ] Cached/degraded/failure states are distinguishable from live healthy states
- [ ] Token detail screens communicate what is known, what is estimated, and what is unavailable
- [ ] Scope changes do not create visual confusion about which account or chain is being shown

## 8. Music audit

- [ ] Music tab clearly communicates that it is derived from NFT-backed media
- [ ] Playable items are visually distinct from non-playable or unsupported items
- [ ] Mini player is easy to understand and does not obscure other UI unnecessarily
- [ ] Now Playing screen has a strong hierarchy: artwork/title/controls/progress
- [ ] Playback failure states look deliberate and readable
- [ ] Playlist flows feel native to the app instead of tacked on

## 9. Receipts and settings audit

- [ ] Receipts timeline is readable as an audit/history surface, not a debug dump
- [ ] Receipt detail makes cause/effect easier to understand
- [ ] Settings surfaces only meaningful controls and does not feel like a junk drawer
- [ ] Privacy reset is understandable and appropriately serious

## 10. Trust, provenance, and safety communication

- [ ] Trust labels are visible where provider-backed or external data matters
- [ ] Untrusted or user-supplied inputs are visually differentiated from app-known state
- [ ] External links are clearly outbound before the tap
- [ ] Freshness/provenance language is understandable to a non-engineer
- [ ] Degraded mode messaging is honest without sounding catastrophic

## 11. Interaction audit

- [ ] Major actions are buttons, not fragile gesture-only affordances
- [ ] Touch targets feel large enough on device
- [ ] Sheets, dialogs, and navigation transitions feel orderly
- [ ] Repeated actions do not create visual duplication or stale overlays
- [ ] Loading indicators appear where the user expects them

## 12. Accessibility and readability audit

- [ ] Text remains readable at larger Dynamic Type sizes
- [ ] Contrast is acceptable for primary content and controls
- [ ] Important controls have accessible labels
- [ ] Information is not conveyed by color alone
- [ ] Long addresses, token values, and NFT names truncate gracefully

## 13. Design debt to watch for

- [ ] inconsistent spacing between feature areas
- [ ] surfaces that still read as placeholder scaffolding
- [ ] cards that repeat the same information with different labels
- [ ] states that rely on engineering jargon instead of product language
- [ ] provider-backed data shown with the same certainty as local deterministic data

## Suggested audit output

For each issue found, capture:

- screen/flow
- severity: blocker, major, minor
- what the user sees
- why it matters
- proposed fix direction

## Severity rubric

- `Blocker`: makes a core flow unusable, deceptive, or visibly broken
- `Major`: damages trust, comprehension, or consistency in an important flow
- `Minor`: polish issue that does not break the flow but still lowers product quality
