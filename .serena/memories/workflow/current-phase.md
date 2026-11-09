# Current TGK BotTradeFramework Phase

As of 2026-11-09, Grid Level Runtime Coordinator — Round 1 is completed and user-verified. The user reported that the new Coordinator Test EA plus all 11 existing Grid Regression Tests compiled and ran successfully in MetaEditor/MT5: 12/12 PASS. The assistant did not independently run MetaEditor/MT5.

## Most recently completed phase: Grid Level Runtime Coordinator — Round 1

Design and implementation record: `Docs/EAs/Grid/Phases/phase-grid-level-runtime-coordinator-round-1.md`.

Implemented:
- `Include/BotTrade/Grid/GridLevelRuntimeCoordinator.mqh`
- `Experts/TGK/Tests/Grids/test_grid_level_runtime_coordinator.mq5`
- Pure coordination logic joining `GridLevelEngine` with Candidate handoff, one unresolved Entry Request, best Deferred Candidate retention, explicit Position-to-Level mapping, request confirmation/failure, and full-close events.
- Public Coordinator `UpdatePrice()` takes 4 parameters: current Bid, current Ask, result reference, candidate reference. Previous Bid/Ask are tracked internally and passed to the Engine.
- Initial Anchor Position is explicitly registered through `RegisterInitialAnchorPosition()` with `is_anchor=true` and `level_index=-1`.
- Position snapshots validate exact Symbol/Magic, unique non-zero tickets, unique logical mappings, valid Anchor/index mapping, and positive volume.
- Partial close retains ACTIVE; disappearance requires an explicit TP/Non-TP Close Event.
- No CTrade or live Account scan in the Coordinator. Restart persistence of unresolved request/deferred candidate remains out of scope.

## Validation result
User reported on 2026-11-09 that all 12 tests compiled and ran successfully in MetaEditor/MT5:
1. `test_grid_level_runtime_coordinator.mq5`
2. `test_grid_level_engine.mq5`
3. `test_grid_order_execution.mq5`
4. `test_grid_runtime_orchestrator.mq5`
5. `test_grid_position_reconciler.mq5`
6. `test_grid_lifecycle.mq5`
7. `test_grid_state_machine.mq5`
8. `test_grid_types.mq5`
9. `test_grid_persistence.mq5`
10. `test_grid_identity.mq5`
11. `test_grid_identity_multichart.mq5`
12. `test_grid_restart_persistence.mq5`

Status: **Completed — User Verified, 12/12 PASS**. This validates the pure Coordinator and its regression contracts. It does not validate production EA event-handler integration, live multi-level entry execution, restart persistence of unresolved entry requests/deferred candidates, or complete Grid V1 behavior.

## Next step
Do not start the next phase until the user explicitly approves and its scope/design is agreed. Before any new Grid feature/refactor, run the relevant Grid Regression Tests first.

## Workflow
- Work phase by phase; do not start later phases without explicit user authorization.
- User compiles/runs MQL5 in MetaEditor/MT5; never claim the assistant ran it.
- Use 2-space indentation and one parameter per line in multi-parameter test calls.
- If Serena/MCP fails, remind the user to check the MCP Serena server.
