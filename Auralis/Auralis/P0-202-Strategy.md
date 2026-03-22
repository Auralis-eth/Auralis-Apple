# P0-202 Strategy: Address validation + normalization

## Status

Implemented

## Ticket

Validate and normalize EVM addresses early, present them consistently, and reject invalid formats before persistence.

## Dependencies

P0-201, with `P0-101D` as a recommended parallel foundation for shared messaging

## Strategy

- Treat validation behavior as startable now.
- Do not wait for the full shell-level pattern library to settle before locking validation rules.
- Later align errors and empty states with `P0-101D`.

## Key Risk

Whitespace trimming, non-EVM formats, and ambiguous ENS-in-address-field behavior must be deterministic.

## Definition Of Done

- Invalid addresses are blocked early.
- Valid addresses are normalized consistently.
- Phase 0 stores and copies lowercase canonical `0x...` addresses.
- EIP-55 checksum display is explicitly deferred beyond Phase 0.
- Shared visual messaging can later converge with `P0-101D`.

## Completion Note

Implemented as a strict account-entry validation pass:

- `AccountStore` now treats account input normalization as strict EVM address validation instead of permissive embedded-address extraction
- whitespace trimming and lowercase canonicalization are deterministic
- 40-hex inputs without `0x` are normalized to canonical `0x...`
- ENS names in account-entry surfaces are explicitly rejected in this ticket and deferred to `P0-203`
- auth copy and QR validation now match the actual supported input contract
- the auth entry surface exposes the exact normalized address that Phase 0 will persist and copy
- checksum display is intentionally not part of the Phase 0 contract

## Validation Target

Block invalid addresses, save valid normalized addresses, copy normalized values exactly, and trim pasted whitespace before validation.
