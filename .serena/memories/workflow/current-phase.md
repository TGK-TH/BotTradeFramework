# Current TGK BotTradeFramework Phase

As of 2026-11-12, Grid Level Runtime Coordinator — Round 1 remains completed and user-verified (12/12 PASS). The Persistent Journal foundation slice in Grid Entry Execution Adapter — Round 1 is implemented and user-verified: the user reported `GridEntryMappingStorage.mqh` compiled, its new Unit Test passed, and all 12 existing Grid Regression Tests passed.

## Current phase: Grid Entry Execution Adapter — Round 1
Status: **Implementation in progress; Persistent Journal foundation complete/user-verified; Snapshot + Journal Rotation retention policy agreed on 2026-11-12.**

User decisions:
- Persistent Mapping is the only source of truth for Entry Request / Order / Deal / Position / Logical Level relationships.
- Order Comment is human-readable metadata only; never parse or use it for mapping, restore, fill confirmation, or state transitions.
- Keep existing `CTGKGridPersistence` / Terminal Global Variables for Grid Snapshot and Level State; separate Entry Mapping journal remains under terminal `MQL5/Files`.
- Do not use `FILE_COMMON` in Round 1.
- Store Order Ticket, Deal Ticket and Position Identifier as decimal Strings, never as double.
- Persist and Flush Entry Intent before sending any trade request. Persistence failure blocks execution.
- Accepted/Placed is not proof of fill; only validated Position reconciliation may confirm mapping and make a level ACTIVE.
- One unresolved Entry Request per Instance; no approximate Fill Price inference.
- Support multiple Deals for one Position Identifier when consistent with partial fills; conflicting Position Identifiers for one Request enter Recovery Error.
- Snapshot is a **Current State Store, not Trade History**. It stores current Grid configuration/Anchor, all current Grid Level States, active Position Mappings, unresolved Requests and Last applied Journal Sequence, with schema/identity/integrity metadata.
- After confirmed zero-volume Position Reconciliation, prune that Position Mapping but retain its Grid Level Index/State (e.g. WAIT_RETURN).
- Keep Levels with no Position while they remain part of the current Grid configuration.
- Prune old Level States after Mode/Step Reset only when reset is confirmed, no old Positions remain, and no unresolved Request references the old configuration.
- Being outside Bounds alone is not a reason to prune a Level.
- Do not retain closed Trade/Deal history in Snapshot unless still required for Reconciliation/Recovery.
- Journal threshold is 16 MiB per active segment; Snapshot + Rotation is required for long-running operation. Snapshot must have its own size/count validation.
- Rotation must preserve sequence continuity and must not delete old journal generation until new Snapshot and journal generation are flushed, read back and validated. Crash matrix/commit mechanism will be designed before implementation.

## Completed and user-verified in current phase
- `Include/BotTrade/Grid/GridEntryMappingStorage.mqh`: per Account/Server/Symbol/Instance journal in terminal MQL5/Files, schema version, sequence, checksum, UTF-8 hex payload, strict replay, incomplete final tail recovery via flushed temporary file replacement, checked write/flush result.
- `Experts/TGK/Tests/Grids/test_grid_entry_mapping_storage.mq5`: no-trading tests for identity, append/replay, sequence, large decimal identifier strings, instance isolation, comment independence, incomplete tail, malformed complete record.
- User reported 2026-11-12: source compiled, new Unit Test passed, and all 12 Grid Regression Tests passed in MetaEditor/MT5 (13 Test EAs checked).
- Current Storage implementation has a 16 MiB safety cap in `TrimIncompleteTail()` and `ReadJournal()`; exceeding it blocks append/replay. Snapshot/Rotation is not implemented yet.

## Next implementation sequence
1. Typed Mapping Payload schema, validation and deterministic Current-State Reducer; first add `test_grid_entry_mapping_reducer.mq5` fixtures and tests.
2. Snapshot serialization and Journal Rotation design, generation/commit protocol and Crash Recovery Matrix.
3. Snapshot + Rotation implementation and failure/crash injection tests.
4. Entry Execution Policy + tests.
5. CTrade Adapter + no-live-trade seam tests.
6. Coordinator integration, docs and regression; user performs MetaEditor/MT5 compile/run.
7. Demo Integration remains separate and requires explicit user approval.

Before any source changes, run the relevant Grid Regression Tests (currently 12 files). Do not start Entry Policy/CTrade Adapter until the Typed Reducer slice is complete and verified. Do not send real or Demo trade requests unless the user explicitly authorizes the Demo test.
