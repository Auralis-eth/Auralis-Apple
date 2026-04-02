# P0-103C Tickets And Session Handoff

## Summary

Implement the search resolution pipeline that turns raw queries into typed, routable search intents.

## Ticket Status

Startable.

## Execution Checklist

### 1. Confirm the query contract

- [ ] Re-read `P0-103C-Strategy.md` and `P0-103C-Dependency-Note.md`.
- [ ] Confirm which query types the first pipeline must support.
- [ ] Confirm where local-first vs provider-backed resolution should split.

### 2. Implement the resolution pipeline

- [ ] Build typed resolution stages from raw query to resolved search intent.
- [ ] Keep parsing/resolution separate from results rendering.
- [ ] Preserve stable behavior for supported query types.

### 3. Cover required edge cases

- [ ] Invalid or ambiguous queries fail safely.
- [ ] Local-first resolution does not misclassify supported inputs.
- [ ] Provider-backed resolution is optional where a local answer already exists.

### 4. Validate the vertical slice

- [ ] Verify supported query types resolve deterministically.
- [ ] Verify unsupported queries fail safely into later no-results behavior.
- [ ] Record any deeper provider enrichment outside this ticket.

## Critical Edge Case

The resolution pipeline must stay typed and deterministic even when raw user input is messy or ambiguous.

## Validation

Resolve supported query types deterministically and preserve a stable contract for later search-result rendering.

## Handoff Rule

If a requested change is really about UI rendering or history persistence, move it to the later search tickets instead of stretching `P0-103C`.
