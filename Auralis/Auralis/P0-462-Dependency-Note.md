# P0-462 Dependency Note

## Status

Partially blocked

## Dependency Read

- `P0-461` should define the first stable holdings-row contract before token detail is treated as fully unblocked.
- `P0-101A` and current router work are enough for the screen/routing baseline.
- `P0-301` is already sufficient for native-balance and basic provider-backed metadata later.
- `P0-403` may support provenance/receipt deepening later, but it is not a first-slice blocker.

## Safe First Slice

- Prepare the token-detail contract and route shape in parallel with `P0-461`.
- Keep the first detail screen tolerant of sparse token metadata.
- Do not assume full ERC-20 enrichment is ready on day one.

## Rule For Planning

Do not let `P0-462` outrun the row/data contract established by `P0-461`.
