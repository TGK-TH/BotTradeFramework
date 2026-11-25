# TGK BotTradeFramework Development + Trello Workflow V2

## Parallel Planning, Sequential Execution (effective 2026-11-25)
- CTO-led Design/Planning may cover multiple related Cards concurrently. Create/update all necessary Cards and prepare multiple SPEC/TEST_PLAN documents in parallel; move planning Cards to `In Progress` when CTO planning is active.
- Explicitly label each such Card `CTO Planning / Contract Design only; implementation not authorized`. `In Progress` is shared by Planning and Implementation; Card descriptions/comments must distinguish them.
- Product behavior, trading behavior, and new WP scope still require explicit Product Owner approval.
- Implementation by the user-selected agent (Codex or Freebuff), User Verification, and CTO formal Code Review remain sequential, one Card at a time. Each implementation requires final SPEC/TEST_PLAN, explicit PO authorization, and a fresh pre-change no-trade Grid Regression baseline.


## Authority
- Repository source, tests, and Markdown docs are the technical source of truth.
- Trello board **TGK Grid Bot** tracks work item status, ownership, blockers, and approvals; keep Cards linked to repository specifications and evidence.
- `AGENTS.md` is the mandatory repository instruction entry point for developer agents.

## Roles
- **ChatGPT — CTO / Technical Lead:** co-designs architecture/contracts with the user, breaks work into WP/Phase/implementation Cards, writes developer specifications, performs formal Code Review only after user-reported Compile/Test PASS, records actionable findings, and updates technical documentation after approval.
- **Codex or Freebuff — Developer Agent:** the user chooses the Implementer for each Card. The current preference is Codex first until monthly quota is exhausted, then Freebuff. The selected agent reads repository files directly (especially `AGENTS.md`, Card-linked `SPEC.md`, and `TEST_PLAN.md`), implements only the approved scope, and writes an implementation report. Neither agent may depend on prior chat history or Serena memories; Freebuff must not use Serena MCP.
- **User — Product Owner / QA:** approves design/scope, selects and invokes the Implementer, runs MetaEditor/MT5 Compile and Tests, reports actual outcomes, and explicitly authorizes subsequent work.
- ChatGPT does not implement or patch source code on behalf of the selected Implementer unless the user explicitly changes the role agreement. ChatGPT prepares neutral handoffs and does not choose or switch agents.

## Per-Card workflow
1. Agree on Design, Contract, scope, dependencies, Acceptance Criteria, and tests; obtain user approval.
2. Create/update the Trello Card and prepare separate `SPEC.md` and `TEST_PLAN.md` files. State allowed files and out-of-scope work.
3. User selects and starts Codex or Freebuff implementation. The selected agent reads repository files directly and implements only the approved Card.
4. The selected agent records changed files, summary, tests run/not run, exact results, compile evidence, and unresolved issues in `IMPLEMENTATION_REPORT.md`; move Card to User Verification.
5. User performs MetaEditor/MT5 Compile and the specified tests. If any fail, the same Implementer fixes and user repeats verification. Formal ChatGPT Code Review does not start before user reports PASS.
6. After user reports PASS, move Card to Code Review and notify ChatGPT.
7. ChatGPT reviews actual source/diff against SPEC, TEST_PLAN, architecture, Acceptance Criteria, and user-reported evidence. Record outcome/findings in `CODE_REVIEW.md`.
8. Review status: `APPROVED`, `CHANGES_REQUESTED`, or `BLOCKED`. Findings include ID, severity, file/location, problem, required fix, and acceptance condition.
9. For changes requested, the same user-selected Implementer fixes only the findings; user compiles/tests again before the next formal review cycle.
10. After user verification PASS and CTO review APPROVED, ChatGPT updates relevant docs/status. Card becomes Done only with required documentation and user confirmation.
11. Stop at every WP/Phase boundary and request explicit user approval before starting the next.

## Handoff files
- `SPEC.md`: Objective, Scope/Out of Scope, Dependencies, Allowed Files, Technical Contract, Constraints, Acceptance Criteria.
- `TEST_PLAN.md`: Preconditions, Test IDs/scenarios, Expected Results, Regression Coverage, Safety Restrictions.
- `IMPLEMENTATION_REPORT.md`: Changed Files, Implementation Summary, Tests Run/Not Run, Exact Results, Remaining Issues.
- `CODE_REVIEW.md`: Review Status and actionable Findings.
- These files and the approved Trello Card must contain enough context for either Codex or Freebuff to work without relying on chat history.

## Trello lifecycle
- Target flow: `Product Backlog -> Ready -> In Progress -> User Verification -> Code Review -> Done`.
- If user verification fails, return to `In Progress` for fixes by the same assigned Implementer.
- If CTO review requests changes, use `Changes Requested` (or an agreed equivalent), then repeat User Verification before formal review again.
- Reuse existing board lists where possible. Do not create/rename lists without user agreement; if the board lacks a matching stage, agree on mapping first.
- Never mark Done from implementation completion alone.

## Safety and quality
- Work in small, independently reviewable logical deliverables; do not split atomic transitions merely to reduce Card size.
- No silent Design/Contract changes or scope expansion. Stop and ask the user if a material design decision is needed.
- Preserve all existing user changes. No reset/checkout/clean/stash or overwriting unrelated work. No commit/push unless explicitly asked.
- Before new Grid feature/refactor work, remind the user to run the latest Grid Regression Tests and record a pre-change baseline.
- Unit tests must not send Trade Requests. Demo tests that send requests require separate explicit user approval and designated test positions. Never trade live.
- User runs MetaEditor/MT5 Compile/Runtime unless an explicitly configured and verified environment is available. Never claim unverified results.
- After each completed WP/Phase, update `PROJECT_STATUS.md`, relevant Thai technical docs, test inventory, and applicable durable project memory; run Documentation Consistency Gate, validate local links, inspect full diff, and run `git diff --check`.

## Chat boundaries
- Keep one bounded primary Work Item/Phase per chat. Proactively tell the user when a new chat is warranted and provide a complete kickoff prompt.
- Handoffs must state exact current status, approved scope/decisions, changed files, user-reported test evidence, unresolved issues, and next authorized step.
