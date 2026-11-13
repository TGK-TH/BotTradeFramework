# Current TGK BotTradeFramework Phase

As of 2026-11-12, Grid Level Runtime Coordinator — Round 1 remains completed and user-verified (12/12 PASS). The Persistent Journal foundation slice in Grid Entry Execution Adapter — Round 1 is implemented and user-verified: the user reported `GridEntryMappingStorage.mqh` compiled, its new Unit Test passed, and all 12 existing Grid Regression Tests passed.

## Current phase: Grid Entry Execution Adapter — Round 1
Status: **Persistent Journal foundation complete/user-verified; Typed Mapping Reducer implemented and pending user Compile/Run verification; Snapshot + Journal Rotation retention policy agreed.**

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
- Position Identifier is the logical primary key; Position Ticket is a mutable execution handle and may be refreshed without changing Position Identifier.
- Snapshot is a **Current State Store, not Trade History**. It stores current Grid configuration/Anchor, all current Grid Level States, active Position Mappings, unresolved Requests and Last applied Journal Sequence, with schema/identity/integrity metadata.
- After confirmed zero-volume Position Reconciliation, prune that Position Mapping but retain its Grid Level Index/State (e.g. WAIT_RETURN).
- Keep Levels with no Position while they remain part of the current Grid configuration.
- Prune old Level States after Mode/Step Reset only when reset is confirmed, no old Positions remain, and no unresolved Request references the old configuration.
- Being outside Bounds alone is not a reason to prune a Level.
- Do not retain closed Trade/Deal history in Snapshot unless still required for Reconciliation/Recovery.
- Journal threshold is 16 MiB per active segment; Snapshot + Rotation is required for long-running operation. Snapshot must have its own size/count validation.
- Rotation must preserve sequence continuity and must not delete old journal generation until new Snapshot and journal generation are flushed, read back and validated. Crash matrix/commit mechanism will be designed before implementation.

## Completed and user-verified
- `Include/BotTrade/Grid/GridEntryMappingStorage.mqh`: per Account/Server/Symbol/Instance journal in terminal MQL5/Files, schema version, sequence, checksum, UTF-8 hex payload, strict replay, incomplete final tail recovery via flushed temporary file replacement, checked write/flush result.
- `Experts/TGK/Tests/Grids/test_grid_entry_mapping_storage.mq5`: no-trading tests for identity, append/replay, sequence, large decimal identifier strings, instance isolation, comment independence, incomplete tail, malformed complete record.
- User reported 2026-11-12: Storage source compiled, new Unit Test passed, and all 12 Grid Regression Tests passed in MetaEditor/MT5 (13 Test EAs checked).
- Current Storage implementation has a 16 MiB safety cap in `TrimIncompleteTail()` and `ReadJournal()`; exceeding it blocks append/replay. Snapshot/Rotation is not implemented yet.

## Implemented in source; pending user Compile/Run verification
- `Include/BotTrade/Grid/GridEntryMappingReducer.mqh`: Pure Typed Payload v1 Current-State Reducer. No CTrade/OrderSend dependency and no Order Comment parsing.
- `Experts/TGK/Tests/Grids/test_grid_entry_mapping_reducer.mq5`: fixture-only Unit Test EA; no Trade Request.
- Typed event payloads cover Entry Intent, Execution Result, Deal Association, Position Mapping, Level State, Position Volume, Position Ticket refresh, Position Closed and Reset Committed.
- Reducer validates exact payload version/field count, Instance ID + Symbol + Magic, configuration epoch, target uniqueness, one unresolved request, accepted-vs-failed execution outcomes, multiple Deal Tickets sharing one Position Identifier, decimal-string identifiers, reconciled Position Mapping, partial/full close, Position Ticket refresh, reset retention and continuous Journal Sequence.
- Partial close updates remaining volume and keeps Position Mapping/Level ACTIVE. Confirmed full close removes Position/Deal/Request mapping data but retains Level State. Completed Mode/Step Reset prunes old Level State only with no active Positions or unresolved Requests.
- Static checks completed: whitespace/final newline, delimiter balance, no Trade API calls in the two new files. Assistant has NOT compiled or run MetaEditor/MT5.
- The new Reducer EA is pending user Compile/Run; rerun the 12 Grid Regression Tests after this source change. The prior 12/12 result is baseline only, not post-Reducer verification.

## Next implementation sequence
1. User compiles/runs `test_grid_entry_mapping_reducer.mq5` plus all 12 Grid Regression Tests in MetaEditor/MT5 and reports results.
2. Fix any compile/runtime issues found; do not proceed until the Reducer test and regression pass.
3. Snapshot serialization + Journal Rotation design, generation/commit protocol and Crash Recovery Matrix.
4. Snapshot + Rotation implementation and failure/crash injection tests.
5. Entry Execution Policy + tests.
6. CTrade Adapter + no-live-trade seam tests.
7. Coordinator integration, docs and regression; user performs MetaEditor/MT5 compile/run.
8. Demo Integration remains separate and requires explicit user approval.

Before any further source changes, run relevant Grid Regression Tests (currently 12 files). Do not send real or Demo trade requests unless the user explicitly authorizes the Demo test.
