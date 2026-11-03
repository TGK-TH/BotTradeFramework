# Current TGK BotTradeFramework Phase

As of 2026-11-04, Grid Level Engine Design Review is complete and approved by the user; implementation has NOT started.

## Current phase: Grid Level Engine — Design Agreed, Implementation Pending
- Full specification and agreed test plan: `Docs/EAs/Grid/Phases/phase-grid-level-engine-design.md`.
- User confirmed all five final design decisions on 2026-11-04:
  1. Bounds are hard filters; Anchor=4000, Step=5, Bounds=3992..4012 yields Grid Levels 3995, 4005, 4010 only.
  2. Unselected READY or WAIT_RETURN Levels that are crossed and now lie on the wrong side of Current Price become WAIT_ACTIVATION; ACTIVE remains unchanged.
  3. If a pending open Candidate has not succeeded and price reaches a better Candidate, the better Candidate may replace it; do not wait indefinitely for the earlier one.
  4. Non-TP closes (SL, Manual Close, other reasons) set WAIT_ACTIVATION or READY based on Current Price.
  5. Anchor is a Special Level separate from ordinary Grid Levels, excluded from level_count, with the same State Machine and Re-entry behavior.
- Two-sided Grid: calculate ordinary levels on both sides of actual Fill Price Anchor using Grid Step. Do not shift levels to Bounds.
- Initial state uses Current Price, not position relative to Anchor: BUY uses Ask (above=WAIT_ACTIVATION, below=READY); SELL uses Bid (below=WAIT_ACTIVATION, above=READY).
- BUY: price rises through WAIT_ACTIVATION -> READY; price retraces downward through READY/WAIT_RETURN -> Candidate. Choose lowest eligible price when multiple candidates are crossed in one Price Check.
- SELL is inverse and chooses highest eligible price.
- One Candidate maximum per Price Check. Anchor can also be a Candidate according to its state.
- Successful open must be confirmed by Runtime/Position Reconciliation before state becomes ACTIVE. Engine itself has no Trade API.
- TP close -> WAIT_RETURN; return to Entry Level produces Re-entry Candidate and becomes ACTIVE only after confirmed open.
- Current prototype files `Include/BotTrade/Grid/GridLevelEngine.mqh` and `Experts/TGK/Tests/Grids/test_grid_level_engine.mq5` are not yet updated to this design and have not been compiled/run by the user.
- User reported the 10 existing Grid Regression Tests passed on 2026-11-03 before the prototype additions.

## Open edge details before implementation
- Define exact touch/equality and anti-duplicate semantics.
- Define retry/reconciliation handoff when price moves through several candidates while an earlier request remains unresolved.
- Define handling of partial/multiple positions per Level; ACTIVE must persist while any owned position for that Level remains.
- Persistence/Restart integration is outside the pure Engine scope and needs a later integration phase.

## Next step
Review/resolve the edge details and test cases in the Design Specification. Do not edit source or begin implementation until the user explicitly approves.

## Workflow
- Work phase by phase; do not start later phases without explicit approval.
- User performs MetaEditor/MT5 tests and reports results.
- Before any Grid source feature/refactor, run relevant Grid Regression Tests first.
- Update Thai Docs and this memory after completed phases.
- Use 2-space indentation and one parameter per line for multi-parameter test calls.
- If Serena/MCP fails, remind the user to check the MCP Serena server.
