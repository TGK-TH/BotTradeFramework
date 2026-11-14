# Current TGK BotTradeFramework Phase

As of 2026-11-14, Grid Entry Execution Adapter — Round 1 remains in progress. Persistent Journal foundation and Typed Mapping Reducer had user-reported Compile/Run PASS before the current Snapshot implementation. Snapshot Serialization + Journal Rotation source and tests have now been added; user Compile/Run validation is pending.

## Current slice: Snapshot Serialization + Journal Rotation — implementation draft

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
- User reported `test_grid_entry_mapping_snapshot.mq5` passed all tests on 2026-11-14. The first rerun of `test_grid_entry_mapping_reducer.mq5` found one assertion mismatch: after RESET_COMMITTED, a Level that existed before Reset is recreated in the new configuration as READY (enum value 0), not absent (`-1`). The test assertion was corrected to expect `TGK_GRID_LEVEL_READY`; user Compile/Run of the corrected Reducer Test and the full Grid Regression suite remains pending. Actual MQL5 File API replacement/deletion semantics are being validated by the Snapshot Test run.

The generation/manifest protocol and crash matrix are documented in:
- Docs/EAs/Grid/Phases/phase-grid-entry-execution-adapter-round-1.md
- Docs/EAs/Grid/Testing/testing.md
- PROJECT_STATUS.md

## Completed and user-verified before this slice
- `GridEntryMappingStorage.mqh` and `test_grid_entry_mapping_storage.mq5`: user reported compile/test pass plus 12 Grid Regression Tests on 2026-11-12.
- `GridEntryMappingReducer.mqh` and `test_grid_entry_mapping_reducer.mq5`: user reported compile/test pass plus historical/Grid Regression Tests on 2026-11-14. Reducer source changed again during the current Snapshot implementation, so its test must be rerun.

## Implementation added in the current slice (2026-11-14; user validation pending)
- `Include/BotTrade/Grid/GridEntryMappingSnapshotStorage.mqh`: dual Manifest slots, immutable Snapshot/Journal generations, Checksum/Identity/Sequence validation, Flush + Read-back, Commit Point, restart Recovery, repeatable Cleanup, incomplete Journal tail recovery/repair, and Journal size preflight.
- `Include/BotTrade/Grid/GridEntryMappingReducer.mqh`: `ExportSnapshot()` / `RestoreSnapshot()` for Config, every non-anchor Level State, active Position Mappings, and unresolved Request/Deal Associations; validates geometry-derived Level Count and mapping relationships.
- `Experts/TGK/Tests/Grids/test_grid_entry_mapping_snapshot.mq5`: no-trading test EA for Snapshot round-trip, Journal N+1 replay, Manifest alternation, Rotation, cleanup, fallback to an older valid generation, crash injection, incomplete-tail repair, Journal/Snapshot/Record/String limits, and Mapping/Deal boundaries.
- Assistant ran static checks only: `git diff --check`, final newline, delimiter balance, and feature/failure-matrix token checks. No MetaEditor/MT5 compile/runtime was run. Actual MQL5 File API replacement/deletion semantics still require user validation.

## User validation required next
1. Compile/run `Experts/TGK/Tests/Grids/test_grid_entry_mapping_snapshot.mq5`.
2. Recompile/run `Experts/TGK/Tests/Grids/test_grid_entry_mapping_reducer.mq5` because Reducer source changed.
3. Run all current Grid Regression Tests, including `test_grid_entry_mapping_storage.mq5`.
4. Report compile errors, failing assertions, Journal size/Rotation issues, or unexpected files left in MQL5/Files.
5. Do not start Entry Execution Policy until this slice passes and the user explicitly approves the next phase.

No trade APIs or real/demo Trade Requests are part of this slice.

Before any Grid source changes, run the latest Grid Regression Tests. User performs MetaEditor/MT5 compile/runtime tests; never claim these were run by Assistant.