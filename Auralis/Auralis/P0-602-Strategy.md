# P0-602 Strategy: Policy gate wrapper for actions

## Status

Completed for the current slice

## Ticket

Wrap shell and feature actions in a policy gate so restricted modes and action rules are enforced through one explicit decision layer.

## Dependencies

- `P0-601`
- `P0-101A`
- `P0-502` slices

## Strategy

- Build a reusable wrapper around action execution rather than sprinkling mode checks everywhere.
- Keep allow/deny decisions explicit and auditable.
- Make the wrapper easy to attach to later surfaces.

## Key Risk

Avoid creating a policy layer that is inconsistent, bypassable, or too implicit to reason about.

## Definition Of Done

- A reusable action policy gate exists.
- Restricted actions can be allowed or denied through one contract.
- The shell can later verify and log denials consistently.

## Validation Target

Wrap representative actions through the policy gate and preserve explicit allow/deny behavior.
