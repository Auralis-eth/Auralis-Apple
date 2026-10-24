# AutopilotCore

The authority layer for agentic plans. It supplies the `StepAuthorizing` decision that
`PlannerCore`'s orchestrator consults, composing the app's **existing** policy substrate
(`PolicyCore`) rather than inventing a parallel one.

## The ladder

`AutopilotAuthorizer.authorize(_:in:)` maps each plan step to a verdict:

| Step | Condition | Verdict |
|------|-----------|---------|
| `observe` / `assist` | read-only or advisory | `autopilot` (runs unattended) |
| `execute` | policy denies (e.g. app in Observe mode) | `blocked` |
| `execute` | policy allows, not a trusted routine | `needsConfirmation` |
| `execute` | policy allows **and** trusted routine | `autopilot` |

Execute steps map to a `PolicyControlledAction` via `CapabilityActionMapping` and go
through the same `PolicyActionGating` the rest of the app uses. A `TrustedRoutineAllowlist`
only removes the per-run confirmation tap — it **never** bypasses the policy gate.

The active `CryptoMode` comes from the same policy gate used by the rest of the app. Observe blocks
crypto execution, Assist escalates it for approval, and Operate can proceed only when the policy gate
and routine trust both allow it.

`AutopilotRunner` wires planner + authorizer + executor into one `run(_:)` call.

## Phase 1 status

This package is scaffolded infrastructure, not a policy bypass. Signing, approvals, transaction
drafting, and high-risk wallet actions are governed by `CryptoMode` and routed through policy.
Performance metrics and successful routine history are descriptive only; they never increase authority
or remove governance gates.
