# P0-803 Tickets And Session Handoff

## Summary

Create the Phase 0 privacy and security hardening checklist and implement the required controls around redaction, reset, storage boundaries, and absence of key or signing material.

## Execution Order

1. Re-read the dependencies and confirm which ones are already complete.
2. Implement the minimum vertical slice that proves the ticket is real.
3. Cover the stated edge cases before expanding scope.
4. Run the ticket-specific validation path and record any blockers.

## Critical Edge Case

Prevent sensitive RPC or stack-trace leakage, guarantee full local reset, and ensure release-safe behavior even when debug tooling exists.

## Validation

Export receipts to verify redaction, wipe local data fully, confirm no private key storage exists, and ensure release-mode receipts omit raw stack traces.

## Handoff Rule

If this ticket is still blocked when work starts, do not build throwaway scaffolding unless the dependency note explicitly allows it.
