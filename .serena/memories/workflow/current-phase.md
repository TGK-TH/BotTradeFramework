# Current TGK BotTradeFramework Phase

As of 2026-11-08, Grid Level Runtime Coordinator — Round 1 source and test EA have been added. MetaEditor/MT5 validation is pending.

## Current phase: Grid Level Runtime Coordinator — Round 1

Design document: `Docs/EAs/Grid/Phases/phase-grid-level-runtime-coordinator-round-1.md`.

User-approved contracts:
- One unresolved Entry Request maximum per Grid Instance.
- Retain the best Deferred Candidate while the current request is unresolved: BUY lowest price; SELL highest price.
- Accepted/Placed is not proof of an opened Position. Do not set Level ACTIVE until reconciliation confirms a Position mapped to the same Candidate.
- A missing Position alone does not prove request failure; Execution/Reconciliation must confirm terminal no-position/no-order.
- Position-to-Level Mapping is supplied explicitly by Integration Layer using Anchor flag or Level Index; never infer from approximate Fill Price.
- Partial Close retains ACTIVE while volume remains. Full Close requires resolved TP/Non-TP reason before updating Level state.
- Coordinator is pure coordination logic: no CTrade and no live Account scan.

## Implementation added
- `Include/BotTrade/Grid/GridLevelRuntimeCoordinator.mqh`
- `Experts/TGK/Tests/Grids/test_grid_level_runtime_coordinator.mq5`
- Coordinator owns quote tracking, Candidate handoff, one unresolved request, Deferred Candidate retention, explicit Position snapshot validation, request confirmation/failure, and full-close events.
- Public Coordinator `UpdatePrice()` takes exactly 4 parameters: current Bid, current Ask, result reference, candidate reference. Previous Bid/Ask are held internally and passed to the Engine. The Engine's own lower-level `UpdatePrice()` has a different 7-parameter signature.
- The Test EA was corrected on 2026-11-08: removed the extra Previous Bid/Ask arguments from all Coordinator `UpdatePrice()` calls; each test now supplies only the current quote pair plus result/candidate references. Current quote transitions are generated from Initialize's quote and successive calls.
- Initial Anchor Position must be explicitly registered with `RegisterInitialAnchorPosition()` using `is_anchor=true` and `level_index=-1`.
- Position snapshots require exact Symbol/Magic, non-zero unique tickets, unique logical mappings, valid Anchor/index mapping, and positive volume.
- A disappeared tracked position requires an explicit matching TP/Non-TP Close Event; unknown/missing reasons are errors.
- Restart persistence of unresolved request/deferred candidate remains out of scope.
- `git diff --check` passed after the API call correction. No MetaEditor/MT5 compile or runtime result has been reported for the new test yet.

## Baseline and current gate
User reported all 11 existing Grid Regression Tests passed on 2026-11-07 before implementation:
1. `test_grid_level_engine.mq5`
2. `test_grid_order_execution.mq5`
3. `test_grid_runtime_orchestrator.mq5`
4. `test_grid_position_reconciler.mq5`
5. `test_grid_lifecycle.mq5`
6. `test_grid_state_machine.mq5`
7. `test_grid_types.mq5`
8. `test_grid_persistence.mq5`
9. `test_grid_identity.mq5`
10. `test_grid_identity_multichart.mq5`
11. `test_grid_restart_persistence.mq5`

Next, user must compile/run the corrected `test_grid_level_runtime_coordinator.mq5` plus all 11 existing Grid Regression Tests in MetaEditor/MT5. If any compile/runtime test fails, stop and diagnose before proceeding. Assistant did not run MetaEditor/MT5.

## Previous completed phase
Grid Level Engine — Round 1; user reported all 11 Grid Regression Tests passed on 2026-11-04. See `Docs/EAs/Grid/Phases/phase-grid-level-engine-implementation-round-1.md`.

## Workflow
- Do not begin later phases without explicit user approval.
- Before new Grid feature/refactor, run relevant Grid Regression baseline first.
- User compiles/runs MQL5 in MetaEditor/MT5; do not claim assistant ran it.
- Use 2-space indentation and one parameter per line in multi-parameter test calls.
- If Serena/MCP fails, remind the user to check the MCP Serena server.
