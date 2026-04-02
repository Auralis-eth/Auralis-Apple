# P0-801 Tickets And Session Handoff

## Summary

Define the deterministic demo dataset and offline mode behavior for Phase 0.

## Ticket Status

Startable.

## Execution Checklist

### 1. Confirm the demo/offline contract

- [ ] Re-read `P0-801-Strategy.md` and `P0-801-Dependency-Note.md`.
- [ ] Confirm what counts as deterministic demo data.
- [ ] Confirm how offline mode differs from stale cached mode and provider failure.

### 2. Implement the first demo/offline behavior

- [ ] Define the first deterministic demo dataset contract.
- [ ] Define or implement the first offline-mode shell behavior.
- [ ] Keep provenance explicit across surfaces.

### 3. Cover required edge cases

- [ ] Demo and live data are not visually conflated.
- [ ] Offline mode does not look like a broken shell.
- [ ] Cached stale state stays distinct from deliberate demo/offline state.

### 4. Validate the vertical slice

- [ ] Verify deterministic demo behavior is repeatable.
- [ ] Verify offline mode remains understandable.
- [ ] Record richer offline/product behavior outside this ticket.

## Critical Edge Case

Users must be able to tell the difference between demo truth, cached truth, stale truth, and unavailable truth.

## Validation

Run the app in deterministic demo/offline conditions and preserve clear provenance across the shell.

## Handoff Rule

If a proposed solution creates a shadow app path outside the normal shell/data contracts, stop and redesign it.
