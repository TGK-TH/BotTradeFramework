# Current TGK BotTradeFramework Phase

As of 2026-11-04, Grid Level Engine Round 1 source and tests have been prepared. MetaEditor/MT5 validation is pending the user.

## Current phase: Grid Level Engine — Round 1

Design references:
- `Docs/EAs/Grid/Phases/phase-grid-level-engine-design.md`
- `Docs/EAs/Grid/Phases/phase-grid-level-engine-implementation-round-1.md`

## Round 1 changes
- Rewrote `Include/BotTrade/Grid/GridLevelEngine.mqh` for Two-sided Grid levels sorted ascending by price, with Anchor as a separate Special/Re-entry Level. Caller passes total ordinary `level_count` (both sides, Anchor excluded); Engine independently validates it against Anchor/Step/Bounds.
- Grid Level count is calculated from Anchor, Step and hard Bounds; Anchor is excluded. Bounds do not shift levels.
- Initial states use current entry quote: BUY Ask (above/equal WAIT_ACTIVATION, below READY); SELL Bid (below/equal WAIT_ACTIVATION, above READY). Anchor starts ACTIVE for the initial filled position.
- Appended `TGK_GRID_LEVEL_WAIT_ACTIVATION` to `GridTypes.mqh`, preserving numeric values of READY, ACTIVE, WAIT_RETURN.
- Updated `GridPersistence.mqh` enum range validation to accept WAIT_ACTIVATION.
- Engine methods: `UpdatePrice()` (activation + max one best-price candidate), `RecordEntryConfirmed()`, `RecordEntryFailed()`, `RecordPositionClosed()`, plus Anchor/ordinary Level state getters/setters.
- BUY uses Ask; activation upward, entry downward, selects lowest crossed eligible price. SELL uses Bid; activation downward, entry upward, selects highest crossed eligible price.
- READY and WAIT_RETURN are eligible; ACTIVE is not. Unselected crossed eligible levels left on the wrong side of current price become WAIT_ACTIVATION.
- TP/non-TP close outcome is evaluated against current price: if Level is already past the market, WAIT_ACTIVATION; otherwise TP -> WAIT_RETURN, non-TP -> READY.
- Exact crossing uses strict previous-side and inclusive current-side (half-open): BUY activation prev<level<=current, BUY entry prev>level>=current; SELL inverse. Stationary quote cannot retrigger.
- Accepted/Placed unresolved requests must not be duplicated. Execution/Reconciliation must resolve outstanding request before retry; better candidates observed while pending must be retained by Runtime/Execution. Pure Engine does not send orders.
- One logical open Position per Level. Partial close retains ACTIVE until reconciliation finds no Position. Ticket-to-Level mapping is an integration responsibility.
- Restart persistence integration is outside this Pure Engine round.

## Files changed
- `Include/BotTrade/Grid/GridLevelEngine.mqh`
- `Include/BotTrade/Grid/GridTypes.mqh`
- `Include/BotTrade/Grid/GridPersistence.mqh`
- `Experts/TGK/Tests/Grids/test_grid_level_engine.mq5`
- `Experts/TGK/Tests/Grids/test_grid_persistence.mq5`
- `Experts/TGK/Tests/Grids/test_grid_types.mq5` (WAIT_ACTIVATION enum numeric contract)
- Docs: Design Spec, Implementation Round 1 notes, README, architecture, testing guide, PROJECT_STATUS.

## Validation status
- User-reported baseline: all 10 Grid Regression Tests passed on 2026-11-03 before Round 1 changes.
- Round 1 MetaEditor compile/runtime has NOT been performed or reported by the user.
- Next: user compiles/runs `test_grid_level_engine.mq5` and `test_grid_persistence.mq5`, then reruns all 11 Grid regression tests (10 existing plus Grid Level Engine).

## Workflow
- Work phase by phase; do not start later phases without explicit approval.
- User performs MetaEditor/MT5 tests and reports results.
- Before any Grid source feature/refactor, run relevant Grid Regression Tests first.
- Update Thai Docs and this memory after completed phases.
- Use 2-space indentation and one parameter per line for multi-parameter test calls.
- If Serena/MCP fails, remind the user to check the MCP Serena server.
