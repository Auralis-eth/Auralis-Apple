# P0-703 Dependency Note

## Status

Partially blocked

## Dependency Read

- `P0-602` should provide the action-policy gate.
- `P0-701B` should close or at least clearly identify major boundary bypasses.
- `P0-702` should define the trust-labeling contract where labeling is the expected mitigation.

## Safe First Slice

- Identify the first smoke-test targets now.
- Add tests only where the underlying rule is already real and stable enough.
- Prefer a small trustworthy smoke suite over broad brittle coverage.

## Rule For Planning

Do not write smoke tests for rules that still exist only as planning language.
