# Parallel Planning, Sequential Execution

Effective 2026-11-25 for TGK BotTradeFramework.

- CTO-led Design/Planning is allowed to proceed across multiple related Cards in parallel. ChatGPT may create multiple Trello Cards, prepare multiple SPEC/TEST_PLAN/IMPLEMENTATION_TASK documents, and move multiple planning Cards to `In Progress` together when the design has several deliverables.
- Every planning Card moved to `In Progress` must explicitly say `CTO Planning / Contract Design only; implementation not authorized`. Trello `In Progress` is shared by planning and implementation, so the card description/comment must identify which activity is active.
- Parallel planning does not imply parallel implementation authorization. Product behavior, trading behavior, and new WP scope still require explicit Product Owner approval.
- Implementation by Freebuff remains strictly sequential, one Card at a time. User MetaEditor/MT5 verification and CTO formal Code Review also remain sequential, one Card at a time.
- A Card can enter implementation only after its SPEC and TEST_PLAN are finalized, the Product Owner explicitly authorizes implementation, and the required pre-change no-trade Grid Regression baseline is reported.
- Preserve dependency order for execution even when downstream Cards are planned concurrently.
- Do not commit/push unless explicitly requested; preserve all user changes.
