# Current TGK BotTradeFramework Phase

As of 2026-10-26, Grid Integration Testing and Documentation Structure are complete. User confirmed the Grid Regression Baseline passed before Grid State Machine changes:
- `Experts/TGK/Tests/Grids/test_grid_types.mq5`
- `Experts/TGK/Tests/Grids/test_grid_persistence.mq5`
- `Experts/TGK/Tests/Grids/test_grid_identity.mq5`
- `Experts/TGK/Tests/Grids/test_grid_identity_multichart.mq5`
- `Experts/TGK/Tests/Grids/test_grid_restart_persistence.mq5`

Lifecycle decision: a manually opened new chart with the same symbol is a new Grid Instance with a new Instance ID and Magic Number. It must not manage the previous Grid's positions. An existing Grid resumes when its saved chart/profile and identity/persistence are restored; do not auto-adopt old positions from a fresh chart.

Grid State Machine implementation round 1 is written, pending user compile/runtime validation:
- `Include/BotTrade/Grid/GridStateMachine.mqh`
- `Experts/TGK/Tests/Grids/test_grid_state_machine.mq5`
- `Docs/EAs/Grid/Phases/phase-grid-state-machine.md`

State machine scope: lifecycle transitions only, no order execution. It validates instance data, records actual fill price as Anchor, handles configuration reset requests, waits for account-confirmed zero remaining positions before rebuilding, clears Anchor on mode change, retains Anchor on step change, and blocks state changes in Recovery Error. The caller must provide a fresh count of positions filtered by this Grid's symbol and Magic Number. Grid level generation, bounds, TP/re-entry, position reconciliation, and EA integration are not yet implemented.

Next: user compiles/runs the new state machine test in MetaEditor/MT5. If it passes, user reruns the five baseline tests. Do not start order execution integration until these results are reported. User expects 2-space indentation and multi-parameter calls with one argument per line. Never claim compile/runtime success without user confirmation.