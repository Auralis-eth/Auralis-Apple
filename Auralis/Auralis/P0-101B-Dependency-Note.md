# P0-101B Dependency Note: Global Chrome UI

## Status

Sequenced, not blocked

## Dependency Read

Satisfied:

- `P0-101A` Root navigation structure
- `P0-201` Account model + persistence

Not required before starting:

- `P0-601` Mode system Observe v0

## Agreed Sequence

1. implement `P0-101B` first with fixed Observe presentation
2. formalize global mode-state ownership in `P0-601`

## Safe Work

- build the chrome shell
- wire account-switcher data from `P0-201`
- expose search and context-inspector entry points
- keep the badge visually fixed to Observe for the first pass

## What Should Wait

- final mode-state ownership
- receipt inclusion rules for mode state
- any future mode-switching behavior

## Rule For Planning

Do not keep `P0-101B` blocked just because `P0-601` exists. Build chrome first, then formalize mode state.
