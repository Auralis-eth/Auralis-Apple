# P0-101E Dependency Report

This document records the dependency posture, implementation status, and downstream impact for `P0-101E`.

`P0-101E` is complete.

## Ticket

JIRA: `P0-101E`

Goal:

- establish a minimal Aura UI primitive layer
- prove those primitives in real production surfaces
- harden the migrated surfaces for layout and accessibility

## Dependency Status

Hard dependencies:

- none

Primary reference surfaces used to define the primitive language:

- [`Auralis/Auralis/Aura/Auth/GatewayView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Auth/GatewayView.swift)
- [`Auralis/Auralis/Aura/Auth/AddressEntryView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Auth/AddressEntryView.swift)
- [`Auralis/Auralis/Aura/Home/HomeTabView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Home/HomeTabView.swift)
- [`Auralis/Auralis/Gas/GasFeeEstimate.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Gas/GasFeeEstimate.swift)

Downstream consumers unblocked or supported by this work:

- `P0-101B` Global Chrome UI
- Home/Search/Libraries/Receipts surface work that needs a shared layout and component baseline

Explicitly out of primitive scope:

- [`Auralis/Auralis/Aura/Auth/GuestPassCard.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Auth/GuestPassCard.swift) remains a product-specific component, not a generic primitive

## Delivered Primitive Layer

Primitive home:

- [`Auralis/Auralis/Aura/Primitives/`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Primitives)

Primitive files delivered:

- [`Auralis/Auralis/Aura/Primitives/AuraScenicScreen.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Primitives/AuraScenicScreen.swift)
- [`Auralis/Auralis/Aura/Primitives/AuraSurfaceCard.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Primitives/AuraSurfaceCard.swift)
- [`Auralis/Auralis/Aura/Primitives/AuraSectionHeader.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Primitives/AuraSectionHeader.swift)
- [`Auralis/Auralis/Aura/Primitives/AuraActionButton.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Primitives/AuraActionButton.swift)
- [`Auralis/Auralis/Aura/Primitives/AuraPill.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Primitives/AuraPill.swift)
- [`Auralis/Auralis/Aura/Primitives/README.md`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Primitives/README.md)

Primitive responsibilities:

- `AuraScenicScreen`: scenic full-screen shell used by Gateway/Home/Gas-style presentation
- `AuraSurfaceCard`: shared rounded glass surface for cards, tiles, and utility panels
- `AuraSectionHeader`: shared card/module header with optional subtitle and trailing accessory
- `AuraActionButton`: shared action treatment for hero CTA and compact in-surface actions
- `AuraPill`: shared lightweight badge/status treatment

## Production Adoption

Gateway proving surface:

- [`Auralis/Auralis/Aura/Auth/GatewayView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Auth/GatewayView.swift) now uses `AuraScenicScreen`
- [`Auralis/Auralis/Aura/Auth/AddressEntryView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Auth/AddressEntryView.swift) now uses the hero `AuraActionButton`

Home proving surface:

- [`Auralis/Auralis/Aura/Home/HomeTabView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Home/HomeTabView.swift) now uses `AuraSurfaceCard` for the main modules
- [`Auralis/Auralis/Aura/Home/HomeTabView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Home/HomeTabView.swift) now uses `AuraSectionHeader` and `AuraActionButton` inside module content
- [`Auralis/Auralis/Aura/Home/EnergyCardView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Home/EnergyCardView.swift) now uses `AuraSectionHeader`

Gas proving surface:

- [`Auralis/Auralis/Aura/MainTabView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/MainTabView.swift) now uses `AuraScenicScreen` for the Gas shell
- [`Auralis/Auralis/Gas/GasFeeEstimate.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Gas/GasFeeEstimate.swift) now uses `AuraSurfaceCard`, `AuraSectionHeader`, `AuraActionButton`, and `AuraPill`

## Accessibility And Layout Hardening

Applied hardening:

- hero CTA is no longer nested inside another `Button`
- Home tiles stack vertically in compact-width and accessibility-size layouts
- primitive text treatments now wrap instead of assuming single-line space
- decorative divider lines and icon-only ornamentation were removed from the accessibility tree where appropriate
- Gas header now exposes a cleaner spoken summary and state value

Touched accessibility/layout files:

- [`Auralis/Auralis/Aura/Auth/AddressEntryView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Auth/AddressEntryView.swift)
- [`Auralis/Auralis/Aura/Home/HomeTabView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Home/HomeTabView.swift)
- [`Auralis/Auralis/Aura/Primitives/AuraActionButton.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Primitives/AuraActionButton.swift)
- [`Auralis/Auralis/Aura/Primitives/AuraPill.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Primitives/AuraPill.swift)
- [`Auralis/Auralis/Aura/Primitives/AuraSectionHeader.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Primitives/AuraSectionHeader.swift)
- [`Auralis/Auralis/Gas/GasFeeEstimate.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Gas/GasFeeEstimate.swift)

## Validation

Completed validation:

- project builds succeeded after Step 3, Step 4, Step 5, and the follow-up accessibility pass
- targeted previews rendered successfully for primitive-backed action/header/card cases
- live file diagnostics succeeded on the migrated files during the implementation passes

Session limitation:

- heavier full-screen preview renders were unreliable in this session, so the strongest evidence came from successful builds, smaller rendered previews, and the adaptive layout/accessibility changes applied to production code

## Completion Summary

`P0-101E` is complete because:

- a minimal set of shared Aura UI primitives exists
- the primitives have a clear home and consistent naming
- real production surfaces use them
- accessibility and layout hardening was applied to the migrated surfaces
- the work reduces repeated Aura UI markup without introducing a large design-system maintenance burden
