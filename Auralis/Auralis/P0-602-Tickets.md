# P0-602 Tickets And Session Handoff

## Summary

Wrap shell and feature actions in a reusable policy gate so restricted modes and action rules are enforced consistently.

## Ticket Status

Completed for the current slice.

## Execution Checklist

### 1. Confirm the action-gate contract

- [x] Re-read `P0-602-Strategy.md` and `P0-602-Dependency-Note.md`.
- [x] Confirm which actions should use the first shared wrapper.
- [x] Confirm how allow/deny outcomes should be surfaced and logged.

Action-gate notes:

- The first shared gate now covers the execution-style actions already mounted in the product-policy surfaces.
- Observe mode blocks `signMessage`, `approveSpending`, and `draftTransaction`.
- Plugin and tool execution remain allowed in this slice, per product direction, so the gate distinguishes controlled actions from blocked actions.
- Denials continue to surface with a user-facing message and a `policy.denied` receipt.

### 2. Implement the policy gate

- [x] Add the shared allow/deny wrapper contract.
- [x] Route representative actions through it.
- [x] Keep gate ownership centralized.

Implementation notes:

- The old Observe-only execution helper is now a shared `ActionPolicyGate`.
- Shell service wiring now exposes a generic policy-gating service instead of an Observe-specific handler type.
- Representative actions in the Profile policy surfaces run through that shared gate.
- The policy preview surfaces no longer claim plugin execution is blocked.

### 3. Cover required edge cases

- [x] Denied actions fail safely and visibly.
- [x] Allowed actions do not regress existing happy paths.
- [x] The gate remains understandable in Observe-mode and normal mode.

### 4. Validate the vertical slice

- [x] Verify representative actions respect the gate.
- [x] Verify denials can be explained or logged.
- [x] Record broader rollout work outside this ticket.

Validation notes:

- The project build passes with the shared gate in place.
- Focused tests now prove both sides of the contract: blocked actions emit denial receipts, and allowed plugin actions pass through without denial receipts.
- Broader rollout across all future action surfaces remains later work for `P0-701B` and `P0-703`.

## Critical Edge Case

The gate must be explicit enough that later enforcement and smoke tests can prove there are no obvious bypasses.

## Validation

Wrap representative actions through one allow/deny contract and preserve explicit gate outcomes.

## Handoff Rule

If a proposed change is really broad rollout or enforcement auditing, split it into `P0-701B` or `P0-703` instead of stretching `P0-602`.
