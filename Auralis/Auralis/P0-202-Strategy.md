# P0-202 Strategy: Address validation + normalization

## Status

Partially blocked

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
- Shared visual messaging can later converge with `P0-101D`.

## Validation Target

Block invalid addresses, save valid normalized addresses, copy normalized values exactly, and trim pasted whitespace before validation.
