# P0-701A Strategy: Layered Module Boundaries Structural Scaffolding

## Status

In Progress

## Ticket

Establish the early code-structure scaffolding that keeps UI, services, providers, policy, receipts, and storage moving toward clear separation before full enforcement is possible.

## Dependencies

P0-101A, P0-301, P0-402

## Strategy

- Start with folder, seam, and dependency-injection structure that supports later enforcement.
- Prefer explicit service entry points over direct UI access to lower layers.
- Avoid over-promising compile-time enforcement before the service graph is real.
- Land the shell-facing seams now: shared service hub, receipt-store factory, context-source builder, and policy-action service.

## Key Risk

If this starts too late, feature tickets bake in cross-layer shortcuts that become expensive to unwind later.

## Current Slice

- `MainAuraView` now owns shared shell mode state instead of re-creating it inside the tab view.
- A live `ShellServiceHub` now provides shell-facing seams for context-source building, receipt-store creation, policy handling, and service construction.
- Receipt-backed account, NFT refresh, and receipt reset flows now build through a shared receipt-store factory seam instead of naming `SwiftDataReceiptStore` everywhere.
- The shell policy UI now talks to a policy action service instead of constructing receipt storage directly.

## Definition Of Done

- Structural seams exist for the main read-only paths.
- UI-facing code has obvious service entry points.
- Later enforcement work can tighten rules without a full rewrite.

## Validation Target

Review imports, ownership, and dependency injection paths to ensure new feature work can build on the intended boundaries instead of bypassing them.

## Remaining Work

- Move broader context orchestration behind the future `P0-402` service layer.
- Extend the same service-hub approach to more feature-specific read paths as they become real consumers.
- Reserve compile-time or folder-level enforcement for `P0-701B`.
