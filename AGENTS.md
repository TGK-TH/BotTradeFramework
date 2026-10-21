# Repository Working Agreement

## Project
TGK BotTradeFramework: MQL5 trading systems and supporting Python tooling.

## Workflow
- Work in small, explicitly scoped phases.
- Do not start the next phase until the user confirms the current phase is complete and authorizes continuing.
- At the end of every completed phase, update `PROJECT_STATUS.md` with what changed, checks performed, the user's reported compile/test results, known issues, and the exact next step.
- Do not claim MetaEditor/MT5 compilation or runtime tests passed unless the user reports that result. Distinguish static/code checks from actual MT5 results.
- Never place live trades or enable live trading as part of development/testing unless the user explicitly authorizes it.
- Explain changed files, behavior, and rationale after each phase.
- If Serena/MCP access fails, tell the user to check that the MCP Serena server is running.

## Repository and editing
- Repository root: `/Users/tachagon/Documents/13_Trade/1_Bot/BotTradeFramework`.
- Treat this repository as the source of truth; do not edit separate MT5-linked copies.
- Use Serena/MCP tools for repository work when available and authorized.
- Use 2-space indentation for new/edited code where appropriate.
- Prefer targeted edits over unnecessary rewrites.

## Testing and regression policy
- Build and validate reusable tests before expanding Grid functionality.
- Keep MQL5 tests organized by domain under `Experts/TGK/Tests/`, for example `Framework/` and `Grids/`.
- Before starting a new Grid feature or refactor, run the relevant Grid regression tests first. If tests do not yet cover the relevant behavior, add/agree on tests before implementation.
- A smoke test is not the same as a full unit/integration test suite.
- Do not move to a later test phase without the user's report and approval.

## Current workflow rule
- After each completed phase, update `PROJECT_STATUS.md` before handing work back to the user.
