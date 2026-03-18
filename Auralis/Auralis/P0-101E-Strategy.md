# P0-101E Strategy: Design System Primitives (Phase 0 Minimal)

## Ticket

`P0-101E` defines the minimal reusable UI primitives shared by Home, Search, Libraries, and Receipts.

This is not a full design-system rewrite. It is a Phase 0 move to stop duplicating small view decisions across surfaces while preserving the existing Aura visual language.

## Locked Decisions

These decisions should stay fixed while implementing the ticket:

- scope is minimal, not a grand component framework
- the output should be reusable across multiple surfaces
- the system must work in light mode, dark mode, and higher-contrast situations
- the system must survive Dynamic Type, including very large accessibility sizes
- small devices and large screens must both remain usable

## Current State

The app already has pieces of visual language, but they are scattered:

- [`Auralis/Auralis/Aura/Text+Font.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Text+Font.swift)
- [`Auralis/Auralis/Aura/Home/AuraStyleKnobs.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Home/AuraStyleKnobs.swift)
- [`Auralis/Auralis/Aura/Home/ProfileCardView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Home/ProfileCardView.swift)
- [`Auralis/Auralis/Aura/Home/EnergyCardView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Home/EnergyCardView.swift)
- [`Auralis/Auralis/Aura/Newsfeed/Components/NFTSortButton.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Newsfeed/Components/NFTSortButton.swift)
- [`Auralis/Auralis/Aura/Newsfeed/Components/TorchToggleButton.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Newsfeed/Components/TorchToggleButton.swift)

The repo does not yet appear to have one obvious home for shared surface-level primitives like:

- section spacing rules
- consistent cards and containers
- small status badges or pills
- consistent action buttons
- shared empty/loading surface wrappers

That means Phase 0 should focus on extracting only the pieces that are visibly repeated or immediately needed by upcoming tickets.

## Constraints

- do not redesign the whole app
- do not create a token matrix bigger than the app can realistically maintain
- do not force every existing screen to migrate in one pass
- preserve the current Aura look instead of introducing a second visual language
- avoid primitives that are so abstract they hide layout intent

## Strategy

### 1. Build a small primitives layer, not a design-system religion

The goal is a handful of shared view building blocks with obvious usage.

Good Phase 0 candidates:

- a shared screen container with consistent padding and width behavior
- a shared surface card/container style
- a shared badge or pill component
- a shared primary and secondary icon/text action style
- a shared section header row
- a shared empty-state wrapper

Bad Phase 0 candidates:

- a complete semantic color taxonomy for every future product state
- a deep token engine with dozens of indirections
- a component catalog that the app does not actually use yet

Why:

- `P0-101E` should lower friction for nearby tickets, not become a side quest

### 2. Put the primitives near the Aura UI, not in a fake platform layer

The app is still a single target and the design language is product-specific.

A good home would be a focused area under `Auralis/Auralis/Aura/` for reusable UI building blocks rather than a giant global utilities folder.

Why:

- these are product primitives, not generic framework code
- putting them close to the UI makes adoption easier and keeps intent visible

### 3. Start from typography, spacing, and surfaces

Most UI inconsistency comes from three places:

- text styling
- spacing rhythm
- container treatment

If those are stabilized first, later tickets like global chrome and search can compose faster without every screen hand-tuning paddings and capsule shapes again.

Why:

- these are the highest-leverage primitives
- they affect both compact and large layouts without requiring a complicated architecture

### 4. Prefer composable view wrappers over opaque mega-components

Example shape:

- one reusable surface container
- one badge primitive
- one icon action primitive
- one section header primitive

Then feature screens compose them directly.

Avoid:

- one universal component trying to act like card, panel, list row, header, and toolbar item depending on twenty parameters

Why:

- Phase 0 should stay readable
- future tickets will move faster if the primitives are obvious at the call site

### 5. Bake accessibility into the primitive contracts

The ticket already calls out:

- Dynamic Type
- dark mode
- contrast
- very small devices
- large screens

That means primitives should be designed so they naturally:

- wrap and truncate intentionally
- preserve tap target size
- avoid hard-coded heights where text can grow
- use adaptive spacing rather than brittle pixel-perfect stacks

Why:

- accessibility bugs become expensive when copied into every screen

### 6. Migrate only the minimum proving surfaces first

`P0-101E` does not need a repo-wide UI migration.

A good proving set is:

- one Home surface
- one News/Search-adjacent surface
- one utility/detail-style surface

That gives enough coverage to prove the primitives are real without turning the ticket into a sweeping redesign.

## What This Ticket Should Deliver

By the end of `P0-101E`, the repo should have:

- a small set of reusable UI primitives with clear ownership
- a consistent spacing and container baseline
- at least a few real surfaces using the primitives
- primitives that are safe for Dynamic Type and color-mode variation
- enough shared pieces that `P0-101B` and related UI work can build faster

## What This Ticket Should Not Try To Solve

Do not over-claim. `P0-101E` does not need to solve:

- a complete product-wide redesign
- full theming infrastructure
- every state variant the app may ever need
- total migration of all screens
- platform-wide component APIs for hypothetical future modules

## Proposed Implementation Order

### Slice A: Primitive inventory and location

- choose the folder/location for shared Aura primitives
- identify the first small set of components to extract

Definition of done:

- there is one obvious place to look for shared UI primitives

### Slice B: Foundation primitives

- implement screen/container layout primitive
- implement surface card/container primitive
- implement badge primitive
- implement action/button primitive
- implement section header primitive

Definition of done:

- the primitives compile
- each one has a narrow purpose
- each one is reusable without feature-specific knowledge

### Slice C: Proof-of-use migration

- adopt the primitives in a few existing screens
- remove duplicated styling only where the new primitive clearly replaces it

Definition of done:

- the primitives are used by real production views
- the migration proves the API is practical

### Slice D: Validation

- light mode and dark mode review
- large Dynamic Type review
- compact-width review
- optional snapshot coverage if the team wants it

Definition of done:

- the primitives hold up visually and structurally under the ticket’s stated edge cases

## Recommended Read Order

1. [`Auralis/Auralis/Aura/Text+Font.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Text+Font.swift)
2. [`Auralis/Auralis/Aura/Home/AuraStyleKnobs.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Home/AuraStyleKnobs.swift)
3. [`Auralis/Auralis/Aura/MainAuraShell.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/MainAuraShell.swift)
4. [`Auralis/Auralis/Aura/MainTabView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/MainTabView.swift)
5. [`Auralis/Auralis/Aura/Home/ProfileCardView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Home/ProfileCardView.swift)
6. [`Auralis/Auralis/Aura/Home/EnergyCardView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Home/EnergyCardView.swift)
7. [`Auralis/Auralis/Aura/Newsfeed/Components/NFTSortButton.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Newsfeed/Components/NFTSortButton.swift)
8. [`Auralis/Auralis/Aura/Newsfeed/Components/TorchToggleButton.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Newsfeed/Components/TorchToggleButton.swift)

## Rule For Implementation

If a primitive is not clearly reused, not clearly needed by near-term tickets, or not clearly preserving the existing Aura language, it probably does not belong in `P0-101E`.
