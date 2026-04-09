# P0-103C Tickets And Session Handoff

## Summary

Implement the search resolution pipeline that turns raw queries into typed, routable search intents.

## Ticket Status

Completed for the current slice.

## Execution Checklist

### 1. Confirm the query contract

- [x] Re-read `P0-103C-Strategy.md` and `P0-103C-Dependency-Note.md`.
- [x] Confirm which query types the first pipeline must support.
- [x] Confirm where local-first vs provider-backed resolution should split.

Query-contract notes:

- The current slice supports wallet and ENS matches to profile detail, contract and collection matches to NFT collection detail, token-symbol matches to ERC-20 detail, and NFT-item matches to NFT detail.
- The first pipeline stays local-first and deterministic.
- Provider-backed enrichment remains a later follow-on rather than a blocker for typed resolution.

### 2. Implement the resolution pipeline

- [x] Build typed resolution stages from raw query to resolved search intent.
- [x] Keep parsing/resolution separate from results rendering.
- [x] Preserve stable behavior for supported query types.

Implementation notes:

- `SearchDestination` now carries the typed destination contract out of parsing.
- Local matches now include enough route data to open profile detail, NFT collection detail, NFT item detail, or ERC-20 token detail without view-local guesswork.
- `SearchLocalIndex` now uses scoped token holdings for symbol matches so token-detail routing is grounded in real local rows instead of loose NFT metadata.

### 3. Cover required edge cases

- [x] Invalid or ambiguous queries fail safely.
- [x] Local-first resolution does not misclassify supported inputs.
- [x] Provider-backed resolution is optional where a local answer already exists.

### 4. Validate the vertical slice

- [x] Verify supported query types resolve deterministically.
- [x] Verify unsupported queries fail safely into later no-results behavior.
- [x] Record any deeper provider enrichment outside this ticket.

## Critical Edge Case

The resolution pipeline must stay typed and deterministic even when raw user input is messy or ambiguous.

## Validation

Resolve supported query types deterministically and preserve a stable contract for later search-result rendering.

## Handoff Rule

If a requested change is really about UI rendering or history persistence, move it to the later search tickets instead of stretching `P0-103C`.
