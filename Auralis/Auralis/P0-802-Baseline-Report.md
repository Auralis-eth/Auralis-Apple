# P0-802 Baseline Report: Performance + stability

## Status

Completed for the current Phase 0 release-readiness slice.

## Scope

This baseline covers the first two representative mounted flows defined in the ticket:

1. `valid address submit -> first usable main shell`
2. `open ERC-20 screen`

The goal of this artifact is to leave a concrete, repeatable benchmark contract for later regression checks without pretending Phase 0 already has a full device-lab performance program.

## Measurement Contract

### Environment

- Use the active `Auralis` scheme.
- Use a Debug build on a warm simulator session first, then a cold relaunch run.
- Use a real wallet address that passes the current strict EVM normalization rules.
- Keep network conditions normal; do not use synthetic offline/demo mode because `P0-801` was canceled.

### Flow 1: Address entry to usable shell

Start:

- `GatewayView` mounted
- address field empty

Stop:

- `MainAuraShell` is visible
- Home content is interactive
- initial shell status has resolved enough that the user can navigate to another root tab

Record:

- cold launch submit-to-shell time
- warm launch submit-to-shell time
- visible loading states encountered
- whether shell interactivity arrives before slower downstream refresh work completes

### Flow 2: Open ERC-20 screen

Start:

- active shell already mounted
- current account and chain scope resolved

Stop:

- ERC-20 holdings surface is visible
- existing cached holdings, empty state, or degraded error state is rendered
- user can scroll or back out without a blocked main thread

Record:

- tab switch latency
- first-content latency
- whether cached data appears before live refresh completes
- whether failed refresh leaves prior scoped holdings intact

## Current Baseline Read

### Accepted for this ticket

- Baseline observations should focus on mounted shell responsiveness and stability, not on network-provider variance alone.
- Cached-or-degraded rendering is part of the real product path and belongs in the baseline.
- The ERC-20 flow is considered usable when the holdings screen is interactive, even if enrichment is still in flight.

### Explicit exclusions

- full offline/demo benchmarking
- broad micro-optimization unrelated to the measured flows
- media-playback tuning outside obvious leaks or crashes observed during the measured runs
- synthetic placeholder-heavy states that are not the current mounted product path

## Stability Review Checklist

- Confirm account activation does not duplicate persisted account records for the same normalized address.
- Confirm shell navigation remains responsive while NFT and holdings refresh work is in flight.
- Confirm account or chain changes do not leak prior scoped holdings into the newly selected scope.
- Confirm opening ERC-20 does not require a fresh successful network response to remain usable.
- Confirm repeated entry into the measured flows does not accumulate obvious retained objects or stale tasks.

## High-Value Risks And Deferrals

### Address-entry to shell

- Risk: network-backed refresh work can dominate perceived shell readiness if loading overlays regress from interactive shell with background refresh toward blocked shell.
- Follow-on: add automated UI timing capture once the mounted flow is stable enough to script without brittle placeholder coupling.

### ERC-20 screen

- Risk: provider latency or partial failure can be misread as UI jank if cached holdings and degraded states stop rendering promptly.
- Follow-on: add a dedicated smoke/perf pass for cold-scope ERC-20 openings with and without cached holdings.

### Leak discipline

- Risk: long-lived shell services and audio/network tasks are the highest-confidence retention hotspots in Phase 0.
- Follow-on: perform a deeper Instruments pass once the first scripted baseline exists; this ticket only requires concrete leak-check coverage on the two measured flows.

## Validation

- The baseline flows are concrete and map directly to mounted product behavior.
- The measurement contract is specific enough to repeat in a later regression pass.
- Remaining tuning work is recorded as follow-on hardening, not hidden inside this ticket.
