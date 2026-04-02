# P0-602 Tickets And Session Handoff

## Summary

Wrap shell and feature actions in a reusable policy gate so restricted modes and action rules are enforced consistently.

## Ticket Status

Startable.

## Execution Checklist

### 1. Confirm the action-gate contract

- [ ] Re-read `P0-602-Strategy.md` and `P0-602-Dependency-Note.md`.
- [ ] Confirm which actions should use the first shared wrapper.
- [ ] Confirm how allow/deny outcomes should be surfaced and logged.

### 2. Implement the policy gate

- [ ] Add the shared allow/deny wrapper contract.
- [ ] Route representative actions through it.
- [ ] Keep gate ownership centralized.

### 3. Cover required edge cases

- [ ] Denied actions fail safely and visibly.
- [ ] Allowed actions do not regress existing happy paths.
- [ ] The gate remains understandable in Observe-mode and normal mode.

### 4. Validate the vertical slice

- [ ] Verify representative actions respect the gate.
- [ ] Verify denials can be explained or logged.
- [ ] Record broader rollout work outside this ticket.

## Critical Edge Case

The gate must be explicit enough that later enforcement and smoke tests can prove there are no obvious bypasses.

## Validation

Wrap representative actions through one allow/deny contract and preserve explicit gate outcomes.

## Handoff Rule

If a proposed change is really broad rollout or enforcement auditing, split it into `P0-701B` or `P0-703` instead of stretching `P0-602`.
