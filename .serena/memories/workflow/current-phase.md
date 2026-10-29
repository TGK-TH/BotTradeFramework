# Current TGK BotTradeFramework Phase

As of 2026-10-29, Grid Runtime & Position Reconciliation round 1 has been implemented test-first and is awaiting user Compile/Runtime validation in MetaEditor/MT5.

## Current phase changes
- Added `Include/BotTrade/Grid/GridPositionReconciler.mqh`.
  - Ownership requires exact Symbol + Magic Number.
  - `CountLiveOwnedPositions()` reads live positions without changing them.
  - If a live scan cannot safely read a position, it returns -1 rather than undercounting and falsely reporting zero.
  - Snapshot fixture counting supports tests without opening real positions.
  - Close attempt outcomes: none, accepted, market closed, failed.
  - An accepted request is not proof of closure; fresh account state is authoritative.
  - If positions remain on the next observation, return retry required rather than waiting forever.
  - Negative/invalid observed counts enter Recovery Error.
  - It does not send trade requests or integrate directly with Lifecycle.
- Added `Experts/TGK/Tests/Grids/test_grid_position_reconciler.mq5`, no trading calls.
- Added `Docs/EAs/Grid/Phases/phase-grid-runtime-position-reconciliation.md`; updated `PROJECT_STATUS.md`, `Docs/EAs/Grid/Testing/testing.md`, and `Docs/EAs/Grid/architecture.md`.

## Validation state
The user reported all seven existing Grid tests PASS on 2026-10-28 before this phase. Assistant has not run MetaEditor/MT5. User must compile/run the new test and all seven existing tests after current source changes before phase can be marked complete. Static checks do not replace MQL5 compile/runtime testing.

## Next user action
Compile/run:
- `Experts/TGK/Tests/Grids/test_grid_position_reconciler.mq5`
- `Experts/TGK/Tests/Grids/test_grid_lifecycle.mq5`
- `Experts/TGK/Tests/Grids/test_grid_state_machine.mq5`
- `Experts/TGK/Tests/Grids/test_grid_types.mq5`
- `Experts/TGK/Tests/Grids/test_grid_persistence.mq5`
- `Experts/TGK/Tests/Grids/test_grid_identity.mq5`
- `Experts/TGK/Tests/Grids/test_grid_identity_multichart.mq5`
- `Experts/TGK/Tests/Grids/test_grid_restart_persistence.mq5`

Actual order open/close execution, grid levels, bounds, TP and re-entry remain out of scope and require separate explicit authorization.

## Completed earlier
Grid State Machine round 1 and Grid Lifecycle Integration round 1 remain complete based on user-reported tests. Lifecycle integration and persistence changes had all seven tests pass on 2026-10-28.
