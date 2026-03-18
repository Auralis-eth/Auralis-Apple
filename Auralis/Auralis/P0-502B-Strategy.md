# P0-502B Strategy: Receipt logging verification + cleanup

## Status

Blocked

## Ticket

Perform the broad verification and cleanup pass for receipt logging after the major Phase 0 feature slices have already integrated their own receipt hooks.

## Dependencies

P0-502 feature slices, P0-503, P0-602, P0-703

## Strategy

- Do not use this ticket as an excuse to defer feature-level receipt integration.
- Use it to verify coverage, naming consistency, correlation discipline, and failure-path completeness.
- Clean up duplicate or inconsistent receipt emission only after the real flows exist.

## Key Risk

Global cleanup started too early turns into speculative work because the final flow graph does not exist yet.

## Definition Of Done

- The major Phase 0 flows have receipt coverage.
- Coverage gaps, duplicates, and inconsistent naming are cleaned up.
- Cross-flow verification is complete enough for release-hardening work.

## Validation Target

Run representative user flows across shell, Home, Search, Libraries, Context, and Receipts, then verify receipts are present, correlated where expected, and structurally consistent.
