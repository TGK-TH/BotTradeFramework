# Current TGK BotTradeFramework Phase

Current phase: Grid Integration Testing. Do not begin Grid State Machine development until the user explicitly authorizes it and the restart persistence test is rerun after the latest adjustment.

User-reported results on 2026-10-23:
- `Experts/TGK/Tests/Grids/test_grid_identity_multichart.mq5` compiled and passed.
- `Experts/TGK/Tests/Grids/test_grid_restart_persistence.mq5` ran its second stage; persistence and identity checks passed except `chart id changed after reopening`, which failed because the saved and current ChartID were equal.

Diagnosis and edit:
- MT5 may reuse a ChartID while restoring a saved Profile. ChartID is not a durable Grid identity and should not be required to change for persistence to pass.
- Updated `Experts/TGK/Tests/Grids/test_grid_restart_persistence.mq5`: saved/current ChartID are now printed as diagnostic information, not asserted. Actual checks remain Instance ID hash, Magic Number, snapshot fields, and level states.
- Updated `PROJECT_STATUS.md` with the user-reported result and pending rerun.
- User must compile and rerun the adjusted test in MetaEditor/MT5 and report the outcome. Do not claim it passes until confirmed.

Workflow: user compiles/runs MQL5 tests. Use 2-space indentation. Update PROJECT_STATUS.md after each completed phase. Before new Grid feature/refactor, run relevant Grid Regression Tests. If Serena/MCP fails, remind user to check the Serena MCP server.