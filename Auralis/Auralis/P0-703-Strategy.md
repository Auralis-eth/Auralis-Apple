# P0-703 Strategy: No bypass paths smoke tests

## Status

Blocked

## Ticket

Create the repeatable security smoke tests for Observe-only enforcement, PolicyGate coverage, and absence of any execute or signing bypass path.

## Dependencies

P0-602, P0-701B, P0-502B

## Strategy

- Wait until policy and enforcement are real enough to test.
- Treat `P0-701B` as the relevant boundary-enforcement dependency, not monolithic `P0-701`.
- Use `P0-502B` as the broad receipt verification companion.

## Key Risk

The smoke suite must catch later bypasses, not just certify the state of the code on the day it is written.

## Definition Of Done

- The checklist and tests reflect the real enforced architecture.
- Policy-denied and no-bypass expectations are repeatable.
- The suite fits the later hardening stage instead of pretending early scaffolding is enough.

## Validation Target

Run the checklist across all screens and, if feasible, automate enumeration of action handlers to confirm PolicyGate coverage.
