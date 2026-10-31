# Current TGK BotTradeFramework Phase

As of 2026-10-31, Grid Order Execution Adapter — Round 1 is IN PROGRESS. User reported all nine Grid Regression Tests passed immediately before this phase began.

## Completed phase: Grid Runtime Orchestration — Round 1
- Added `Include/BotTrade/Grid/GridRuntimeOrchestrator.mqh`.
  - Caller initializes `CTGKGridIdentity` first and passes Instance ID, Symbol, and Magic Number.
  - Initializes/restores Lifecycle using a fresh position count filtered by exact Symbol + Magic Number.
  - Coordinates Lifecycle and Position Reconciler reset transitions.
  - Reports ERROR, WAIT_INITIAL_ENTRY, ACTIVE, CLOSE_REQUIRED, and WAIT_CLOSE_CONFIRMATION.
  - Never sends trade requests; no CTrade dependency.
  - Recounts positions on every update; accepted close requests are not proof of closure.
  - When zero owned positions are confirmed, advances RESET_CLOSE_OLD -> RESET_REBUILD -> applies pending configuration.
- Added `Experts/TGK/Tests/Grids/test_grid_runtime_orchestrator.mq5` with Snapshot-based, no-trading tests.
- Updated phase documentation, Grid testing guide, architecture documentation, and `PROJECT_STATUS.md`.
- User reported on 2026-10-30 that all 9 Grid tests compiled and passed in MetaEditor/MT5:
  1. `test_grid_runtime_orchestrator.mq5`
  2. `test_grid_position_reconciler.mq5`
  3. `test_grid_lifecycle.mq5`
  4. `test_grid_state_machine.mq5`
  5. `test_grid_types.mq5`
  6. `test_grid_persistence.mq5`
  7. `test_grid_identity.mq5`
  8. `test_grid_identity_multichart.mq5`
  9. `test_grid_restart_persistence.mq5`
- These are user-reported MetaEditor/MT5 results; assistant did not independently run MetaEditor/MT5.
- No EA OnInit/OnTick/OnTimer adapter, pending-order management, Grid levels, Bounds, TP, re-entry, or actual open/close execution is included.

## Current phase: Grid Order Execution Adapter — Round 1 (2026-10-31)
- User explicitly approved the Batch Close policy: when Runtime reports CLOSE_REQUIRED, attempt to close every owned Position found in one pass, then let Runtime reconcile fresh account state and retry only what remains.
- User reported all nine Grid Regression Tests passed immediately before source changes on 2026-10-31.
- Added `Include/BotTrade/Grid/GridOrderExecutionPolicy.mqh`: pure ownership filtering, batch construction, retcode classification, and aggregate outcome policy; no trade requests.
- Added `Include/BotTrade/Grid/GridOrderExecutionAdapter.mqh`: live account scan and ticket-specific CTrade PositionClose calls, gated by CLOSE_REQUIRED; reports one aggregate close attempt to Runtime.
- Added `Experts/TGK/Tests/Grids/test_grid_order_execution.mq5`: compiles Policy + Adapter and tests policy outcomes, adapter initialization, runtime identity guard, and non-CLOSE_REQUIRED gate; no live trade requests.
- Added `Docs/EAs/Grid/Phases/phase-grid-order-execution.md`; updated Grid architecture, testing guide, and PROJECT_STATUS.md.
- New Unit Test and post-change 9-file Regression Tests still require user Compile/Runtime validation in MetaEditor/MT5.
- Do not run a Demo integration test that sends real close requests without separate explicit user approval.

## Next work boundary
Do not begin Initial/Grid-level opening, pending-order management, or EA Event Handler integration until separately scoped and explicitly approved.

## Workflow and safety
- Work phase by phase; do not begin later phases without explicit user authorization.
- User performs MetaEditor compilation/runtime tests and reports results.
- Update this memory and project docs after every completed phase, recording actual user-reported outcomes.
- Before new Grid feature/refactor, run relevant Grid Regression Tests first; agree on and add coverage if needed.
- Use 2-space indentation. Format multi-parameter test calls one parameter per line.
- If Serena/MCP fails, remind the user to check the MCP Serena server.
