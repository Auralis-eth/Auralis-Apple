# P0-102E Strategy: Home empty/first-run state

## Status

Partially blocked

## Ticket

Implement the first-run Home experience with add-address or ENS CTA and optional demo entry, then transition directly into the full dashboard.

## Dependencies

P0-201, with `P0-101D` as a recommended parallel foundation

## Strategy

- Start once the account and shell flow are clear.
- Do not wait for the full shared empty-state language before building the first-run path.
- Converge the final visual language with `P0-101D` once those patterns settle.

## Key Risk

Invalid input should not eject the user from onboarding, and provider failure after adding an account must still leave the shell usable.

## Definition Of Done

- First-run users see a clear add-account or demo path.
- Successful account entry transitions directly into Home.
- The final surface can later align with `P0-101D` without a rewrite.

## Validation Target

Fresh install shows CTA, valid address lands on Home without relaunch, invalid address is blocked clearly, and demo mode stays visibly reversible.
