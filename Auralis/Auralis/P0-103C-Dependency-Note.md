# P0-103C Dependency Note

## Status

Completed for the current slice

## Dependency Read

- `P0-103A` is enough to expose entry points, but `P0-103C` defines how those queries actually resolve.
- `P0-201` provides account/address grounding for wallet-oriented resolution.
- `P0-301` and `P0-302` can support provider-backed lookups later without blocking a deterministic local-first pipeline.

## Safe First Slice

- Keep the pipeline typed and local-first where possible.
- Add provider-backed branches only where the contract is already clear.
- Keep the pipeline separate from results rendering and history storage.

## Rule For Planning

Do not let the resolution pipeline dissolve back into view-local conditional logic.
