# P0-102C Strategy: OS-level shortcuts / modules section

## Status

Completed for the current slice

## Ticket

Deepen the Home modules section so it behaves like a useful launcher layer instead of a loose collection of tiles.

## Dependencies

- `P0-102A`
- `P0-101A`
- `P0-201`
- `P0-102E` complete for sparse-data Home behavior
- `P0-102B` complete for the active account summary card

## Strategy

- Keep the current Home atmosphere and glassy tile language.
- Make the module area more deliberate and OS-like in its shortcuts/launcher behavior.
- Prioritize real routing and useful affordances over decorative expansion.
- Treat the Home shell, sparse-state card, and summary card as already-landed neighbors; `P0-102C` should deepen the launcher layer, not reopen those areas.

## Key Risk

Avoid bloating the launcher area with too many overlapping shortcuts or mixing unfinished future modules into the first pass.

## Definition Of Done

- The Home modules section feels intentional.
- Shortcut tiles route to real destinations.
- The module layout leaves room for future additions without another rewrite.
- The launcher remains coherent under both sparse-data and populated Home conditions already established by `P0-102E`.

## Validation Target

Launch real product surfaces from the Home modules section and keep the section useful on both sparse and populated accounts.

## Current Read

- The Home modules section now acts as a deliberate launcher layer with primary module cards and secondary shell shortcuts.
- The current slice is validated with unit tests around launcher ordering, sparse-state reachability, and exclusion of pretend destinations.
- Remaining work is future launcher expansion or deeper destination behavior, not a missing baseline modules surface.
