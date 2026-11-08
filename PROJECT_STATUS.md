# TGK BotTradeFramework — Project Status

Last updated: 2026-11-07

## Current focus
**Grid Level Runtime Coordinator — Round 1: Source and Test EA added; awaiting user-reported MetaEditor/MT5 validation.**

## Current phase
**Grid Level Runtime Coordinator — Round 1: Implementation added; validation pending.** User reported all 11 existing Grid Regression Tests passed before implementation on 2026-11-07. Added the pure Coordinator and its Test EA; next gate is compile/run of the new test plus all 11 existing Grid Regression Tests.

Previous completed phase: **Grid Level Engine — Round 1** (user-reported 11/11 tests passed, 2026-11-04).

### Current implementation files
- `Include/BotTrade/Grid/GridLevelRuntimeCoordinator.mqh`: pure coordination of Engine Candidate handoff, one unresolved Entry Request, best Deferred Candidate, explicit Position mapping, and close events; no CTrade or live account scan.
- `Experts/TGK/Tests/Grids/test_grid_level_runtime_coordinator.mq5`: no-trading tests for request lifecycle, BUY/SELL deferred selection, Anchor registration/re-entry, mapping validation, and partial/full close.
- User-reported baseline: all 11 existing Grid Regression Tests passed on 2026-11-07 before implementation.
- **Validation pending:** new Test EA plus all 11 existing Grid Regression Tests must compile/run in MetaEditor/MT5. Assistant did not run MetaEditor/MT5.

### Design decisions confirmed
- Two-sided Grid Levels from actual Fill Price (Anchor) + Grid Step; Anchor is separate and supports Re-entry, excluded from ordinary LevelCount.
- Bounds are hard filters; no shifting levels to bounds. Anchor=4000, Step=5, Bounds=3992..4012 -> 3995, 4005, 4010.
- Initial state uses Current Price: BUY Ask (above/equal WAIT_ACTIVATION, below READY); SELL Bid (below/equal WAIT_ACTIVATION, above READY).
- BUY activates upward through WAIT_ACTIVATION, enters downward through READY/WAIT_RETURN and selects the lowest crossed eligible price.
- SELL is inverse and selects the highest crossed eligible price.
- One candidate maximum per Price Check; Anchor can be a candidate.
- Unselected crossed READY/WAIT_RETURN levels left on the wrong side of Current Price become WAIT_ACTIVATION; ACTIVE is unchanged.
- TP close uses WAIT_RETURN only when Level remains on the retrace side of Current Price; if price has moved past the Level, use WAIT_ACTIVATION. Non-TP close uses WAIT_ACTIVATION/READY from Current Price.
- Accepted request is not proof of open Position. Runtime/Execution must reconcile before ACTIVE; unresolved requests must not be duplicated. A better candidate can replace a definitively failed earlier candidate.
- One logical open Position per Level; partial close leaves ACTIVE until no Position remains. Runtime maps positions to Level IDs.

### Round 1 files changed
- `Include/BotTrade/Grid/GridLevelEngine.mqh`: rewritten for Two-sided levels, Anchor state, activation/entry crossing, best-price candidate selection, close/entry outcome callbacks; caller passes total `level_count`, which Engine validates against Bounds.
- `Include/BotTrade/Grid/GridTypes.mqh`: appended `WAIT_ACTIVATION` enum value, preserving numeric values of existing states.
- `Include/BotTrade/Grid/GridPersistence.mqh`: enum validation now accepts `WAIT_ACTIVATION`.
- `Experts/TGK/Tests/Grids/test_grid_level_engine.mq5`: rewritten to cover new Engine behavior.
- `Experts/TGK/Tests/Grids/test_grid_persistence.mq5`: added WAIT_ACTIVATION save/restore coverage.
- `Experts/TGK/Tests/Grids/test_grid_types.mq5`: added assertion that WAIT_ACTIVATION retains appended enum value 3.
- Existing production Grid EA and Trade API integration remain out of scope.

### Validation
- Baseline: user reported all 10 existing Grid Regression Tests passed on 2026-11-03 before this Round 1 implementation.
- **Final validation: user reported on 2026-11-04 that compilation and all 11 Grid Regression Tests passed in MetaEditor/MT5.** This is user-reported validation; the assistant did not independently run MetaEditor/MT5.
- Round 1 is complete. The result validates the Pure Grid Level Engine and its covered persistence/type contracts; it does not validate production EA event-handler integration, live multi-level order execution, or the full Grid V1 system.

Previous completed implementation phase: Grid Order Execution — Demo Integration Test (user-reported FINAL PASS, 2026-11-02). Earlier phase: **Grid Order Execution Adapter — Round 1: Completed (user-reported 10/10 MetaEditor/MT5 tests passed, 2026-10-31).** See `Docs/EAs/Grid/Phases/phase-grid-order-execution.md`.

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

## Grid Runtime Orchestration — implementation round 1 (2026-10-30)

Added:
- `Include/BotTrade/Grid/GridRuntimeOrchestrator.mqh`: accepts an already-initialized Instance ID/Symbol/Magic Number; initializes/restores Lifecycle from a fresh Symbol + Magic position count; coordinates reset state with Position Reconciler; reports `CLOSE_REQUIRED`, `WAIT_CLOSE_CONFIRMATION`, `WAIT_INITIAL_ENTRY`, `ACTIVE`, or `ERROR`.
- `Experts/TGK/Tests/Grids/test_grid_runtime_orchestrator.mq5`: no-trading Snapshot tests for initialization, fill, reset/retry/rebuild, restart during reset, market closed, and orphan positions.
- `Docs/EAs/Grid/Phases/phase-grid-runtime-orchestration.md`: implementation scope and validation procedure.

Safety boundaries:
- The caller must initialize `CTGKGridIdentity` first; Orchestrator does not allocate identity.
- The Orchestrator never opens or closes positions. `CLOSE_REQUIRED` is a signal for a future Execution adapter.
- Each update re-counts positions; accepted close requests are not treated as proof of closure.
- Position ownership is exact Symbol + Magic Number. This phase does not manage pending orders.

Checks performed: source review and `git diff --check` completed successfully; no MetaEditor/MT5 compiler or runtime was run through this workflow. User must compile/run the new test and all eight existing Grid tests before this phase can be marked validated. Do not begin Order Execution until separately scoped and authorized.

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
