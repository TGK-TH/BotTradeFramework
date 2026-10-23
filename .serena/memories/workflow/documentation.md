# TGK BotTradeFramework Documentation Workflow

User approved a multi-EA documentation hierarchy; all technical Docs must be written in Thai. Preserve actual source identifiers, class/function/enum names, and file paths in original spelling.

Structure:
- `Docs/Framework/`: only architecture/modules with a confirmed shared contract for multiple EAs.
- `Docs/EAs/<EA-Name>/`: EA-specific architecture, strategy logic, state machine, configuration, tests, decisions, and phase notes.
- `Docs/Development/`: repository-wide workflow and development standards.
- `Docs/Decisions/README.md`: central ADR index; every ADR must declare its scope.
- `PROJECT_STATUS.md`: concise current status and exact next step, not a duplicate technical manual.

Do not promote an EA-specific module to Framework merely because another EA might use it later. Current Grid Identity and Persistence docs remain under `Docs/EAs/Grid/` because the existing APIs/types are Grid-specific. TestAssert/TestRunner docs are under Framework.

When a phase completes:
1. Update `PROJECT_STATUS.md` with phase state, changed files, checks, user-reported compile/runtime outcomes, known issues, and exact next step.
2. Update relevant existing Thai Docs; create new docs only when needed.
3. Update module docs for behavior/architecture changes, testing docs for test/procedure changes, ADRs for important design decisions, and phase notes for completed work.
4. Clearly distinguish implemented, user-verified, agreed-not-implemented, and open behavior.
5. Verify docs match source, check local Markdown links, and run `git diff --check`.
6. Never claim MQL5 compile/runtime passed without user confirmation.

Documentation hierarchy was reorganized on 2026-10-23. Grid Integration Testing and Documentation Structure are complete based on user-reported test results and repository checks. Next planned development is Grid State Machine, but do not begin until explicitly authorized. Before any Grid feature/refactor, run relevant Grid regression tests first.