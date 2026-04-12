# P0-401 Tickets And Session Handoff

## Summary

Define the scoped ContextSnapshot schema for active account, chain scope, summary balances, module pointers, preferences, provenance, and freshness.

## Ticket Status

Completed for the current context-contract slice.

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
- added real module-pointer rows for the mounted Home launcher contract instead of keeping module ownership implicit
- replaced the hard-coded demo-data flag with the active account's guest-pass state
- expanded the chrome context inspector so schema consumers can see library pointers, preferences, placeholder-safe balance fields, and freshness metadata from the shared snapshot
- moved the chrome mode badge and context accessibility metadata onto snapshot-backed mode, freshness, and scope labels
- pushed snapshot scope text into the NFT empty-library shell state so that path stops free-styling account/chain context
- moved Home launcher and pinned-link copy onto snapshot-backed module and preference fields where that shell copy is already owned
- kept provider-backed balance handling honest without inventing fake values

Validation completed in this pass:

- project build succeeded after the schema changes
- live Xcode diagnostics returned no issues for the touched source and test files
- a fresh `BuildProject` run succeeded again during the closeout pass after the broader P0 artifact and ERC-20 surface updates
- focused context-suite identifiers were resolved successfully, so the intended next validation set is now explicit:
  - `ContextSnapshotTests/liveContextSourceBuildsVersionedSnapshot()`
  - `ContextSnapshotTests/contextSnapshotUsesLocalSchemaInputs()`
  - `ContextSnapshotTests/contextSnapshotSupportsMissingOptionalValues()`
  - `ContextSnapshotTests/contextSnapshotUsesTTLBackedStaleEvaluation()`
  - `ContextSnapshotTests/contextSnapshotUsesSharedFreshnessLabelContract()`
  - `ContextSnapshotTests/contextSnapshotClampsFutureRefreshTimestamps()`
  - `ContextSnapshotTests/refreshingFreshnessOverridesStaleLabel()`
  - `ContextSnapshotTests/contextSnapshotProvidesShellFacingSummary()`
  - `ContextServiceTests/contextServiceCoalescesDuplicateRequests()`
  - `ContextServiceTests/contextServiceAvoidsStaleOverwriteOnRapidAccountSwitch()`
  - `ContextServiceTests/contextServiceRefreshEmitsReceipt()`
  - `ContextServiceTests/contextServiceRaceKeepsReceiptScopeBoundToResolvedSnapshot()`
  - `ContextServiceTests/contextServiceLoadsNativeBalanceThroughProvider()`

Validation limitation:

- targeted context tests were discovered correctly, but the MCP Xcode test runner returned `No result` for the selected tests in this environment, so trustworthy targeted unit-test pass/fail evidence is deferred to the next pass by user direction

## Closeout

`P0-401` is now complete for the current Phase 0 contract because:

- the shared schema now covers the named ticket areas: scope, balances, library pointers, module pointers, preferences, provenance, and freshness
- the mounted shell consumers that own this contract now read the shared snapshot instead of mixing in parallel shell copy for those same fields
- downstream context growth is additive follow-on work rather than a blocker for closing this ticket
