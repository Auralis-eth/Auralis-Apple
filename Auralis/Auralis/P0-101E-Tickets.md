# P0-101E Tickets And Session Handoff

This document turns `P0-101E` into an execution checklist for the next implementation session.

`P0-101E` is intentionally small. The ticket should deliver a usable Phase 0 primitive set, not a full design-system overhaul.

## Ticket Summary

JIRA: `P0-101E`

Goal:

- implement reusable UI components and layout primitives used across Home, Search, Libraries, and Receipts
- keep the system minimal but consistent

## Non-Negotiable Scope Limits

- do not redesign the app
- do not build a giant token framework
- do not migrate every screen in one pass
- do not invent primitives with no immediate consumer
- do not break the existing Aura visual language

## Dependencies

Hard dependencies:

- none

Soft downstream consumers:

- `P0-101B` Global Chrome UI
- Home/Search/Libraries/Receipts surfaces that need shared layout and component treatment

## Edge Cases To Keep In View

- Dynamic Type, including accessibility sizes
- dark mode and contrast
- very small devices
- larger screens and wider layouts
- truncation for long labels inside shared components

## Implementation Plan

### Step 1. Inventory repeated UI patterns

Read the current Aura files and write down what is obviously repeated:

- spacing stacks
- card containers
- pills and badges
- action buttons
- section headers
- empty-state wrappers

Good starting references:

- [`Auralis/Auralis/Aura/Text+Font.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Text+Font.swift)
- [`Auralis/Auralis/Aura/Home/ProfileCardView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Home/ProfileCardView.swift)
- [`Auralis/Auralis/Aura/Home/EnergyCardView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Home/EnergyCardView.swift)
- [`Auralis/Auralis/Aura/Newsfeed/Components/NFTSortButton.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Newsfeed/Components/NFTSortButton.swift)
- [`Auralis/Auralis/Aura/Newsfeed/Components/TorchToggleButton.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Newsfeed/Components/TorchToggleButton.swift)

Exit criteria:

- the first primitive set is chosen and justified

### Step 2. Choose the primitive home

Create one obvious place for shared Aura-level primitives.

Requirements:

- easy for future tickets to discover
- close to the UI layer
- not buried in `Helpers`

Exit criteria:

- new shared primitive files live in one consistent location

### Step 3. Implement the first primitive slice

Target only the highest-leverage components:

- screen/container layout primitive
- surface card/container primitive
- badge or pill primitive
- shared action/button primitive
- section header primitive

Exit criteria:

- each primitive has one clear purpose
- each primitive is reusable without feature-specific naming

### Step 4. Prove the primitives in real screens

Adopt the new primitives in a few current views instead of leaving them as unused abstractions.

Recommended proving surfaces:

- one Home view
- one News/Search-adjacent view
- one utility or detail-style view

Exit criteria:

- at least a few production views use the primitives
- duplicated styling is reduced where the new abstraction clearly helps

### Step 5. Validate accessibility and layout behavior

Run the ticket’s stated checks:

- light mode and dark mode
- large Dynamic Type
- compact-width layout
- truncation and overflow behavior

If the team uses snapshot tests, add them only for the most stable core primitives.

Exit criteria:

- no obvious overflow, clipping, or unreadable contrast problems remain in the migrated surfaces

## Testing Expectations

Minimum validation:

- visual QA in light mode
- visual QA in dark mode
- Dynamic Type check at the largest size
- compact device check

Optional validation:

- snapshot tests for the most stable primitives

## Anti-Patterns To Avoid

- naming a component after a single screen and then pretending it is generic
- creating “universal” components with too many modes
- using hard-coded heights where text needs to grow
- introducing a second visual language unrelated to Aura
- migrating screens just for the sake of migration

## Session Handoff Notes

If implementation starts in a later session, the next agent should:

1. re-read [`P0-101E-Strategy.md`](/Users/danielbell/Dev/Auralis-Apple/Auralis/P0-101E-Strategy.md)
2. inspect the current Aura typography and card/button treatments
3. choose the smallest viable primitive set
4. migrate only enough real screens to prove the primitives are worth keeping

## Definition Of Done

`P0-101E` is done when:

- a minimal set of shared UI primitives exists
- the primitives have a clear home and consistent naming
- a few real screens use them
- the primitives hold up in light/dark mode and large Dynamic Type
- the ticket leaves the app more consistent without creating a giant design-system maintenance burden
