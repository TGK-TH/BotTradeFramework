# TGK BotTradeFramework Development + Trello Workflow

## Authority and scope
- This is the repository-wide workflow for BotTradeFramework and applies to Grid and future EAs/features unless a task explicitly defines a justified exception.
- Repository is the Technical Source of Truth: source code, tests, architecture, and technical documentation live there.
- Trello board **TGK Grid Bot** is the Project Status Tracker: it tracks work items, ownership/progress, blockers, and acceptance status. Do not duplicate full technical documentation in Trello.
- Keep Trello Cards linked to the relevant source, tests, and documentation paths.

## Development flow
1. **Requirement + Design**: clarify problem, scope, behavior, constraints, edge cases, architecture, and Acceptance Criteria with the user.
2. **Test Plan first**: define suitable Unit, Integration, Failure/Edge Case, and Regression coverage before implementation. Grid work is test-first; keep Grid tests under `Experts/TGK/Tests/Grids`.
3. **Implement by approved phases**: implement only the agreed slice. Explain changes and wait for user approval before starting the next phase. Do not silently expand scope.
4. **Code Review**: inspect logic, architecture, edge cases, compatibility, static issues, and `git diff --check`.
5. **Compile + MT5 Testing**: user runs MetaEditor/MT5 compile and runtime tests and reports results. Assistant must not claim to have run MT5 or claim compile/runtime success without user confirmation.
6. **Regression**: run the relevant full regression suite after changes. Before any new Grid feature/refactor, explicitly remind the user to run the latest Grid Regression Tests.
7. **Documentation + status**: update relevant Thai technical docs, `PROJECT_STATUS.md`, and `.serena/memories/workflow/current-phase.md`. Preserve exact source identifiers and paths. Distinguish implemented, user-verified, agreed-but-not-implemented, and open behavior. Verify Markdown links and run `git diff --check`.
8. **Completion**: mark the phase complete only after Acceptance Criteria and user-reported tests pass. User confirmation is required before declaring a phase Done.

## Trello board workflow
Board: **TGK Grid Bot** — https://trello.com/b/cYLUMIui/tgk-grid-bot

Lists and transition rules:
1. **Product Backlog** — ideas, future features, bugs, refactors, research not yet fully scoped.
2. **Ready** — scope, design, Acceptance Criteria, and appropriate Test Plan are defined; ready to start.
3. **In Progress** — active design/implementation for the current work item. Keep WIP limited and record the current phase.
4. **Code Review** — implementation is complete for the agreed slice; review logic, architecture, edge cases, and static checks.
5. **MT5 Testing** — review and compile are complete; user is running Unit/Integration/Regression tests in MetaEditor/MT5.
6. **Blocked** — work cannot proceed pending a decision, information, dependency, or failure resolution. Record the blocker and what is needed to unblock.
7. **Done** — Acceptance Criteria passed and user confirmed the test outcome. Code merely being written is not sufficient.

Typical path:
`Product Backlog -> Ready -> In Progress -> Code Review -> MT5 Testing -> Done`.
Move to **Blocked** whenever progress is genuinely blocked; return to the appropriate active stage after resolution. A failed test normally returns to In Progress for a fix, then repeats review/testing.

## Trello Card conventions
- Create a Card when a meaningful work item enters the backlog; do not create a Card for every tiny code edit.
- A Card should state: goal/context, scope, Acceptance Criteria, Test Plan, and links/paths to source, tests, and technical docs.
- Keep a concise Progress Log for meaningful stage changes and user-reported test outcomes.
- Use the board's labels consistently:
  - Architecture
  - Feature
  - Bug
  - Refactor
  - Unit Test
  - Integration
  - Documentation
  - Research
- Apply only labels relevant to that Card; do not attach all labels by default.
- Update Card/list status when the work crosses a meaningful workflow boundary, not for every intermediate edit.
- Do not move a Card to Done based solely on assistant implementation or static checks.

## Roles
- Assistant: analyze/design with the user; prepare Test Plans; implement approved code slices; review; update technical docs/status and Trello Cards; analyze user-reported MT5/test results.
- User: make scope/design decisions and approvals; run MetaEditor/MT5 compile/runtime tests; report actual outcomes; confirm Acceptance Criteria and phase completion.
- Assistant must not start the next phase without explicit user approval.

## Practical operating rules
- Before starting Grid feature/refactor work, remind the user to run the latest Grid Regression Tests.
- At the beginning of a new development task, check the current-phase memory and relevant Trello Card/Board state when available; do not infer that a task is active or Done from old chat context alone.
- At each meaningful transition, keep Trello status aligned with repository status. If Trello is unavailable, continue technical work where safe and report that Board synchronization could not be completed.
- Repository documentation remains the detailed technical record; Trello is the concise workflow/status view.
