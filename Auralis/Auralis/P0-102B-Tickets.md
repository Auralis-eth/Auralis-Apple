# P0-102B Tickets And Session Handoff

## Summary

Deepen the active account summary card on Home so it acts like a real identity and scope surface.

## Ticket Status

Startable.

## Execution Checklist

### 1. Confirm card scope and inputs

- [ ] Re-read `P0-102B-Strategy.md` and `P0-102B-Dependency-Note.md`.
- [ ] Confirm which account, chain, and context fields belong on the first card.
- [ ] Confirm which existing temporary visuals are acceptable to preserve.

### 2. Implement the strengthened summary card

- [ ] Add the real identity/scope fields to the Home summary card.
- [ ] Keep the card readable and intentionally scoped.
- [ ] Preserve existing Home visual language.

### 3. Cover required edge cases

- [ ] Missing optional context values degrade cleanly.
- [ ] Chain/account switches update the card correctly.
- [ ] The card remains useful even when richer balances or activity data are absent.

### 4. Validate the vertical slice

- [ ] Verify the card reflects the active account and scope.
- [ ] Verify the card stays visually coherent in sparse-data conditions.
- [ ] Record any profile-management or settings follow-ons outside this ticket.

## Critical Edge Case

The card must stay trustworthy when optional context fields are absent or lag behind richer future integrations.

## Validation

Show a stronger active account summary using real shell/account data without overreaching into profile-management work.

## Handoff Rule

If the card wants richer editing or management behavior, split that into later tickets instead of stretching `P0-102B`.
