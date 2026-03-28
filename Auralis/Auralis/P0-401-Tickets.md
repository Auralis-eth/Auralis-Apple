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

## Completion Summary

- strengthened `ContextSnapshot` so local schema sections no longer rely only on placeholder `nil` values when the app already has local data
- wired playlist count and scoped receipt count into the context contract through local, non-provider-backed inputs
- replaced the hard-coded demo-data flag with the active account's guest-pass state
- expanded the chrome context inspector so schema consumers can see library pointers, preferences, placeholder-safe balance fields, and freshness metadata from the shared snapshot
- kept the remaining deferred behavior explicit instead of inventing fake provider-backed balance data

## Remaining Notes

This ticket is not yet a defensible "100% complete" close because the schema still carries intentionally deferred fields:

- some preference and downstream module fields remain placeholder-safe until their owning surfaces become real

Validation completed in this pass:

- project build succeeded after the schema changes

Validation limitation:

- targeted context tests were discovered correctly, but the Xcode test runner returned `No result` for the selected tests in this environment, so there is no trustworthy pass/fail signal from that run
