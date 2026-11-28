# Repository Working Agreement

## Project
TGK BotTradeFramework is a reusable MQL5 trading framework for multiple EAs, with supporting Python tooling. The repository is the technical source of truth. Do not treat this as a Grid-only repository.

## Mandatory startup context
At the beginning of every repository task:
1. Read this file (`AGENTS.md`).
2. **ChatGPT / CTO:** read `PROJECT_STATUS.md`; for Grid work, also read `Docs/EAs/Grid/ROADMAP.md`, `Docs/EAs/Grid/README.md`, `Docs/EAs/Grid/architecture.md`, `Docs/EAs/Grid/Testing/testing.md`, and the current Work Package's relevant Phase/Design/ADR documents.
3. **Implementer (Codex or Freebuff):** read only the active Trello Card's linked `SPEC.md` and `TEST_PLAN.md`, plus the exact source/test files and any additional repository document explicitly referenced by that Specification. Do not load the entire Grid Roadmap/Architecture/Testing history by default; request clarification if the task handoff is incomplete. This keeps the task context bounded.
4. Inspect the current source files and tests within the Card's allowed scope; do not rely on docs/memories as proof that Source matches them.
5. Run `git status --short --untracked-files=all` before editing and preserve all pre-existing staged, unstaged, and untracked user work.
6. Serena/MCP memories are optional context for ChatGPT when available. Neither Codex nor Freebuff may depend on Serena memories or prior chat history; the repository and active Card handoff are the durable source of instructions. Freebuff must not use Serena MCP.

Do not assume a prior chat transcript or model memory is visible to either Codex or Freebuff. Durable instructions must live in this repository.

## Workflow and authorization
- Work in small, testable Work Packages/Phases and implementation Cards with explicit scope and Acceptance Criteria.
- Do not silently expand product scope or change approved contracts. If implementation reveals a material design/contract issue, stop and request a decision.
- **Roles:** ChatGPT acts as CTO/Technical Lead: owns architecture/design, contracts, task breakdown, implementation handoffs, final code review, and technical documentation. **Codex or Freebuff** acts as the Developer Agent selected by the user for each implementation task: implements code and tests strictly within the approved specification and follows the Developer compile gate. The user acts as Product Owner/QA: approves scope/design, chooses the Implementer, runs the MetaEditor/MT5 test suites, reports actual results, and authorizes the next task.
- **Implementer selection belongs exclusively to the user.** The user's current preference is to use Codex first while monthly Codex quota remains, then use Freebuff after that quota is exhausted. ChatGPT must not select, switch, or recommend an Implementer based on quota assumptions; prepare a tool-neutral handoff usable by either agent and wait for the user to invoke/assign the chosen one.
- ChatGPT must not implement or patch source code on behalf of the assigned Implementer unless the user explicitly changes this role agreement. The same implementation contract, scope, safety rules, reporting requirements, and acceptance criteria apply to Codex and Freebuff.
- The assigned Implementer must work from repository files directly. `AGENTS.md`, task `SPEC.md`, `TEST_PLAN.md`, and relevant repository documentation are the durable instructions and context; do not require prior chat history or Serena memories. **Do not require either Implementer to install, connect to, or use Serena MCP.** Freebuff must not use Serena MCP. Serena/MCP availability is optional and must never block implementation.
- Before implementation, ChatGPT prepares and the user approves the Design/Contract, then creates or updates the Trello implementation Card and prepares separate `SPEC.md` and `TEST_PLAN.md` files. Do not start implementation until the Card is in the active implementation state and the user explicitly authorizes the task.
- The user-selected Implementer (Codex or Freebuff) implements only the active Card's scope. It must report changed files, behavior, tests added/run, exact results, compile evidence, and anything not verified in `IMPLEMENTATION_REPORT.md` (or the agreed Card-linked report). It must not silently change Design/Contract or expand scope.
- After the assigned Implementer reports implementation complete together with its compile evidence (or explicitly reports why compilation was unavailable), the user runs the specified MetaEditor/MT5 test suites first. **ChatGPT's formal Code Review starts only after the user reports Test PASS.** If user verification fails, return the Card to implementation and have the assigned Implementer (Codex or Freebuff) fix it (including recompiling to `0 errors, 0 warnings`); do not start formal review yet.
- After user verification passes, ChatGPT reviews the actual source diff against `SPEC.md`, `TEST_PLAN.md`, Acceptance Criteria, architecture, and reported test evidence. Record findings in a Card-linked `CODE_REVIEW.md` (or the agreed durable review file). Each finding must include an ID, severity, file/location, problem, required fix, and acceptance condition.
- Review outcomes are `APPROVED`, `CHANGES_REQUESTED`, or `BLOCKED`. For `CHANGES_REQUESTED`, the assigned Implementer (Codex or Freebuff) fixes only the recorded findings; the user must compile/test the revised code again before ChatGPT reviews it again. Repeat until approved.
- Mark a Card Done only after user-reported Compile/Test PASS, ChatGPT Code Review APPROVED, required documentation updates, and user confirmation. A written implementation report or static review alone is insufficient.
- At every Phase boundary, stop and ask the user for explicit authorization before starting the next Phase. A broad roadmap/kickoff authorization does not waive this requirement.
- When a new Phase/task is authorized, check whether a Trello card already matches its scope; create or update a separate card when needed before implementation. Keep its list, description, links, and progress log aligned with the actual state.
- Blanket authorization does NOT authorize live trading, Demo tests that send Trade Requests, touching non-test positions, destructive account actions, changing product scope, or choosing between unresolved material design alternatives. Stop and ask the user for these.
- Do not commit or push unless explicitly asked. Never place live trades or enable live trading as part of development/testing unless the user explicitly authorizes it.
- Explain changed files, behavior, rationale, validation, and next step after each Work Package.

## Trello implementation lifecycle
- Use the board's existing lists where possible; if needed, create/agree on a dedicated **User Verification** stage so user Compile/Test happens before formal CTO Code Review.
- The intended lifecycle is: `Product Backlog -> Ready -> In Progress -> User Verification -> Code Review -> Done`.
- If user Compile/Test fails, return to `In Progress` for fixes by the assigned Implementer (Codex or Freebuff), then repeat User Verification. If CTO review requests changes, use `Changes Requested` (or the board's equivalent), then repeat User Verification before the next formal review.
- If the board has no exact matching list, do not silently create or rename lists; report the mismatch and agree with the user on the mapping first.
- Current TGK Grid Bot board mapping (2026-11-25): `MT5 Testing` is the User Verification stage; `Code Review` is formal CTO review; `In Progress` may contain multiple Cards during CTO-led Design/Planning (clearly mark `CTO Planning / Contract Design only; implementation not authorized`) and may also contain the single active implementation Card or its review fixes; `Blocked` is used when work cannot proceed. Planning Cards may be designed/created/moved to In Progress in parallel when the scope has multiple deliverables. This does NOT authorize implementation. Implementation and formal review remain sequential: only one Card is implemented/reviewed at a time, after finalized SPEC/TEST_PLAN, explicit Product Owner authorization, and the required pre-change baseline. Keep the Card description/comment explicit about whether In Progress means Planning or Implementation. Do not create/rename lists unless the user later approves it.
- Trello is the concise work/status tracker. Repository Markdown files are the durable technical contract and handoff. Link each implementation Card to its `SPEC.md`, `TEST_PLAN.md`, implementation report, and code review record as applicable.

## Developer handoff files
- Each implementation Card must link to a dedicated `SPEC.md` and a separate `TEST_PLAN.md`.
- `SPEC.md` defines objective, scope/out-of-scope, dependencies, allowed files, technical contract, implementation constraints, and Acceptance Criteria.
- `TEST_PLAN.md` defines preconditions, test IDs/scenarios, expected results, regression coverage, and safety restrictions.
- The assigned Implementer (Codex or Freebuff) records implementation details and evidence in `IMPLEMENTATION_REPORT.md` (or a clearly agreed Card-linked report).
- ChatGPT records review status and actionable findings in `CODE_REVIEW.md` (or a clearly agreed Card-linked review file). Keep these files concise and scoped to the individual implementation Card.
- Do not require Codex or Freebuff to recover requirements from chat history; the approved Card and linked repository files are the complete task handoff.

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
- The assigned Implementer (Codex or Freebuff) compiles changed code when the verified environment is accessible (see **Developer compile gate** below), but does not run the MT5 test suites. The user runs MetaEditor/MT5 runtime tests and reports actual results. Never claim tests were run if they were not.
- If a test fails, stop forward progression, diagnose/fix the failure, and repeat the relevant regression suite.

## Developer compile gate (Codex / Freebuff)

The assigned Implementer must use the verified local MetaEditor compile environment when it is accessible. Running the MT5 test suites stays with the user.

- After finishing any code change (source or test `.mq5` / `.mqh`), compile every affected MQL5 program before reporting the task as implemented.
- Fix every error **and** every warning, then recompile, until each affected program reports `0 errors, 0 warnings`. Do not report implementation complete on a failing or warning-carrying compile, and do not hand warnings to the user to triage.
- An `.mqh` include has no standalone build: compile every program that includes it (find them with `grep -rl "<Include>.mqh" --include=*.mq5 --include=*.mqh`).
- Do not run the test suites; the user runs MetaEditor/MT5 tests and reports actual results. Record compile evidence separately from test evidence, and never present compile success as test success.
- If the assigned Implementer cannot access the compile environment or compilation cannot be made to pass, report that plainly with the exact limitation/log evidence. Do not infer compile status from static checks or claim implementation fully verified. The user decides whether to provide compile access or take over the compile step.

### Verified compile environment (2026-11-24)

- Verified on the user's machine and previously used by Freebuff; Codex should use it when running in an environment with access to the same local machine/filesystem.
- `WINEPREFIX="$HOME/wine-python-mt5"` (the MT5 installation the user actively uses); `Z:` maps to `/` in this prefix.
- Compiler: `/usr/local/bin/wine` (wine-11.0) with `"C:\Program Files\MetaTrader 5\MetaEditor64.exe"`.
- `/inc:` must point at the repository root, not at `<repo>/Include`, because MetaEditor appends `Include` itself; otherwise includes fail with `error 106: file ... not found`.
- `metaeditor64.exe` returns exit code `1` even when the compile succeeds; judge the result from the log's `Result:` line.

```bash
export WINEPREFIX="$HOME/wine-python-mt5"
PFX="Z:\\Users\\tachagon\\Documents\\13_Trade\\1_Bot\\BotTradeFramework"
/usr/local/bin/wine "C:\\Program Files\\MetaTrader 5\\MetaEditor64.exe" \
  /compile:"$PFX\\Experts\\TGK\\Tests\\Grids\\test_grid_entry_execution.mq5" \
  /inc:"$PFX" /log:"$PFX\\compile.log"
iconv -f UTF-16LE -t UTF-8 compile.log
```

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

## Documentation Consistency Gate

- Before closing any WP/Phase or documentation-maintenance task, run the mandatory [Documentation Consistency Gate](Docs/Development/documentation-consistency-gate.md).
- This is a separate acceptance gate after implementation/test review and documentation updates; a successful `git diff --check` alone is not sufficient.
- Review current-status claims across `PROJECT_STATUS.md`, affected `Docs/`, `AGENTS.md`, and relevant Serena memories; compare implementation claims with source, test inventory with actual test files, and verification claims with user-reported evidence.
- Search for stale/contradictory positive and negative claims. Preserve valid historical records but date/contextualize them and point to the current status.
- Confirm architecture, current WP state, next step, and authorization/safety boundaries agree. Read the full diff, validate local Markdown links, run `git diff --check`, and report the gate evidence.
- If contradictions or required checks remain unresolved, do not mark the WP/Phase or documentation task complete.

## Grid V1 completion
- For Grid tasks, `Docs/EAs/Grid/ROADMAP.md` is the master roadmap and Definition of Done.
- Grid V1 is not complete merely because individual modules or test EAs pass. Production EA integration and end-to-end behavior must be validated against the roadmap.
- At completion, review every Definition of Done item, record evidence, and obtain the user's final acceptance.
- If ChatGPT's configured Serena/MCP project access fails during a task that requires it, tell the user to check the MCP Serena server. This does not apply to Freebuff: Freebuff works directly with repository files and does not require Serena MCP.
