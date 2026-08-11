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

Because the shipping app pins `AppMode` to `.observe`, every state change resolves to
`blocked` today. That's the honest state of the world: the machinery is real and tested,
and higher autonomy switches on only when policy does.

`AutopilotRunner` wires planner + authorizer + executor into one `run(_:)` call.
