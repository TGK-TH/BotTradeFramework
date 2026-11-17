# Current TGK BotTradeFramework Phase

As of 2026-11-17, Grid Entry Execution Adapter — Round 1 persistence/mapping foundation is user-verified PASS (2026-11-15). Grid Entry Execution Policy Design Baseline and Test Plan are now approved and documented at `Docs/EAs/Grid/Phases/phase-grid-entry-execution-policy.md`; Trello card is in Ready: https://trello.com/c/Wt3XbHva/3-grid-entry-execution-policy-pure-decision-component-unit-tests. User reported latest Grid Regression Tests all PASS on 2026-11-17 and explicitly accepted this as the Phase 2 precondition. Phase 2 Test-First Implementation is still awaiting separate explicit approval. Do not create the Policy source or dedicated Test EA until approval.

## Completed slice: Persistent Journal + Typed Mapping Reducer + Snapshot Serialization/Journal Rotation

User validation: PASS (2026-11-15). Snapshot Test passed on 2026-11-14; corrected Reducer Test and all current Grid Regression Tests passed on 2026-11-15.



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
- User-approved Capacity Limits (2026-11-14): 1,000 Grid Levels per Instance (dynamic count from Bounds + Grid Step + Anchor; includes Anchor and both sides), 1,000 Position Mappings per Instance, 100 Deal Associations per Request, 1 unresolved Request per Instance, 16 MiB Snapshot, 16 MiB active Journal, 64 KiB serialized Record (including metadata/checksum/delimiter), 4 KiB per String Field, and 16 MiB Serialization Buffer.
- After Position Mapping is validated, prune Deal Associations no longer needed for Recovery from Current State.
- Overflow policy: reject without truncation; preserve the prior valid generation and all recovery-critical state. If Position Mappings reach 1,000 or Deal Associations reach 100/request, reject the new item, enter RECOVERY_ERROR, block new entries, and preserve existing data. Journal full signals Rotation before the next Append. Rotation failure enters MAINTENANCE_ERROR and blocks new entries while preserving the old generation. Snapshot >16 MiB rejects Rotation before Commit; Serialization Buffer >16 MiB aborts before file write; Record >64 KiB or String Field >4 KiB is rejected without truncation.
- Recovery statuses: NORMAL; MAINTENANCE_ERROR (Storage/Rotation/Cleanup issue; block new Entry Intent but permit safe inspection/reconciliation and non-entry state updates when Journal remains writable); RECOVERY_ERROR (Current State/Mapping unverifiable; block new entries pending inspection). Blocking new entries must never abandon existing open positions or their reconciliation. Never delete active Position Mappings or unresolved Requests to free capacity.
- Grid Level Count must match `floor((UpperBound-Anchor)/GridStep) + floor((Anchor-LowerBound)/GridStep) + 1`; Anchor is included. Anchor uses `level_index=-1`; non-anchor Levels use zero-based indices `0..level_count-2`. RESET_COMMITTED initializes READY State for every non-anchor Level so Snapshot retains Levels even when no Position is open.
- User reported `test_grid_entry_mapping_snapshot.mq5` passed all tests on 2026-11-14, then reported on 2026-11-15 that the corrected `test_grid_entry_mapping_reducer.mq5` and all current Grid Regression Tests passed. The corrected assertion verifies that a Level index in the new geometry is initialized to `TGK_GRID_LEVEL_READY` after `RESET_COMMITTED`. Snapshot Test results validate the MQL5 file rotation/recovery behavior covered by its tests.

The generation/manifest protocol and crash matrix are documented in:
- Docs/EAs/Grid/Phases/phase-grid-entry-execution-adapter-round-1.md
- Docs/EAs/Grid/Testing/testing.md
- PROJECT_STATUS.md

## Earlier components also user-verified

- `GridEntryMappingStorage.mqh` and `test_grid_entry_mapping_storage.mq5`: user reported compile/test pass plus 12 Grid Regression Tests on 2026-11-12.
- `GridEntryMappingReducer.mqh` and `test_grid_entry_mapping_reducer.mq5`: user reported compile/test pass plus historical/Grid Regression Tests on 2026-11-14. Reducer source changed again during the current Snapshot implementation, so its test must be rerun.

## Implemented in the completed slice (2026-11-14; user validation completed 2026-11-15)
- `Include/BotTrade/Grid/GridEntryMappingSnapshotStorage.mqh`: dual Manifest slots, immutable Snapshot/Journal generations, Checksum/Identity/Sequence validation, Flush + Read-back, Commit Point, restart Recovery, repeatable Cleanup, incomplete Journal tail recovery/repair, and Journal size preflight.
- `Include/BotTrade/Grid/GridEntryMappingReducer.mqh`: `ExportSnapshot()` / `RestoreSnapshot()` for Config, every non-anchor Level State, active Position Mappings, and unresolved Request/Deal Associations; validates geometry-derived Level Count and mapping relationships.
- `Experts/TGK/Tests/Grids/test_grid_entry_mapping_snapshot.mq5`: no-trading test EA for Snapshot round-trip, Journal N+1 replay, Manifest alternation, Rotation, cleanup, fallback to an older valid generation, crash injection, incomplete-tail repair, Journal/Snapshot/Record/String limits, and Mapping/Deal boundaries.
- Assistant ran static checks only: `git diff --check`, final newline, delimiter balance, and feature/failure-matrix token checks. No MetaEditor/MT5 compile/runtime was run. Actual MQL5 File API replacement/deletion semantics still require user validation.

## Next phase (requires explicit user approval)
The next proposed slice is Entry Execution Policy + dedicated Unit Tests. Before changing any Grid source, run the latest Grid Regression Tests. Do not start this slice until the user explicitly approves.

No trade APIs or real/demo Trade Requests are part of this slice.

Before any Grid source changes, run the latest Grid Regression Tests. User performs MetaEditor/MT5 compile/runtime tests; never claim these were run by Assistant.