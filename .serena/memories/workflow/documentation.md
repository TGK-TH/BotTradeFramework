# TGK BotTradeFramework Documentation Workflow

User approved a Hybrid Documentation workflow; all technical Docs must be written in Thai. Preserve actual source identifiers, class/function/enum names, and file paths in their original spelling.

When a phase completes:
1. Update `PROJECT_STATUS.md` with phase state, changed files, checks, user-reported compile/runtime outcomes, known issues, and exact next step.
2. Update the relevant existing `Docs/` pages; create new docs only when needed.
3. Update module docs for behavior/architecture changes, testing docs for test/procedure changes, ADRs for important design decisions, and phase notes for the work completed.
4. Clearly distinguish implemented behavior, user-verified behavior, agreed requirements not yet implemented, and open questions. Never present planned behavior as implemented.
5. Verify docs match actual source, check local links/paths, and run `git diff --check`.

`PROJECT_STATUS.md` is the short current-status/next-step page. `Docs/` stores durable technical explanations.

Created Thai docs on 2026-10-23:
- `Docs/README.md`
- `Docs/Architecture/overview.md`
- `Docs/Modules/grid-identity.md`
- `Docs/Modules/grid-persistence.md`
- `Docs/Testing/mql5-test-framework.md`
- `Docs/Testing/grid-testing.md`
- `Docs/Decisions/README.md`
- `Docs/Decisions/ADR-001-grid-identity-and-persistence.md`
- `Docs/Decisions/ADR-002-chart-id-is-not-persistence-identity.md`
- `Docs/Phases/phase-grid-integration-testing.md`

Root `README.md` links to `Docs/README.md`. `AGENTS.md` now requires Thai technical docs and the phase documentation workflow.

Grid Integration Testing was marked complete based on user-reported results. Next planned development is Grid State Machine, but do not begin until explicitly authorized. Before Grid feature/refactor, run relevant regression tests first. User performs MQL5 compile/runtime tests; do not claim results without user confirmation.