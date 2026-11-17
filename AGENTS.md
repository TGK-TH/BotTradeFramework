# Repository Working Agreement

## Project
TGK BotTradeFramework is a reusable MQL5 trading framework for multiple EAs, with supporting Python tooling. The repository is the technical source of truth. Do not treat this as a Grid-only repository.

## Mandatory startup context
At the beginning of every repository task:
1. Read this file and `PROJECT_STATUS.md`.
2. If the task concerns Grid, read `Docs/EAs/Grid/ROADMAP.md`, `Docs/EAs/Grid/README.md`, `Docs/EAs/Grid/architecture.md`, and `Docs/EAs/Grid/Testing/testing.md`.
3. Read the current Work Package's Phase Note and directly related Design/ADR documents before changing source.
4. Inspect current source files and tests; docs and memories can be stale.
5. Run `git status --short --untracked-files=all` before editing and preserve all pre-existing staged, unstaged, and untracked user work.
6. If Serena/MCP project access is available, consult the relevant project memories, especially `workflow/current-phase`, `workflow/development-and-trello-workflow`, `workflow/documentation`, and `conventions`.

Do not assume a prior chat transcript or model memory is visible to Codex. Durable instructions must live in this repository.

## Workflow and authorization
- Work in small, testable Work Packages/Phases with explicit scope and Acceptance Criteria.
- Do not silently expand product scope or change approved contracts.
- A user kickoff instruction that explicitly authorizes continuing Grid V1 through completion according to `Docs/EAs/Grid/ROADMAP.md` is blanket authorization for all normal in-scope Work Packages in that roadmap. Under that authorization, proceed sequentially after each successful gate; do not ask for approval again for routine next phases.
- Blanket authorization does NOT authorize live trading, Demo tests that send Trade Requests, touching non-test positions, destructive account actions, changing product scope, or choosing between unresolved material design alternatives. Stop and ask the user for these.
- If no blanket authorization is present, stop at phase boundaries and request approval before starting the next phase.
- Do not commit or push unless explicitly asked.
- Never place live trades or enable live trading as part of development/testing unless the user explicitly authorizes it.
- Explain changed files, behavior, rationale, validation, and next step after each Work Package.

## Repository and editing
- Repository root: `/Users/tachagon/Documents/13_Trade/1_Bot/BotTradeFramework`.
- Edit repository source only; MT5-linked folders are compile/runtime surfaces, not source-of-truth locations.
- Prefer targeted edits over unnecessary rewrites.
- Use 2-space indentation for new/edited code where appropriate.
- MQL5 formatting: for long/multi-parameter calls, put each parameter on its own line, use modest continuation indentation (two spaces beyond call indentation), and align closing `);` with call start. Follow `Experts/TGK/Tests/Grids/test_grid_types.mq5`.
- Preserve source identifiers, API names, enum names, and file paths exactly in technical docs.
- Never overwrite unrelated staged/unstaged changes. Do not use destructive Git commands such as reset, checkout, clean, or stash to make the tree appear clean.

## Test-first and regression policy
- Before a Grid feature/refactor, have the user run the latest relevant Grid Regression Tests and record the pre-change result.
- Check the actual current test inventory under `Experts/TGK/Tests/Grids/`; do not rely on stale hard-coded counts in old notes.
- Add/agree on Unit, Integration, Failure/Recovery, and Regression tests before implementation.
- Unit tests must not send Trade Requests. Demo integration tests are separate, require a dedicated safety plan and explicit user approval, and must be restricted to designated test positions.
- After source changes, run relevant tests and full Grid Regression Tests again.
- Static source checks, diff checks, and reading code are not MetaEditor/MT5 Compile/Runtime evidence.
- The user runs MetaEditor/MT5 compile/runtime tests and reports actual results unless an explicitly configured and verified compiler/test environment is available. Never claim tests were run if they were not.
- If a test fails, stop forward progression, diagnose/fix the failure, and repeat the relevant regression suite.

## Documentation and status
- Technical docs under `Docs/` must be written in Thai; retain actual code identifiers in English.
- After each completed Work Package, update:
  - `PROJECT_STATUS.md` with current status, changed files, checks, user-reported results, known issues, and exact next step.
  - Relevant Grid/Framework architecture, Phase, Testing, and ADR docs.
  - Serena `workflow/current-phase` memory when available.
- Keep `PROJECT_STATUS.md` concise at the top; detailed technical history belongs in Phase Notes.
- Distinguish Implemented, User-verified, Agreed-not-implemented, and Open.
- Verify local Markdown links and run `git diff --check`.
- Do not claim MetaEditor/MT5 compilation or runtime passed without the user's report.

## Grid V1 completion
- For Grid tasks, `Docs/EAs/Grid/ROADMAP.md` is the master roadmap and Definition of Done.
- Grid V1 is not complete merely because individual modules or test EAs pass. Production EA integration and end-to-end behavior must be validated against the roadmap.
- At completion, review every Definition of Done item, record evidence, and obtain the user's final acceptance.
- If Serena/MCP access fails, tell the user to check that the MCP Serena server is running.
