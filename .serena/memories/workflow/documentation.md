# TGK BotTradeFramework Documentation Workflow

## Documentation hierarchy
- Technical Docs under `Docs/` are Thai; preserve source identifiers and paths exactly.
- `PROJECT_STATUS.md` is concise current status/next step; details belong in Phase Notes.
- `Docs/Framework/`: confirmed shared multi-EA contracts only.
- `Docs/EAs/<EA-Name>/`: EA-specific architecture, behavior, tests, decisions, and phases.
- `Docs/Development/`: repository-wide workflow and standards.
- `Docs/Decisions/README.md`: central ADR index; every ADR declares scope.

## WP/Phase completion
1. Update `PROJECT_STATUS.md` with state, changed files, checks, user-reported outcomes, known issues, and exact next step.
2. Update affected Thai technical docs, Phase Notes, Testing inventory, module/architecture docs, ADRs as appropriate.
3. Distinguish Implemented, User-verified, Agreed-not-implemented, and Open.
4. Verify docs against source/tests; do not infer Compile/Runtime PASS from static checks.
5. Run mandatory Documentation Consistency Gate: `Docs/Development/documentation-consistency-gate.md`.
6. Update Serena `workflow/current-phase` and relevant durable memories.
7. Verify local Markdown links and `git diff --check`; inspect the complete diff and working-tree state.
8. Do not close the WP/Phase if semantic contradictions or required checks remain unresolved.

## Documentation Consistency Gate
- Review all affected current-status surfaces: `PROJECT_STATUS.md`, roadmap/README, architecture, Testing, Phase Notes, ADRs, `AGENTS.md`, and relevant Serena memories.
- Compare implementation claims (including claims that something is absent) with source; test inventory/counts with actual test files/cases; verification claims with user-reported evidence.
- Search changed concepts and stale/contradictory claims across status/docs/memories. Preserve valid historical notes, but date/contextualize old state and link to current status.
- Confirm current WP state, architecture/integration boundary, exact next step, and explicit approval/safety boundaries agree.
- Read the full diff; run `git diff --check`; validate local Markdown links; recheck test inventory when affected.
- Completion report records documents reviewed/updated, semantic/search areas checked, evidence basis, checks/results, remaining issues, working-tree state, and exact next step.
- If any criterion fails, do not declare documentation or WP complete.

## Evidence and safety
- User performs MetaEditor/MT5 Compile/Runtime and reports results unless a verified compiler/test environment is explicitly available.
- Never claim MT5 tests passed without user confirmation.
- No commit/push unless explicitly requested.
- Preserve all pre-existing staged, unstaged, and untracked work.
- Stop at each WP/Phase boundary and require explicit user authorization before starting the next.
- Demo tests sending Trade Requests require separate explicit approval and Safety Gate; never place live trades.
