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

Step 1 inventory result:

Primary reference surfaces for the primitive inventory:

- authenticated shell baseline: [`Auralis/Auralis/Aura/Home/HomeTabView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Home/HomeTabView.swift)
- unauthenticated gateway baseline: [`Auralis/Auralis/Aura/Auth/GatewayView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Auth/GatewayView.swift) and [`Auralis/Auralis/Aura/Auth/AddressEntryView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Auth/AddressEntryView.swift)
- utility baseline: [`Auralis/Auralis/Gas/GasFeeEstimate.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Gas/GasFeeEstimate.swift)

Observed repeated patterns across those surfaces:

- full-screen scenic container pattern repeats between Gateway, Home, and Gas: full-bleed `GatewayBackgroundImage`, a `Color.background.opacity(0.3)` wash, then foreground content with safe-area-aware padding
- spacing rhythm is already fairly consistent around `12`, `16`, `20`, and outer screen padding in [`Auralis/Auralis/Aura/Auth/AddressEntryView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Auth/AddressEntryView.swift), [`Auralis/Auralis/Aura/Home/HomeTabView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Home/HomeTabView.swift), and [`Auralis/Auralis/Gas/GasFeeEstimate.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Gas/GasFeeEstimate.swift)
- surface card treatment is the strongest repeated component pattern: Home cards and Gas cards both use padded rounded glass containers with near-identical corner intent and section structure
- section-header pattern is clearly shared between Home tiles and Gas cards: leading aligned `SubheadlineFontText` or `HeadlineFontText`, optional status metadata, then the body content beneath
- CTA pattern splits into two deliberate families already present in the preferred surfaces:
  - hero/full-width capsule CTA in the gateway flow, especially the `Enter Auralis` button in [`Auralis/Auralis/Aura/Auth/AddressEntryView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Auth/AddressEntryView.swift)
  - smaller capsule or rounded actions inside cards in Home and Gas, such as `Open player`, `Open tokens`, and retry actions
- pills and badges are real but lighter-weight than the card problem: Home tile buttons and `BadgeLabel` in [`Auralis/Auralis/Aura/MainTabView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/MainTabView.swift) already share capsule padding, subtle tint, and outline treatment
- center-stacked intro sections are part of the desired gateway language: title, supporting copy, and CTA grouped vertically with generous horizontal padding in [`Auralis/Auralis/Aura/Auth/AddressEntryView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Auth/AddressEntryView.swift)

Out-of-scope for the initial primitive baseline:

- [`Auralis/Auralis/Aura/Auth/GuestPassCard.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Auth/GuestPassCard.swift) is a strong product-specific component and should be preserved as a specialized hero card, not flattened into a generic Phase 0 primitive
- ad hoc Newsfeed examples are still useful consumers later, but they should not define the primitive language ahead of Gateway, Home, and Gas

Chosen first primitive slice:

- `AuraScenicScreen`: standard full-screen foreground container for the scenic Gateway/Home/Gas presentation pattern
- `AuraSurfaceCard`: reusable rounded glass container for cards, tiles, status panels, and utility modules
- `AuraSectionHeader`: reusable header row for card/module titles, optional supporting metadata, and consistent leading alignment
- `AuraActionButton`: shared action style with at least two clear modes:
  - hero capsule CTA for gateway-style primary actions
  - compact surface action for card-level actions
- `AuraPill`: small capsule treatment for badges and lightweight labels
- defer a dedicated empty-state wrapper until Step 3 unless it falls out naturally from `AuraSurfaceCard` plus `AuraActionButton`

Why this slice first:

- it targets the patterns already reinforced by the three reference surfaces the product direction cares about most: Gateway, Home, and Gas
- it gives `P0-101B` and nearby surface work a stable scenic-container plus glass-surface baseline immediately
- it preserves the most intentional UI work already present instead of abstracting around weaker incidental examples
- it stays small enough to preserve the current Aura language without turning Phase 0 into a design-system rewrite

### Step 2. Choose the primitive home

Create one obvious place for shared Aura-level primitives.

Requirements:

- easy for future tickets to discover
- close to the UI layer
- not buried in `Helpers`

Exit criteria:

- new shared primitive files live in one consistent location

Step 2 decision:

- shared Aura-level primitives live in [`Auralis/Auralis/Aura/Primitives/`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Primitives)
- the folder sits beside `Auth`, `Home`, and `Newsfeed` instead of inside any one feature area
- the folder is intentionally under `Aura/`, not `Helpers/`, because these are product UI building blocks rather than generic utilities

Why this home:

- it is easy to discover from the main UI layer
- it keeps primitive ownership close to the surfaces they serve
- it gives Step 3 one stable landing zone for `AuraScenicScreen`, `AuraSurfaceCard`, `AuraSectionHeader`, `AuraActionButton`, and `AuraPill`
- it avoids pretending the current design language is framework-level or app-agnostic

Repository change made for Step 2:

- created [`Auralis/Auralis/Aura/Primitives/README.md`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Primitives/README.md) as the folder marker and placement rule for incoming primitive files

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

Step 3 implementation result:

- added [`Auralis/Auralis/Aura/Primitives/AuraScenicScreen.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Primitives/AuraScenicScreen.swift) for the full-screen scenic background and safe-area-aware foreground container used by Gateway/Home/Gas-style screens
- added [`Auralis/Auralis/Aura/Primitives/AuraSurfaceCard.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Primitives/AuraSurfaceCard.swift) for rounded glass surfaces with `soft` and `regular` variants matching the current Home and Gas treatments
- added [`Auralis/Auralis/Aura/Primitives/AuraSectionHeader.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Primitives/AuraSectionHeader.swift) for reusable title plus optional subtitle plus trailing accessory card headers
- added [`Auralis/Auralis/Aura/Primitives/AuraActionButton.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Primitives/AuraActionButton.swift) with `hero` and `surface` modes for gateway CTAs and card-level actions
- added [`Auralis/Auralis/Aura/Primitives/AuraPill.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Primitives/AuraPill.swift) for small capsule labels and lightweight status treatments

Implementation boundary for this step:

- the primitive layer now exists and compiles
- no proving-surface migration happened yet; adoption is reserved for Step 4
- `GuestPassCard` and other strongly product-specific views remain specialized components instead of being forced into the primitive API

Validation for Step 3:

- full project build succeeded after adding the primitive slice

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
