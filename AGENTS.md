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
- MQL5 formatting preference: for multi-parameter function/method calls, put each parameter on its own line when the call is long or has multiple arguments, use only a modest continuation indent (two spaces beyond the call indentation), and align the closing `);` with the call start. Follow `Experts/TGK/Tests/Grids/test_grid_types.mq5` as the example.
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

## Documentation workflow
- Organize technical docs by scope: `Docs/Framework/` for genuinely shared architecture/modules, `Docs/EAs/<EA-Name>/` for EA-specific behavior, `Docs/Development/` for repository-wide workflow, and `Docs/Decisions/` as the ADR index.
- Do not classify a module as shared merely because another EA might use it in the future; confirm its contract and responsibilities first.
- Technical documentation under `Docs/` must be written in Thai. Preserve actual source identifiers, class/function names, enum names, and file paths in their original spelling.
- Keep `PROJECT_STATUS.md` focused on current phase, completed work, user-reported checks, known issues, and the exact next step; use `Docs/` for durable technical explanations.
- At the end of each completed phase, update both `PROJECT_STATUS.md` and the relevant documentation. Create/update module docs when behavior or architecture changes, test docs when test coverage or procedures change, and ADRs when an important design decision is made.
- Phase notes should record scope, changed files, checks actually performed, user-reported compile/runtime outcomes, what the phase does not prove, and the next step.
- Clearly distinguish implemented behavior, user-verified behavior, agreed requirements not yet implemented, and open questions. Never document planned behavior as if it already exists.
- Avoid duplicate documents: update the most relevant existing document where possible and keep `Docs/README.md` as the index.

## Current workflow rule
- After each completed phase, update `PROJECT_STATUS.md` and relevant `Docs/` pages before handing work back to the user.
