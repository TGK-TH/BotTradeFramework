# TGK BotTradeFramework — Project Status

Last updated: 2026-10-29

## Current focus
Grid State Machine round 1 and Grid Lifecycle Integration round 1 are complete based on user-reported MetaEditor/MT5 results. Grid Runtime & Position Reconciliation round 1 is complete based on the user's report that the new test and all seven existing Grid tests compiled and passed in MetaEditor/MT5 on 2026-10-29. Actual order execution remains out of scope until separately authorized.

## Current phase
**Grid Runtime & Position Reconciliation — round 1 complete (user-reported tests passed).** The phase adds a read-only live position scan filtered by Symbol + Magic Number and a policy boundary for accepted/failed/market-closed close attempts. It does not send trade requests or integrate a complete EA runtime.

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

## Grid State Machine — implementation round 1 (2026-10-26)

Added:
- `Include/BotTrade/Grid/GridStateMachine.mqh`: validates initial data, records actual initial fill as Anchor, requests Mode/Step/Magic reset, waits for confirmed zero remaining positions before rebuilding, clears Anchor for Mode changes, retains Anchor for Step changes, and blocks state-changing operations in Recovery Error.
- `Experts/TGK/Tests/Grids/test_grid_state_machine.mq5`: no-trading tests for initial state, fill/Anchor, Mode reset, Step reset, invalid inputs, and Recovery Error.
- `Docs/EAs/Grid/Phases/phase-grid-state-machine.md`: lifecycle decision, scope, limitations, and next steps.

Status: user reported on 2026-10-27 that `test_grid_state_machine.mq5` compiled and ran successfully in MetaEditor/MT5. The user also reran all five Grid Regression Tests after the State Machine source changes and reported that all passed. Assistant did not independently run MetaEditor/MT5. Round 1 is complete based on user-reported validation. Order execution, bounds, grid level generation, TP handling, and EA integration remain out of scope for this round.

## Grid Lifecycle Integration — implementation round 1 (2026-10-27)

Added/changed:
- `Include/BotTrade/Grid/GridLifecycle.mqh`: coordinates State Machine transitions with snapshot restore/save for an already-identified Grid Instance; does not execute trades.
- `Include/BotTrade/Grid/GridPersistence.mqh`: added `HasSnapshot()` to distinguish a missing snapshot from a present snapshot that fails Restore.
- `Experts/TGK/Tests/Grids/test_grid_lifecycle.mq5`: no-trading integration tests for fresh initialization, fill/Anchor restore, pending Mode reset across restart, missing snapshot with remaining positions, and Magic mismatch.
- `Docs/EAs/Grid/Phases/phase-grid-lifecycle-integration.md`: scope and test plan.

Safety behavior: missing/invalid snapshot with remaining positions, Magic mismatch, Fixed Lot mismatch, or unsupported input changes during a pending reset leads to `RECOVERY_ERROR`. The caller must supply a fresh remaining-position count filtered by this Instance's Symbol and Magic Number. The coordinator does not initialize `CTGKGridIdentity`; the EA must initialize Identity and pass its Instance ID/Magic Number.

Status: user reported on 2026-10-28 that `test_grid_lifecycle.mq5`, `test_grid_state_machine.mq5`, `test_grid_types.mq5`, `test_grid_persistence.mq5`, `test_grid_identity.mq5`, `test_grid_identity_multichart.mq5`, and `test_grid_restart_persistence.mq5` all compiled and ran successfully in MetaEditor/MT5. Assistant did not independently run MetaEditor/MT5. Round 1 is complete based on user-reported validation. No Order Execution or actual close/open requests are included.

## Grid Runtime & Position Reconciliation — round 1 (2026-10-29)

Added:
- `Include/BotTrade/Grid/GridPositionReconciler.mqh`: exact Symbol + Magic ownership filtering, read-only live position counting, fixture snapshot counting, and close-attempt/reconciliation policy.
- `Experts/TGK/Tests/Grids/test_grid_position_reconciler.mq5`: no-trading tests for ownership isolation, close accepted vs actual closure, market closed, failed close, restart behavior, and invalid count recovery.
- `Docs/EAs/Grid/Phases/phase-grid-runtime-position-reconciliation.md`: scope, test-first coverage, limits, and validation steps.

Safety rules:
- A close request being accepted does not prove the position has closed.
- A fresh live position scan must be filtered by both Symbol and Magic Number.
- A failed live scan returns an invalid count; it must not be treated as zero positions.
- A newly constructed reconciler does not assume an old close request is still pending after restart.
- This is only a read-only/policy boundary. It does not send close requests or connect a complete EA runtime.

Status: user reported Compile/Runtime PASS in MetaEditor/MT5 on 2026-10-29 for the new reconciler test and all seven existing Grid tests. This is user-reported validation; the assistant did not independently run MetaEditor/MT5.

## Grid Regression Baseline — user-reported pass (2026-10-26)

The user explicitly confirmed all five current Grid Regression Tests passed before Grid State Machine work began:
- `Experts/TGK/Tests/Grids/test_grid_types.mq5`
- `Experts/TGK/Tests/Grids/test_grid_persistence.mq5`
- `Experts/TGK/Tests/Grids/test_grid_identity.mq5`
- `Experts/TGK/Tests/Grids/test_grid_identity_multichart.mq5`
- `Experts/TGK/Tests/Grids/test_grid_restart_persistence.mq5`

These are user-reported MetaEditor/MT5 results, not tests executed by the assistant. Treat this as the baseline for the current phase; rerun relevant regression tests after source changes.

## Documentation Structure — completed

The documentation hierarchy now reflects that BotTradeFramework will contain multiple EAs, not Grid alone:
- `Docs/README.md`: project-wide documentation index and documentation rules.
- `Docs/Framework/README.md`: scope and rules for genuinely shared components.
- `Docs/Framework/Testing/mql5-test-framework.md`: shared `TestAssert` and `TestRunner` documentation.
- `Docs/EAs/README.md`: index of EAs with documentation and guidance for adding a new EA.
- `Docs/EAs/Grid/README.md`: Grid-specific index and boundary between agreed requirements and implemented behavior.
- `Docs/EAs/Grid/architecture.md`: current Grid architecture and scope boundaries.
- `Docs/EAs/Grid/modules/identity.md`: Grid Identity marker, Instance ID, and Magic Number allocation.
- `Docs/EAs/Grid/modules/persistence.md`: Grid Snapshot keys, save/restore validation, and limitations.
- `Docs/EAs/Grid/Testing/testing.md`: test inventory, procedures, user-reported outcomes, and regression policy.
- `Docs/Decisions/README.md`: central ADR index, separated by scope.
- `Docs/EAs/Grid/Decisions/`: Grid-specific ADRs; neither ADR is a Framework-wide rule.
- `Docs/EAs/Grid/Phases/phase-grid-integration-testing.md`: scope and outcomes of Grid Integration Testing.
- `Docs/Development/workflow.md`: phase workflow and documentation responsibilities.
- `Docs/Development/phase-documentation-structure.md`: record of this documentation restructuring phase.
- Updated root `README.md` and `AGENTS.md` to describe the multi-EA documentation model and maintenance rules.

Validation performed for this documentation-only phase: checked the moved/created files and Markdown references, then ran `git diff --check` and a local-link validation script. No MQL5 compile or runtime test was performed because no MQL5 source behavior changed.

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
