# TGK BotTradeFramework — Project Status

Last updated: 2026-10-23

## Current focus
Create a reusable MQL5 Unit Test framework, then use it to test existing Grid components before resuming Grid State Machine development.

## Current phase
**Documentation Foundation — complete.** Thai documentation structure and the first set of Grid architecture, module, testing, decision, and phase documents have been added. The next planned development phase is Grid State Machine, which has not been authorized to start yet.

The user reported that Phase 1's `Experts/TGK/Tests/Framework/test_framework.mq5` compiled and ran successfully.

### Phase 1 files and result
- `Include/BotTrade/Testing/TestAssert.mqh`
  - Assertions: true/false, int/long equality, double equality with tolerance, string equality.
- `Include/BotTrade/Testing/TestRunner.mqh`
  - Suite/test tracking, assertion logs, failure counts, and final PASS/FAIL summary.
- `Experts/TGK/Tests/Framework/test_framework.mq5`
  - Framework smoke tests; no trading calls.
- User-reported MetaEditor compile and runtime result: passed.

### Phase 2 implementation
- Added `Experts/TGK/Tests/Framework/test_framework_selftest.mq5`.
- It tests failure detection using nested runners:
  1. A deliberately failed assertion must result in 1 failed assertion, 1 failed test, and `AllPassed() == false`.
  2. A test with no assertions must count as 1 failed test, 0 failed assertions, and `AllPassed() == false`.
  3. The outer self-test suite asserts these outcomes and should finish with `FINAL RESULT: PASS` if detection/accounting works.
- The nested probes intentionally print `FINAL RESULT: FAIL`. These are expected diagnostic outputs; the final outer suite result is the acceptance result.
- No trading calls or market-data dependency.
- Status: user later confirmed MetaEditor compilation/runtime passed; see Phase 2 verification below.

## Phase 2 verification
- User reported on 2026-10-21 that `Experts/TGK/Tests/Framework/test_framework_selftest.mq5` compiled and ran in MetaEditor/MT5 with the expected results.
- The deliberate assertion failure was detected and counted; the test without assertions was also marked failed; the outer self-test suite passed.
- Phase 2 is complete based on the user's compile/runtime confirmation.

## Phase 3 progress
Created three test EAs under `Experts/TGK/Tests/Grids/`:
- `test_grid_types.mq5`: checks persisted enum numeric values and `STGKGridInstanceData` field assignment/readback. This is a type-contract/compile test, not behavior-heavy unit coverage because `GridTypes.mqh` contains declarations only.
- `test_grid_persistence.mq5`: integration tests using terminal Global Variables for missing snapshots, save/restore round-trip, identity/symbol mismatch, level-state save/restore, invalid persisted mode, and deletion. It uses a dedicated test instance namespace and does not place trades.
- `test_grid_identity.mq5`: chart integration tests for successful identity initialization and stable Instance ID/Magic Number when initialized repeatedly on the same chart. It does not place trades; it intentionally exercises the persistent chart marker and registry.

### Phase 3 validation status
- User reported on 2026-10-22 that all three Phase 3 test EAs compiled and ran successfully in MetaEditor/MT5:
  - `test_grid_types.mq5`: passed.
  - `test_grid_persistence.mq5`: passed.
  - `test_grid_identity.mq5`: passed.
- Phase 3 is complete based on this user-reported compile/runtime validation.
- Multi-chart isolation and persistence across chart close/reopen remain manual/integration checks beyond the current same-chart identity test; these are not covered by the reported Phase 3 pass.

## Grid Integration Testing — completed

User-reported results on 2026-10-23:
- `Experts/TGK/Tests/Grids/test_grid_identity_multichart.mq5`: compiled and passed.
- `Experts/TGK/Tests/Grids/test_grid_restart_persistence.mq5`: passed after changing the ChartID comparison from an assertion to diagnostic output.
- Unit Test Phases 1–3 had previously been confirmed by the user as passing.

Scope note: restoring a saved chart/Profile and manually opening a fresh chart are different lifecycle scenarios. A fresh chart may receive a new Instance ID/Magic Number; recovery of an existing Grid with open positions from a newly opened chart needs separate design and testing.

## Documentation Foundation — completed

Created the Thai-language documentation structure under `Docs/`:
- `Docs/README.md`: documentation index and maintenance rules.
- `Docs/Architecture/overview.md`: current Grid architecture and scope boundaries.
- `Docs/Modules/grid-identity.md`: Identity marker, Instance ID, and Magic Number allocation.
- `Docs/Modules/grid-persistence.md`: Snapshot keys, save/restore validation, and limitations.
- `Docs/Testing/mql5-test-framework.md`: TestAssert and TestRunner behavior.
- `Docs/Testing/grid-testing.md`: test inventory, procedures, user-reported outcomes, and regression policy.
- `Docs/Decisions/ADR-001-grid-identity-and-persistence.md`: separation of Identity and Persistence.
- `Docs/Decisions/ADR-002-chart-id-is-not-persistence-identity.md`: ChartID is diagnostic, not a restore requirement.
- `Docs/Phases/phase-grid-integration-testing.md`: integration phase scope and outcomes.
- Updated root `README.md` to link the Thai documentation index.
- Updated `AGENTS.md` with the Thai Docs workflow and phase-completion requirements.

Checks performed for this documentation change: repository content reviewed through Serena; documentation files created/updated; `git diff --check` passed; local Markdown links and referenced paths were reviewed. No MQL5 compile or runtime test was run because this phase changed documentation/workflow only.

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
- User reported `Experts/TGK/test_grid_identity.mq5` compiled and ran successfully as a smoke test, not a full Grid unit test suite.

## Important workflow
- Work phase by phase; do not start later phases without explicit user authorization.
- User performs MetaEditor compilation/runtime testing and reports results.
- Update this file after every completed phase, recording actual user-reported outcomes.
- Before any new Grid feature/refactor, run the relevant Grid Regression Tests first. If those tests are not yet available, agree on and add coverage before changing feature logic.

## Recent repository state
- Active branch at last check: `feature/grid-trading`.
