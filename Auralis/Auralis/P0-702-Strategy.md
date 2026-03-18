# P0-702 Strategy: Untrusted input labeling (metadata hygiene v0)

## Status

Blocked

## Ticket

Treat remote metadata as untrusted, label it where displayed, and ensure untrusted strings cannot create app intents beyond normal navigation.

## Dependencies

P0-452, P0-462, P0-602, with `P0-101D` as a recommended parallel foundation

## Strategy

- Wait for the detail surfaces and policy gate that give this ticket real meaning.
- Use `P0-101D` only for final warning-pattern convergence.
- Keep trust-labeling rules independent from empty-state styling.

## Key Risk

Control characters, spoofed domains, and oversized text must not break layout or imply trust.

## Definition Of Done

- Untrusted metadata is clearly labeled.
- It cannot create special app behavior beyond safe navigation and explicit user interaction.
- Visual warning language can align later with `P0-101D`.

## Validation Target

Show untrusted badges, ensure metadata cannot trigger behavior, require explicit interaction for external links, and sanitize control characters safely.
