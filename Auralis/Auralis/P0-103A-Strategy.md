# P0-103A Strategy: Search entry points

## Status

Completed for the current slice

## Ticket

Implement the search entry points that make global search feel like a real product surface instead of a hidden utility.

## Dependencies

- `P0-101A`
- `P0-102A`
- `P0-103C`

## Strategy

- Make search discoverable from the shell and relevant launch surfaces.
- Keep the entry contract stable even while deeper resolution and results work continue.
- Route into the existing search root rather than inventing parallel search entry flows.

## Key Risk

Avoid scattering inconsistent search entry behavior across Home, chrome, and deep-link paths.

## Definition Of Done

- Search has clear entry points in the shell.
- Entry points land on the same search root contract.
- Later search deepening can build on those same launches.

## Validation Target

Launch search from the intended shell surfaces and preserve one consistent search entry contract.
