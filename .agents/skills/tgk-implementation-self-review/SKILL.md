---
name: tgk-implementation-self-review
description: Implement or remediate an explicitly authorized TGK BotTradeFramework work item, then perform a disciplined, evidence-based self-review and handoff. After any CTO review rejection, use the mandatory adversarial remediation protocol. Compatible with Antigravity, Codex, Freebuff, and other agents supporting the Agent Skills format.
---

# TGK Implementation & Self-Review

## Purpose and authority

Deliver implementation work that is review-ready on the first submission where possible. Follow repository rules; this Skill adds a working method and review lessons, not a second policy source.

**Precedence:** user-approved task scope and contract → repository AGENTS.md → active Card SPEC.md and TEST_PLAN.md → this Skill and its references. If these conflict, stop and report the conflict; do not silently choose or change product behavior.

You are the user-selected Implementer, not the Product Owner or CTO. Do not approve your own work, expand scope, select/switch agents, run MT5 test suites reserved for the Product Owner, or commit/push unless explicitly authorized. This Skill is agent-neutral: follow it regardless of whether the implementing agent is Antigravity, Codex, Freebuff, or another compatible agent.

## Context-efficient startup

1. Read repository-root AGENTS.md first. Treat it as authoritative for project-wide rules, compile commands, test boundaries, and reporting requirements.
2. Read only the active Card's linked SPEC.md and TEST_PLAN.md, plus files explicitly referenced by them and the exact source/test files needed. Do not load the entire roadmap, architecture history, all Work Packages, or all review records by default.
3. Inspect git status --short --untracked-files=all before editing. Preserve all pre-existing staged, unstaged, and untracked changes.
4. Build a compact requirement-to-code/test map from active acceptance criteria. If the handoff is incomplete, a required file is missing, scope is ambiguous, or authorization is absent, stop and ask rather than reconstructing requirements from chat history.
5. Load references selectively:
   - State, persistence, hydration, validation, atomicity, idempotency, or recovery: read references/self-review-checklist.md.
   - Before final review, especially after a previous CTO rejection: read references/review-lessons.md.
   - Every remediation after a CTO Review Reject: read and follow references/adversarial-review-protocol.md in full. This protocol is mandatory and takes precedence over the lighter generic self-review sequence for remediation.
   - Before writing/updating the implementation report: read references/implementation-report-checklist.md.
   Do not read every reference automatically when it is unrelated to the task.

## Implementation workflow

1. **Confirm the contract.** Identify objective, allowed files, out-of-scope behavior, dependencies, invariants, failure behavior, and acceptance tests. Record uncertainty before coding.
2. **Trace the real path.** Follow the production call path from input/event through validation, state mutation, persistence, and observable result. Inspect callers and consumers where a change affects an API or shared include.
3. **Implement narrowly.** Make the smallest coherent change that satisfies the approved contract. Preserve public contracts unless the SPEC authorizes a change. Do not add speculative abstractions or unrelated cleanup.
4. **Prove intended behavior.** Add/update focused tests. A fixture must be a legal, reachable event path and reach the guard/invariant it claims to test. An earlier unrelated rejection does not prove a later invariant. Include BUY and SELL paths when direction changes behavior.
5. **Review failure paths.** Check invalid input, conflicting evidence, duplicate/replay behavior, append or persistence failure, partial progress, restart/restore, and stale state where applicable. Ensure failure does not leave partial or stale durable/runtime state.
6. **Run the Developer Compile Gate.** Follow exact current instructions and verified commands in AGENTS.md. Compile every affected MQL5 program; fix all errors and warnings until each reports 0 errors, 0 warnings. For changed .mqh files, identify and compile every including program. If unavailable, report the precise limitation and evidence; never infer success.
7. **Self-review.** Read the complete diff, run git diff --check, inspect final working-tree status, and apply relevant checklists. For remediation, re-check every prior finding and use the mandatory protocol above.
8. **Report evidence precisely.** Update the Card-linked IMPLEMENTATION_REPORT.md (or explicitly agreed report). Separate compile evidence from test evidence. State which tests were added/changed and which were run by whom. Do not run MT5 test suites when AGENTS.md reserves them for the Product Owner.
9. **Stop at handoff.** Report changed files, implementation summary, compile logs/results, tests run/not run, diff checks, known limitations, and unresolved questions. Do not claim Product Owner verification or CTO approval.

## Compile, test, and review gates

These are distinct gates and must never be conflated:
- **Compile PASS** establishes that the compiled program passed the compiler under the reported environment/settings. It does not establish runtime correctness, API semantics, requirement satisfaction, or recovery safety.
- **Implementer self-review PASS** means the Implementer completed the applicable checklist and can point to evidence. It is not independent approval.
- **Product Owner test PASS** means the Product Owner ran the required tests and reported results.
- **CTO Review PASS** is the independent architectural/contract review decision. Only the CTO can grant it.

Never describe Compile PASS as implementation approval or as proof that an acceptance criterion passed.

## Remediation after CTO review

A CTO Reject triggers a stricter mandatory process:
1. Read the current CODE_REVIEW.md, the specific finding handoff, active SPEC.md, TEST_PLAN.md, and all applicable Skill references.
2. Freeze scope to the authorized remediation files/findings. Do not redesign adjacent behavior. If a finding reveals a contract gap, stop and request direction.
3. Create a Finding Closure Matrix before editing: finding ID, required correction, acceptance condition, target code/test, and evidence required.
4. Complete all six activities in references/adversarial-review-protocol.md: Requirement-to-Code Trace, API Semantics Audit, Adversarial Review, Acceptance Evidence Audit, Finding Closure Matrix, and Final Diff & Report Audit.
5. Re-check all previous findings, including findings marked fixed in an earlier round. Verify the actual current code and tests, not only the prior report.
6. Run the applicable compile gate after code changes. Return the task to the Product Owner for required MT5 tests before the next formal CTO review.
7. Update the report with a finding-by-finding closure matrix and precise evidence. Mark a finding fixed only when its acceptance condition is demonstrated; otherwise leave it open with the reason and remaining evidence.
8. Do not claim that a check, test, staging state, or repository state was unchanged unless supported by before/after evidence.

## Completion boundary

Implementation is complete only when approved scope is implemented, the required compile gate is passed (or a compile blocker is explicitly reported), self-review is complete, and the report is accurate. Formal acceptance still requires Product Owner verification and independent CTO review under AGENTS.md.
