# TGK BotTradeFramework — Project Status

Last updated: 2026-10-21

## Current focus
Create a reusable MQL5 Unit Test framework, then use it to test existing Grid components before resuming Grid State Machine development.

## Current phase
**Unit Testing — Phase 1 completed; waiting to begin Phase 2.**

The user reported on 2026-10-21 that `Experts/TGK/Tests/Framework/test_framework.mq5` compiled and ran successfully.

### Phase 1 files
- `Include/BotTrade/Testing/TestAssert.mqh`
  - Assertions: true/false, int/long equality, double equality with tolerance, string equality.
- `Include/BotTrade/Testing/TestRunner.mqh`
  - Suite/test tracking, assertion logs, failure counts, and final PASS/FAIL summary.
- `Experts/TGK/Tests/Framework/test_framework.mq5`
  - Framework smoke tests; no trading calls.

### Verification
- User-reported MetaEditor compile and runtime test: passed.
- Earlier static check: `git diff --check` passed.
- Phase 2 has not started. Do not begin until the next step is discussed and the user authorizes it.

## Next steps
1. Agree on and perform Unit Testing Phase 2: test the framework's own failure detection and result accounting, including a controlled failing assertion/test case that cannot accidentally be mistaken for a passing suite.
2. Then test existing Grid components with dedicated files under `Experts/TGK/Tests/Grids/`:
   - `GridTypes.mqh`
   - `GridPersistence.mqh`
   - `GridIdentity.mqh`
3. Decide which Grid checks are unit tests and which require chart/account integration or smoke tests.
4. Only after the test foundation and Grid tests are in place, resume Grid State Machine/reset behavior work.

## Grid context and constraints
- Grid V1 is intended to manage one Grid per EA/chart instance.
- Use chart symbol (`_Symbol`), not a user-provided Symbol input.
- Grid instance identity should distinguish multiple instances on different chart windows, including the same symbol/timeframe.
- Automatically generated/persisted Magic Number and Grid Instance identity are preferred over a user-entered Magic Number.
- Manage only positions/orders belonging to the relevant chart symbol and this Grid instance's Magic Number. Never touch manual trades or other EAs.
- Anchor is the actual fill price of the first order.
- Grid levels are derived from Anchor and GridStep; bounds filter eligibility but do not shift levels.
- Initial order waits until price is inside bounds. If price is outside bounds, no new entries; existing positions and their TP management continue.
- After a level's position closes at TP, wait for price to return to that level before reopening it.
- Step changes close existing Grid positions, wait for confirmed closure, then recalculate levels from the previous Anchor using the new step.
- Mode changes close old positions and wait for confirmed closure before starting the new mode with a new Anchor from the first new fill.
- A successful close request is not proof that all positions have closed; reconcile actual account state and retry when needed.
- Restart recovery must preserve Anchor, level state, pending reset, and prior Magic Number; do not infer all state only from remaining positions.
- A known design constraint: `TargetPositionReconciler.mqh` stores one desired direction and cannot be reused unchanged for a multi-level Grid.

## Existing Grid files and prior checks
- `Include/BotTrade/Grid/GridTypes.mqh`
- `Include/BotTrade/Grid/GridPersistence.mqh`
- `Include/BotTrade/Grid/GridIdentity.mqh`
- User previously reported the first two Grid files compiled successfully.
- User reported `Experts/TGK/test_grid_identity.mq5` compiled and ran successfully as a smoke test.
- The test EA above is a smoke test, not yet a full Grid unit test suite.

## Important workflow
- Work phase by phase; do not start later phases without explicit user authorization.
- User performs MetaEditor compilation/runtime testing and reports results.
- Update this file after every completed phase, recording actual user-reported outcomes.
- Before any new Grid feature/refactor, run the relevant Grid Regression Tests first. If those tests are not yet available, agree on and add coverage before changing feature logic.

## Recent repository state
- Active branch at last check: `feature/grid-trading`.
- At last check, `git status --short` showed no pre-existing working-tree changes before these context files were created.
