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
- User-approved Capacity Limits (2026-11-14): 1,000 Grid Levels per Instance (dynamic count from Bounds + Grid Step + Anchor; includes Anchor and both sides), 1,000 Position Mappings per Instance, 100 Deal Associations per Request, 1 unresolved Request per Instance, 16 MiB Snapshot, 16 MiB active Journal, 64 KiB serialized Record (including metadata/checksum/delimiter), 4 KiB per String Field, and 16 MiB Serialization Buffer.
- After Position Mapping is validated, prune Deal Associations no longer needed for Recovery from Current State.
- Overflow policy: reject the operation/rotation without truncation; preserve the prior valid generation and all recovery-critical state. User approved the detailed behavior on 2026-11-14: if Position Mappings reach 1,000 or Deal Associations reach 100 per Request, reject the new item, enter RECOVERY_ERROR, block new entries, and preserve existing data; Journal full pauses Append and triggers Snapshot+Rotation before the next Append; Rotation failure enters MAINTENANCE_ERROR and blocks new entries while preserving the old generation. Snapshot >16 MiB rejects Rotation before Commit; Serialization Buffer >16 MiB aborts before file write; Record >64 KiB or String Field >4 KiB is rejected without truncation. Recovery statuses are NORMAL (normal trading), MAINTENANCE_ERROR (Storage/Rotation/Cleanup issue; block new entries but permit inspection/reconciliation of existing positions), and RECOVERY_ERROR (Current State unverifiable; block new entries pending inspection). Blocking new entries must never abandon existing open positions or their reconciliation. Never delete active Position Mappings or unresolved Requests to free capacity.
- Remaining design/test work: validate MQL5 File API generation/manifest replacement and deletion semantics; define and run boundary/failure-injection tests for all agreed limits.

The generation/manifest protocol and crash matrix are documented in:
- Docs/EAs/Grid/Phases/phase-grid-entry-execution-adapter-round-1.md
- Docs/EAs/Grid/Testing/testing.md
- PROJECT_STATUS.md

## Completed and user-verified
- GridEntryMappingStorage.mqh and test_grid_entry_mapping_storage.mq5: user reported compile/test pass plus 12 Grid Regression Tests on 2026-11-12.
- GridEntryMappingReducer.mqh and test_grid_entry_mapping_reducer.mq5: user reported compile/test pass plus all historical/Grid Regression Tests on 2026-11-14.

## Remaining sequence
1. Validate MQL5 File API behavior for generation files, manifest slots, safe cleanup, and failure recovery; prepare boundary/failure-injection tests for all agreed Capacity Limits.
2. Add Snapshot Serialization + Journal Rotation implementation and fixture/failure-injection tests; no trade APIs.
3. User compiles/runs new Snapshot test and all current Grid Regression Tests.
4. Only then proceed to Entry Execution Policy + tests, CTrade Adapter + no-live-trade seam tests, and Coordinator integration.
5. Demo Integration is separate and requires explicit user approval.

Before any Grid source changes, run the latest Grid Regression Tests. User performs MetaEditor/MT5 compile/runtime tests; never claim these were run by Assistant.