# Current TGK BotTradeFramework Phase

As of 2026-10-28, Grid Lifecycle Integration round 1 is complete based on user-reported MetaEditor/MT5 results.

## User-reported validation after Lifecycle Integration changes
The user confirmed all seven tests compiled and ran successfully:
- `Experts/TGK/Tests/Grids/test_grid_lifecycle.mq5` — PASS
- `Experts/TGK/Tests/Grids/test_grid_state_machine.mq5` — PASS
- `Experts/TGK/Tests/Grids/test_grid_types.mq5` — PASS
- `Experts/TGK/Tests/Grids/test_grid_persistence.mq5` — PASS
- `Experts/TGK/Tests/Grids/test_grid_identity.mq5` — PASS
- `Experts/TGK/Tests/Grids/test_grid_identity_multichart.mq5` — PASS
- `Experts/TGK/Tests/Grids/test_grid_restart_persistence.mq5` — PASS

These are user-reported results, not tests independently executed by the assistant. `PROJECT_STATUS.md`, `Docs/EAs/Grid/Testing/testing.md`, and `Docs/EAs/Grid/Phases/phase-grid-lifecycle-integration.md` were updated to record the outcome.

## Completed Lifecycle Integration round 1
- `Include/BotTrade/Grid/GridLifecycle.mqh` coordinates State Machine and Persistence for an already-identified instance, without order execution.
- `Include/BotTrade/Grid/GridPersistence.mqh` provides `HasSnapshot()` to distinguish missing snapshots from present-but-invalid snapshots.
- `Experts/TGK/Tests/Grids/test_grid_lifecycle.mq5` covers fresh start, actual fill/Anchor restore, pending Mode reset across restart, missing snapshot with positions, Magic mismatch, and invalid persisted mode.
- Assistant previously ran `git diff --check` and local Markdown-link validation successfully; these do not replace the user's MQL5 validation.

## Safety and lifecycle decisions
A manually opened new chart creates a new Grid Instance with a new Instance ID/Magic Number and must not manage old Grid positions. Existing Grid resumes only when its saved chart/profile and identity/persistence are restored. No auto-adoption from a new chart.

The Lifecycle Coordinator does not initialize Identity itself; the EA must initialize Identity and pass its Instance ID/Magic. The caller must provide a fresh position count filtered by Symbol + Magic Number. Missing/invalid snapshot, identity mismatch, fixed-lot mismatch, or incompatible pending-reset configuration leads to `RECOVERY_ERROR`. No order opening/closing, Bounds, Grid Level generation, TP or re-entry is implemented.

## Next step
Lifecycle Integration round 1 is complete. Do not start a new phase without explicit user authorization and agreement on scope. A reasonable proposed next phase is to design and test-first implement the Grid runtime/position reconciliation boundary before real order execution, including ownership filtering and safe behavior when close requests fail or the market is closed. Keep actual trading actions separately scoped and do not assume authorization to implement them yet.

Workflow: phase-by-phase; run relevant regression tests before any new Grid feature/refactor. User compiles/runs MQL5 tests in MetaEditor/MT5 and reports results. Use 2-space indentation and format multi-parameter calls one argument per line.