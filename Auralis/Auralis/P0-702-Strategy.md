# P0-702 Strategy: Untrusted input labeling

## Status

Startable

## Ticket

Label untrusted input clearly across the shell so users can distinguish system-known values from user- or provider-supplied values.

## Dependencies

- `P0-401`
- `P0-602`
- search and routing surfaces that expose raw input

## Strategy

- Apply a consistent labeling contract to untrusted or externally sourced values.
- Keep the labels understandable rather than overly technical.
- Start where the trust boundary matters most.

## Key Risk

Avoid inconsistent or overly subtle trust labeling that users will miss or contributors will bypass.

## Definition Of Done

- A clear untrusted-input labeling contract exists.
- Representative surfaces use it.
- Safety/no-bypass work can build on the same labeling rules.

## Validation Target

Render representative untrusted values with clear labeling and keep trust boundaries legible in the UI.
