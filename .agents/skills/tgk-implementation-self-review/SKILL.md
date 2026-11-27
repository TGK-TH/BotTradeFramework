---
name: tgk-implementation-self-review
description: Implement or remediate an explicitly authorized TGK BotTradeFramework work item, then perform a disciplined self-review, required MQL5 compile gate, and evidence-based handoff. Use for coding tasks, bug fixes, test changes, and CTO review remediation in this repository; do not use as a substitute for Product Owner approval or independent CTO review.
---

# TGK Implementation & Self-Review

## Purpose and authority

Deliver implementation work that is review-ready on the first submission where possible. Follow the repository's current rules; this Skill adds a working method and review lessons, not a second policy source.

**Precedence:** user-approved task scope and contract → repository `AGENTS.md` → active Card's `SPEC.md` and `TEST_PLAN.md` → this Skill and its references. If these conflict, stop and report the conflict; do not silently choose or change product behavior.

You are the user-selected Implementer (Codex, Freebuff, or another compatible agent), not the Product Owner or CTO. Do not approve your own work, expand scope, select/switch agents, run MT5 test suites reserved for the user, or commit/push unless explicitly authorized.

## Context-efficient startup

1. Read repository-root `AGENTS.md` first. Treat it as the authoritative source for project-wide rules, compile commands, test boundaries, and reporting requirements.
2. Read only the active Card's linked `SPEC.md` and `TEST_PLAN.md`, plus files explicitly referenced by them and the exact source/test files needed for the task. Do not load the entire roadmap, architecture history, all Work Packages, or all review records by default.
3. Inspect `git status --short --untracked-files=all` before editing. Preserve all pre-existing staged, unstaged, and untracked changes.
4. Build a compact requirement-to-code/test map from the active acceptance criteria. If the handoff is incomplete, a required file is missing, scope is ambiguous, or authorization is absent, stop and ask rather than reconstructing requirements from chat history.
5. Load a reference file from this Skill only when its topic applies:
   - State, persistence, hydration, validation, atomicity, or idempotency work: read `references/self-review-checklist.md`.
   - Before final review, especially after a previous CTO rejection: read `references/review-lessons.md`.
   Do not read every reference automatically.

## Implementation workflow

1. **Confirm the contract.** Identify objective, allowed files, out-of-scope behavior, dependencies, invariants, failure behavior, and acceptance tests. Record any uncertainty before coding.
2. **Trace the real path.** Follow the production call path from input/event through validation, state mutation, persistence, and observable result. Inspect callers and consumers where a change affects an API or shared include.
3. **Implement narrowly.** Make the smallest coherent change that satisfies the approved contract. Preserve existing public contracts unless the SPEC authorizes a change. Do not add speculative abstractions or unrelated cleanup.
4. **Prove the intended behavior.** Add or update focused tests. A test fixture must be a legal, reachable event path and must reach the guard/invariant it claims to test. A rejection at an earlier unrelated lookup or validation step does not prove a later invariant. Include both BUY and SELL paths when direction changes behavior.
5. **Review failure paths.** Check invalid input, conflicting evidence, duplicate/replay behavior, append or persistence failure, partial progress, restart/restore, and stale state where applicable. Ensure failure does not leave partial or stale durable/runtime state.
6. **Run the Developer Compile Gate.** Follow the exact current instructions and verified commands in `AGENTS.md`. Compile every affected MQL5 program; fix all errors and warnings until each reports `0 errors, 0 warnings`. For changed `.mqh` files, identify and compile every including program. If the environment is unavailable, report the precise limitation and evidence; never infer success.
7. **Self-review before handoff.** Read the complete diff, run `git diff --check`, inspect the final working-tree status, and apply the relevant checklist in `references/self-review-checklist.md`. Re-check every prior CTO finding if this is a remediation.
8. **Report evidence precisely.** Update the Card-linked `IMPLEMENTATION_REPORT.md` (or explicitly agreed report). Separate compile evidence from tests. State which tests were added/changed and which were run by whom. The Implementer must not run MT5 test suites when `AGENTS.md` reserves them for the Product Owner.
9. **Stop at handoff.** Report changed files, implementation summary, compile logs/results, tests run/not run, diff checks, known limitations, and unresolved questions. Do not claim Product Owner verification or CTO approval.

## Remediation after CTO review

- Read the current `CODE_REVIEW.md` and the specific finding handoff. Fix only findings and files within the authorized remediation scope.
- For every finding, translate the required fix and acceptance condition into a local checklist before editing.
- Do not interpret a finding as permission to redesign adjacent behavior. If the finding exposes a contract gap, stop and request CTO/Product Owner direction.
- Re-run the applicable compile gate after every code change. Return the task to the Product Owner for the required MT5 test run before the next formal CTO review.
- In the report, map each finding ID to the exact code/test change and evidence that satisfies its acceptance condition.

## Completion boundary

Implementation is complete only when the approved scope is implemented, the required compile gate is passed (or a compile blocker is explicitly reported), the self-review is complete, and the report is accurate. Formal acceptance still requires Product Owner verification and independent CTO review under `AGENTS.md`.
