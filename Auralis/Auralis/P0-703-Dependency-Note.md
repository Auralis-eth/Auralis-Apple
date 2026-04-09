# P0-703 Dependency Note

## Status

Completed for the current first smoke-test slice

## Dependency Read

- `P0-602` should provide the action-policy gate.
- `P0-701B` should close or at least clearly identify major boundary bypasses.
- `P0-702` should define the trust-labeling contract where labeling is the expected mitigation.
- Those three prerequisites now exist in code strongly enough to support a small stable smoke suite.

## Safe First Slice

- Identify the first smoke-test targets now.
- Add tests only where the underlying rule is already real and stable enough.
- Prefer a small trustworthy smoke suite over broad brittle coverage.
- Keep deeper feature-by-feature smoke expansion for later tickets instead of bloating this first baseline.

## Rule For Planning

Do not write smoke tests for rules that still exist only as planning language.
