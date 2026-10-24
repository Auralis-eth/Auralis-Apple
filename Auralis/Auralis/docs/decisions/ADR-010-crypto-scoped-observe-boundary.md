# ADR-010: Crypto-Scoped Observe Boundary

## Status

Accepted. Refines ADR-004.

## Context

ADR-004 introduced an Observe-only posture. As Auralis matured into an operator runtime (governed
workflows, Mission Control, artifacts, playbooks), reading ADR-004 as a *whole-app* read-only lock became
wrong: it would forbid ordinary, safe operation of non-crypto domains (music library CRUD, playlists,
metadata, artifacts, playbooks, local preferences) that carry none of the irreversible-funds risk that
justified the lock.

## Decision

The Observe posture is **scoped to crypto/wallet capabilities only**. Concretely:

- **Gated (CryptoMode):** `.wallet`-category capabilities — `signMessage`, `approveSpending`,
  `draftTransaction`, and any future custody / signing / WalletConnect. Observe blocks them, Assist
  escalates them for approval, and Operate may proceed only when checks, evidence, receipts, and impact
  confirmation rules pass.
- **Fully operational:** every other capability category (`music`, `playback`, `plugin`, …). These
  support create/read/update/delete under normal impact rules (confirmation for external-impact work).

Governance keys off capability category, not a global app mode:

- `RuntimeCore.CapabilityDomain.isCrypto(_:)` == (`CapabilityRegistry` category `.wallet`).
- `PolicyCore.AppMode` was renamed **`CryptoMode`**; the compatibility alias has been removed.
- The app's default judge is `AutopilotCore.DomainJudge`: crypto → block in `.observe`; non-crypto →
  impact rules (readOnly/reversibleWrite → allow, externalImpact/highRisk → escalate; failed
  deterministic check → block).

## Consequences

- Non-crypto operators, routines, and playbooks run and produce artifacts today; the On-Chain Watch
  operator is blocked in Observe with a durable denial receipt.
- ADR-004's mode upgrade gate still applies to crypto: expanding Assist/Operate execution requires full
  controls (signing access, capability grant, confirmation, provenance, receipts) proven by tests.
- The word "mode" in operator surfaces refers to the *crypto* posture, not an app-wide lock.
