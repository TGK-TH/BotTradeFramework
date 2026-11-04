# Current TGK BotTradeFramework Phase

As of 2026-11-04, Grid Level Engine — Round 1 is completed based on user-reported MetaEditor/MT5 validation.

## Most recently completed: Grid Level Engine — Round 1

- User reported on 2026-11-04 that they recompiled and ran all 11 Grid Regression Tests; all passed.
- This includes the new `test_grid_level_engine.mq5` and updated persistence/type tests, plus the existing regression suite.
- This is user-reported validation. The assistant did not independently run MetaEditor/MT5.
- Scope verified: Pure Two-sided Grid Level Engine behavior, Anchor/ordinary level state handling, candidate selection, crossing/activation rules, WAIT_ACTIVATION enum and persistence coverage.
- Not verified by this phase: Production EA OnInit/OnTick/OnTimer integration, full live multi-level order execution, or complete Grid V1 operation.
- Implementation notes: `Docs/EAs/Grid/Phases/phase-grid-level-engine-implementation-round-1.md`.
- Project status: `PROJECT_STATUS.md`.

## Round 1 design and behavior

- Two-sided levels derive from actual Fill Price (Anchor), Grid Step and hard Bounds; Anchor is separate and excluded from ordinary level_count.
- Levels sorted ascending; Bounds do not shift prices.
- BUY uses Ask, activates upward and enters downward; selects lowest crossed eligible READY/WAIT_RETURN level.
- SELL uses Bid, activates downward and enters upward; selects highest crossed eligible READY/WAIT_RETURN level.
- At most one candidate per price update. Unselected crossed eligible levels left on the wrong side become WAIT_ACTIVATION; ACTIVE remains unchanged.
- Anchor is a separate special/re-entry level and follows the same state machine.
- Exact crossing uses strict previous-side and inclusive current-side; stationary quotes do not retrigger.
- Close outcome first checks current market side; if the level is already past market -> WAIT_ACTIVATION; otherwise TP -> WAIT_RETURN and non-TP -> READY.
- Accepted/Placed unresolved order requests must not be duplicated; Runtime/Execution must reconcile and retain a better candidate observed while unresolved.
- Partial close retains ACTIVE until reconciliation confirms no position remains.
- Restart persistence integration and ticket-to-level mapping remain integration responsibilities.

## Files changed in Round 1

- `Include/BotTrade/Grid/GridLevelEngine.mqh`
- `Include/BotTrade/Grid/GridTypes.mqh`
- `Include/BotTrade/Grid/GridPersistence.mqh`
- `Experts/TGK/Tests/Grids/test_grid_level_engine.mq5`
- `Experts/TGK/Tests/Grids/test_grid_persistence.mq5`
- `Experts/TGK/Tests/Grids/test_grid_types.mq5`
- Docs and `PROJECT_STATUS.md`.

## Workflow / next step

- Do not begin a later phase until the user explicitly approves its scope.
- Before any new Grid feature/refactor, run the relevant Grid Regression Tests first.
- User performs MetaEditor/MT5 tests and reports results.
- Work phase-by-phase; update Thai Docs and this memory after completed phases.
- Use 2-space indentation and one parameter per line for multi-parameter test calls.
- If Serena/MCP fails, remind the user to check the MCP Serena server.
