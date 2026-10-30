# Current TGK BotTradeFramework Phase

As of 2026-10-30, Grid Runtime Orchestration round 1 has been implemented and is awaiting user MetaEditor/MT5 validation.

## Current implementation
- Added `Include/BotTrade/Grid/GridRuntimeOrchestrator.mqh`.
  - Accepts an already-initialized Instance ID, Symbol, and Magic Number; caller must initialize `CTGKGridIdentity` first.
  - Initializes/restores `CTGKGridLifecycle` using a fresh position count filtered by exact Symbol + Magic Number.
  - Provides live account methods and deterministic Snapshot fixture methods.
  - Coordinates `CTGKGridPositionReconciler` with Lifecycle reset transitions.
  - Reports runtime statuses: ERROR, WAIT_INITIAL_ENTRY, ACTIVE, CLOSE_REQUIRED, WAIT_CLOSE_CONFIRMATION.
  - Signals that an execution adapter should close positions; it never sends trade requests.
  - Recounts positions on each update; accepted close requests are not treated as proof of closure.
  - When zero owned positions are confirmed, advances RESET_CLOSE_OLD -> RESET_REBUILD -> applies pending configuration.
- Added `Experts/TGK/Tests/Grids/test_grid_runtime_orchestrator.mq5`.
  - Snapshot tests for fresh initialization, actual fill, mode reset close/retry/rebuild, restart during pending reset, failed close, market closed, and orphan positions.
  - No trading calls.
- Added `Docs/EAs/Grid/Phases/phase-grid-runtime-orchestration.md` and updated Grid architecture/testing docs plus `PROJECT_STATUS.md`.

## Checks and validation status
- `git diff --check`: PASS.
- Trailing-whitespace check for new files: PASS.
- Local Markdown link check for changed docs: PASS.
- User reported on 2026-10-29 that all 8 prior Grid tests passed in MetaEditor/MT5.
- New test and all 8 existing Grid tests still require user Compile/Runtime validation. Assistant has not run MetaEditor/MT5.
- Do not mark this phase validated until user reports the results.

## Safety / boundaries
- No real open/close orders; no CTrade dependency.
- No EA OnInit/OnTick/OnTimer adapter yet.
- No pending-order management, Grid levels, Bounds, TP, re-entry, or actual entry execution.
- Order Execution remains a separately scoped future phase requiring explicit authorization.
- If Serena/MCP fails during coding, remind user to check the MCP Serena server.

## Next action
Ask user to compile/run `test_grid_runtime_orchestrator.mq5` and all eight existing Grid regression tests in MetaEditor/MT5, then report PASS/FAIL before proceeding.
