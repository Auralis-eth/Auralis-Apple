# PlannerCore

Goal → plan → orchestration mechanics for agentic features. Pure and authority-free:
it decides *what* to do, never *whether* it's allowed (that's `AutopilotCore`).

## Pieces

- **`PlanningGoal` / `Plan` / `PlanStep`** — a goal decomposes into an ordered list of
  steps, each grounded in a canonical `CapabilityID` and tagged with a `PlanStepKind`
  (`observe` → `assist` → `execute`), the rungs of the autonomy ladder.
- **`GoalPlanning`** — the planner protocol. Two implementations:
  - `DeterministicGoalPlanner` — keyword-triggered templates (`PlanTemplateCatalog`).
    Always available, fully testable, the fallback and evaluation baseline.
  - `ModelGoalPlanner` — FoundationModels-backed decomposition of novel goals. Every
    step it returns is re-grounded against the allowed capabilities, so a hallucinated
    capability is dropped, never run. Falls back to the deterministic planner when the
    model is unavailable.
- **Orchestration** — `SequentialPlanOrchestrator` runs a plan one step at a time,
  asking a `StepAuthorizing` for a verdict immediately before each step and handing
  cleared steps to a `StepExecuting`. It **halts at the first step that isn't cleared to
  run unattended**, which is what turns a plan into the Observe → Assist → Confirm loop.

## FoundationModels + evaluations

The planner's instruction text lives in `PlannerInstructions` so the shipping strings and
the tests reference the exact same source. `PlannerInstructionsTests` guards the strings
deterministically (every capability listed, the kind vocabulary taught, grounding drops
unknowns). `PlannerEvaluationTests` runs the Apple `Evaluations` harness over seed goals,
scoring capability-selection coverage — against the live model on device, and against the
deterministic baseline everywhere else.
