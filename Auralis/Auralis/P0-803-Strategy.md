# P0-803 Strategy: Privacy + security checklist for Phase 0

## Status

Blocked

## Ticket

Create the Phase 0 privacy and security hardening checklist and implement the required controls around redaction, reset, storage boundaries, and absence of key or signing material.

## Dependencies

P0-501, P0-303, with structural hardening completed through `P0-701B`

## Strategy

- Keep this as a later hardening pass.
- Build on the receipt foundation already in place and the degraded-mode rules from `P0-303`.
- Treat `P0-701B` as the relevant architectural hardening dependency, not monolithic `P0-701`.

## Key Risk

Privacy controls must be verified against real flows and real storage boundaries, not against an unfinished architecture.

## Definition Of Done

- Redaction, reset, and boundary checks are validated against the actual Phase 0 app shape.
- No key or signing material exists in the release surface.
- The checklist reflects the hardened architecture, not the pre-enforcement scaffolding.

## Validation Target

Export receipts to verify redaction, wipe local data fully, confirm no private key storage exists, and ensure release-mode receipts omit raw stack traces.
