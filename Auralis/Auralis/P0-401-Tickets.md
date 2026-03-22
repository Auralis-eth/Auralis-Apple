# P0-401 Tickets And Session Handoff

## Summary

Define the scoped ContextSnapshot schema for active account, chain scope, summary balances, module pointers, preferences, provenance, and freshness.

## Execution Order

1. Re-read the dependencies and confirm which ones are already complete.
2. Implement the schema-first slice that proves the ticket is real without inventing provider data.
3. Cover the stated edge cases before expanding scope.
4. Run the ticket-specific validation path and record the remaining `P0-302` / `P0-402` blockers explicitly.

## Critical Edge Case

Missing values must remain valid, provenance rules must stay consistent, and a version field should prepare for future schema changes.

## Validation

Build minimal valid snapshots, verify provenance and timestamps for populated fields, and confirm persistence serialization if stored.

## Handoff Rule

Do not build throwaway scaffolding. It is acceptable to ship the typed schema and compatibility layer now, but any missing balance, receipt-link, or TTL behavior must remain clearly documented as deferred downstream work.
