# Current TGK BotTradeFramework Phase

As of 2026-11-14, Grid Entry Execution Adapter — Round 1 remains in progress. Persistent Journal foundation and Typed Mapping Reducer are user-verified. User confirmed on 2026-11-14 that the Reducer test and all historical/Grid Regression Tests passed.

## Current next slice: Snapshot Serialization + Journal Rotation Design/Test, then Implementation

User-approved retention contract:
- Snapshot stores Current State only, not Trade History.
- After successful Rotation and Cleanup: exactly one committed Snapshot, one active Journal, and two fixed Manifest metadata slots (manifest_A.dat, manifest_B.dat).
- No old Journal generations or temporary data files remain after successful Cleanup.
- Old and new generations may coexist temporarily during Rotation.
- Never delete the old generation until the new Snapshot and Journal have passed Flush, Read-back Validation, and the new Manifest has been written, flushed, and read back successfully (Commit Point).
- Manifest slots are alternated; writing the inactive slot must never destroy the currently active slot.
- Recovery validates both manifests and referenced data sets, selects the valid manifest with the highest Commit Epoch, restores Snapshot at Sequence N, and replays Journal from N+1.
- Crash before Commit -> old generation; crash after Commit -> new generation; crash during cleanup -> new generation plus repeatable cleanup.
- If no complete valid manifest/data set exists, enter Recovery Error and do not trade.
- Cleanup failure must not delete active data or force deletion to meet the file-count target.
- Snapshot Size/Count hard limits remain to be decided before implementation.

The generation/manifest protocol and crash matrix are documented in:
- Docs/EAs/Grid/Phases/phase-grid-entry-execution-adapter-round-1.md
- Docs/EAs/Grid/Testing/testing.md
- PROJECT_STATUS.md

## Completed and user-verified
- GridEntryMappingStorage.mqh and test_grid_entry_mapping_storage.mq5: user reported compile/test pass plus 12 Grid Regression Tests on 2026-11-12.
- GridEntryMappingReducer.mqh and test_grid_entry_mapping_reducer.mq5: user reported compile/test pass plus all historical/Grid Regression Tests on 2026-11-14.

## Remaining sequence
1. Finalize Snapshot Size/Count Hard Limits and validate MQL5 file API behavior for generation files, manifest slots, safe cleanup, and failure recovery.
2. Add Snapshot Serialization + Journal Rotation implementation and fixture/failure-injection tests; no trade APIs.
3. User compiles/runs new Snapshot test and all current Grid Regression Tests.
4. Only then proceed to Entry Execution Policy + tests, CTrade Adapter + no-live-trade seam tests, and Coordinator integration.
5. Demo Integration is separate and requires explicit user approval.

Before any Grid source changes, run the latest Grid Regression Tests. User performs MetaEditor/MT5 compile/runtime tests; never claim these were run by Assistant.