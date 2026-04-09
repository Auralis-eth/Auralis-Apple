# P0-703 Strategy: No bypass paths smoke tests

## Status

Completed for the current first smoke-test slice

## Ticket

Add smoke-test coverage that proves key safety, policy, and boundary rules do not have obvious bypass paths.

## Dependencies

- `P0-602`
- `P0-701B`
- `P0-702`

## Strategy

- Use smoke tests to verify the highest-value rules first.
- Focus on practical bypasses, not abstract purity.
- Keep the suite narrow enough to stay maintainable.
- Prefer pure-rule and small-router smoke tests over UI automation for this phase.

## Key Risk

Avoid building smoke tests before the underlying policy/boundary rules are real enough to test meaningfully.

## Definition Of Done

- A smoke-test baseline exists for key no-bypass rules.
- The tests target real risk areas.
- The suite can grow as enforcement stabilizes.
- Policy denial, policy allow-list behavior, trust labeling, and owned-tab routing now have a dedicated smoke baseline.

## Validation Target

Prove representative bypass paths are blocked or labeled correctly without turning the suite into a brittle integration maze.
