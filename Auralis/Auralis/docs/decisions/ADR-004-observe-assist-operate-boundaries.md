# ADR-004: Observe, Assist, and Operate Boundaries

## Status

Accepted.

## Context

Auralis originally shipped as an Observe-only app. It could inspect public wallet data, maintain local receipts, and route users through read-oriented product surfaces, but it did not ship custody, transaction signing, arbitrary plugin execution, or agent operation.

The policy model already names high-risk actions such as `signMessage`, `approveSpending`, `draftTransaction`, and `runPlugin`. Those names are intentionally present before the features exist so the app has a shared vocabulary for denials, receipts, and future capability reviews.

## Decision

`AppMode` has been superseded by crypto-scoped `CryptoMode` with `Observe`, `Assist`, and `Operate` cases. These modes are not a global app read-only switch: they govern wallet/crypto capabilities, while non-crypto runtime work follows normal impact and confirmation rules.

Assist and Operate may execute high-risk actions only when the policy gate can require all of these controls for that action:

- address access that can sign, via `EthereumAddressAccess.canSign`
- an explicit capability grant for the exact `CapabilityID`
- a user confirmation step at the execution surface
- provenance for the requester, especially for plugins and agent/tool flows
- a durable receipt for both denied and approved decisions

Observe mode blocks `signMessage`, `approveSpending`, `draftTransaction`, and `runPlugin`. `runPlugin` is treated as a high-risk action so plugin or tool execution cannot become an Observe-mode bypass.

### Future Action Contracts

These contracts are requirements for signing, custody, WalletConnect, plugin, or agent work. The current runtime exposes the modes, but high-risk execution still depends on the evidence below.

| Action | Required before any approval path exists |
|--------|------------------------------------------|
| `signMessage` | Signing-capable address, exact message preview, explicit capability grant for `CapabilityID.signMessage`, user confirmation, requester provenance, denied and approved receipts. |
| `approveSpending` | Signing-capable address, token/spender/amount preview, explicit capability grant for `CapabilityID.approveSpending`, user confirmation, requester provenance, denied and approved receipts. |
| `draftTransaction` | Signing-capable address, chain allowlist and transaction preview/simulation, explicit capability grant for `CapabilityID.draftTransaction`, user confirmation, requester provenance, denied and approved receipts. |
| `runPlugin` | Plugin identity and provenance, requested capability manifest, explicit capability grant for `CapabilityID.runPlugin`, user confirmation for high-risk operations, denied and approved receipts. |

### Future Mode Upgrade Gate

Any PR that expands what `Assist` or `Operate` can execute must include policy tests proving that every high-risk action is still denied in Observe and is only allowed outside Observe when all of these are true: `EthereumAddressAccess.canSign`, exact capability grant, confirmation, requester provenance, and receipt recording. Expanding mode power without that proof is a security regression.

## Consequences

WEB3-001 preserved and tested the original denial boundary. The mode enum now exists, so the release decision moves from "may the cases exist?" to "which high-risk actions may each mode execute with proven evidence?"

Future signing, custody, WalletConnect, agent execution, or plugin operation remains blocked until policy tests prove that Observe denies all high-risk actions and future modes only allow them when signing access, capability grant, confirmation, provenance, and receipt requirements are satisfied.

## Follow-up: Signing Policy Shell

`WEB3-002` added the policy-only shell for future transaction drafting without adding a signer. `PolicyCore` now has a deny-by-default signing chain allowlist, transaction preview evidence, a `TransactionPreviewing` protocol boundary, and a readiness evaluator for high-risk actions. For `draftTransaction`, readiness requires signing-capable access, exact capability grant, requester provenance, explicit user confirmation, approved receipt evidence, a transaction preview/simulation result, and a target chain present in the signing allowlist.

This is intentionally not an executable signing flow. A future transaction draft model must bind to the preview protocol and call the readiness evaluator before it can construct or hand off any executable transaction.
