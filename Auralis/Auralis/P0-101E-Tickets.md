# P0-101E Tickets And Session Handoff

## Summary

Establish the minimal Aura UI primitive layer shared by Home, Gateway, Gas, and later shell surfaces.

## Ticket Status

Completed and in maintenance mode for the current Phase 0 primitive layer.

## Execution Checklist

### 1. Confirm primitive scope

- [x] Keep the primitive set intentionally small.
- [x] Put primitives under `Aura/Primitives/` rather than a fake global platform layer.
- [x] Preserve the Aura visual language instead of starting a redesign.

### 2. Deliver the primitive layer

- [x] Add a scenic screen wrapper.
- [x] Add the shared surface card.
- [x] Add the shared section header.
- [x] Add the shared action button.
- [x] Add the shared pill/badge primitive.

### 3. Prove use on real production surfaces

- [x] Migrate Gateway to the scenic screen and hero action seam.
- [x] Migrate Home modules and related cards to the shared surface/header/button set.
- [x] Migrate Gas to the shared scenic/surface/pill baseline.

### 4. Validate the vertical slice

- [x] Verify the primitive-backed surfaces build cleanly.
- [x] Verify Dynamic Type and compact-width behavior on migrated surfaces.
- [x] Keep product-specific auth components out of the generic primitive layer.

## Implementation Notes

- The primitive home is `Auralis/Auralis/Aura/Primitives/`.
- Delivered primitives: `AuraScenicScreen`, `AuraSurfaceCard`, `AuraSectionHeader`, `AuraActionButton`, `AuraPill`.
- Real production adoption already exists across Gateway, Home, Gas, and downstream shell surfaces.
- Accessibility and layout hardening were applied during the primitive rollout rather than left as a later cleanup debt.

## Validation Notes

- The dependency report records repeated successful project builds during the primitive rollout.
- Smaller targeted previews rendered successfully for primitive-backed surfaces during implementation.
- Contract coverage exists in `AuralisTests/AuraPrimitiveContractTests.swift` and `AuralisTests/AuraTrustLabelContractTests.swift` for the primitive/trust-label layer now consumed across shell surfaces.

## Critical Edge Case

Primitives must survive Dynamic Type, compact widths, and color-mode variation without becoming opaque mega-components.

## Handoff Rule

If a new component is not clearly reused and does not preserve the existing Aura language, keep it product-specific instead of inflating the primitive layer.
