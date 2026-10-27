# Current TGK BotTradeFramework Phase

As of 2026-10-27, Grid Integration Testing and Documentation Structure are complete. Grid State Machine implementation round 1 is complete based on user-reported MetaEditor/MT5 validation.

## User-reported validation after State Machine changes
The user confirmed that `Experts/TGK/Tests/Grids/test_grid_state_machine.mq5` compiled and ran successfully, and all five existing Grid Regression Tests were rerun after the changes and passed:
- `Experts/TGK/Tests/Grids/test_grid_types.mq5`
- `Experts/TGK/Tests/Grids/test_grid_persistence.mq5`
- `Experts/TGK/Tests/Grids/test_grid_identity.mq5`
- `Experts/TGK/Tests/Grids/test_grid_identity_multichart.mq5`
- `Experts/TGK/Tests/Grids/test_grid_restart_persistence.mq5`

These are user-reported MetaEditor/MT5 results, not tests independently executed by the assistant. The testing records were updated in `PROJECT_STATUS.md` and `Docs/EAs/Grid/Testing/testing.md`.

## Lifecycle decision
A manually opened new chart with the same symbol is a new Grid Instance with a new Instance ID and Magic Number. It must not manage the previous Grid's positions. An existing Grid resumes when its saved chart/profile and identity/persistence are restored; do not auto-adopt old positions from a fresh chart.

## State Machine round 1 scope
Files:
- `Include/BotTrade/Grid/GridStateMachine.mqh`
- `Experts/TGK/Tests/Grids/test_grid_state_machine.mq5`
- `Docs/EAs/Grid/Phases/phase-grid-state-machine.md`

Implemented lifecycle transitions only: validate instance data, record actual initial fill as Anchor, request configuration resets, wait for account-confirmed zero remaining positions before rebuilding, clear Anchor on mode change, retain Anchor on step change, and block state changes in Recovery Error. Caller must provide a fresh count of positions filtered by this Grid's symbol and Magic Number. No order execution, bounds, level generation, TP/re-entry, position reconciliation, or live EA integration is implemented yet.

## Next step
State Machine round 1 is complete; do not start the next phase until the user explicitly authorizes it and the scope is agreed. A sensible proposed next phase is design/test-first integration of the State Machine with Grid lifecycle coordination, while keeping actual order execution as a separate explicitly scoped phase. Before any new Grid feature/refactor, run relevant Grid Regression Tests first. User compiles/runs MQL5 tests in MetaEditor/MT5 and reports results. Use 2-space indentation and format multi-parameter calls one argument per line. Never claim compile/runtime success without user confirmation.