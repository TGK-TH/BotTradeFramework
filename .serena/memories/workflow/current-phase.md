# Current TGK BotTradeFramework Phase

As of 2026-10-27, Grid State Machine round 1 is complete based on user-reported MetaEditor/MT5 validation: `test_grid_state_machine.mq5` and all five previous Grid Regression Tests passed after those changes.

## Current phase: Grid Lifecycle Integration — round 1 awaiting user compile/runtime validation
User explicitly authorized this phase on 2026-10-27. Scope: integrate State Machine lifecycle transitions with snapshot persistence for an already-identified Grid Instance, with no trade execution.

Added/modified files:
- `Include/BotTrade/Grid/GridLifecycle.mqh`: `CTGKGridLifecycle` coordinates persistence and state machine. Caller initializes `CTGKGridIdentity` first, then passes Instance ID and Magic Number. It persists after initial fill/configuration/reset transitions; accepts fresh remaining-position counts from caller; does not send open/close requests.
- `Include/BotTrade/Grid/GridPersistence.mqh`: added `HasSnapshot()` to distinguish missing snapshot from a present snapshot that fails Restore.
- `Experts/TGK/Tests/Grids/test_grid_lifecycle.mq5`: no-trading integration tests for fresh instance, actual fill/Anchor restore, Mode reset across restart, missing snapshot with remaining positions, Magic mismatch, and invalid snapshot enum.
- `Docs/EAs/Grid/Phases/phase-grid-lifecycle-integration.md` and related docs/status updated.

Safety behavior in this round: a missing snapshot with remaining positions, invalid snapshot, Magic mismatch, Fixed Lot mismatch, or changed inputs during a pending reset leads to `RECOVERY_ERROR`. Fixed Lot changes are not supported in this phase. If snapshot saving fails, lifecycle operations report failure and block state changes in the current instance. `RequestConfiguration` does not close positions; caller must perform order management in a later authorized phase.

Validation by assistant: `git diff --check` passed and local Markdown-link check passed. No MetaEditor/MT5 compilation or runtime execution was performed. User needs to compile/run `Experts/TGK/Tests/Grids/test_grid_lifecycle.mq5`, then rerun `test_grid_state_machine.mq5` and all five existing Grid Regression Tests because `GridPersistence.mqh` changed. Do not claim test success until user reports it.

Lifecycle decision remains: manually opening a new chart creates a new Grid Instance with new Instance ID/Magic Number and must not manage old Grid positions. Existing Grid resumes only when saved chart/profile and prior identity/persistence are restored. No auto-adoption from a new chart.

Workflow: phase-by-phase, no later phase without explicit user authorization. Before any Grid feature/refactor run relevant regression tests. User performs MetaEditor/MT5 tests and reports results. Use 2-space indentation; multi-parameter calls one argument per line.