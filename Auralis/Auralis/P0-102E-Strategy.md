# P0-102E Strategy: Home empty/first-run state

## Status

Startable

## Ticket

Implement the Home empty and first-run state so the dashboard stays intentional when the active account has little or no useful local data.

## Dependencies

- `P0-102A`
- `P0-201`
- `P0-401` slices
- `P0-403` slice

## Strategy

- Build the empty/first-run Home state on top of the existing dashboard shell, not as a parallel Home design.
- Make the screen helpful without pretending data exists.
- Reuse current shell context and account signals where available.
- Keep the scenic/glass Home language intact.

## Key Risk

Avoid a dead-end empty state that fights later Home sections or confuses users about whether the app is loading, empty, or broken.

## Definition Of Done

- Home has a deliberate first-run or sparse-data state.
- Calls to action are clear and route to real next steps.
- The state coexists cleanly with later populated Home sections.

## Validation Target

Show a coherent Home experience for first-run, low-data, and no-activity conditions without breaking the mounted dashboard shell.
