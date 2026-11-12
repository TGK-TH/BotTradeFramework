# Current TGK BotTradeFramework Phase

As of 2026-11-12, Grid Level Runtime Coordinator — Round 1 remains completed and user-verified (12/12 PASS). The Persistent Journal foundation slice in Grid Entry Execution Adapter — Round 1 is now implemented and user-verified: the user reported `GridEntryMappingStorage.mqh` compiled, its new Unit Test passed, and all 12 existing Grid Regression Tests passed in MetaEditor/MT5. Assistant did not independently run MetaEditor/MT5.

## Current phase: Grid Entry Execution Adapter — Round 1
Status: **Implementation in progress; Persistent Journal foundation complete and user-verified.** Design contract: `Docs/EAs/Grid/Phases/phase-grid-entry-execution-adapter-round-1.md`.

User decisions:
- Persistent Mapping is the only source of truth for Entry Request / Order / Deal / Position / Logical Level relationships.
- Order Comment is for human visibility in MT5 UI only. Never parse it or use it for mapping, restore, fill confirmation, or state transitions.
- Keep existing `CTGKGridPersistence` / Terminal Global Variables for Grid Snapshot and Level State.
- Add a separate append-only per-Instance journal file under terminal `MQL5/Files`; do not use `FILE_COMMON` in Round 1.
- Store Order Ticket, Deal Ticket and Position Identifier as decimal Strings, never as double.
- Persist and flush Entry Intent before sending any trade request. Persistence failure blocks execution.
- Accepted/Placed is not a fill; only validated Position reconciliation may confirm the mapping and make a level ACTIVE.
- One unresolved Entry Request per Instance; no approximate Fill Price inference.
- Human-readable comments can show BUY/SELL and Anchor/Level labels; comment may be absent, truncated or changed without affecting system logic.

## Completed and user-verified in the current phase
- Added `Include/BotTrade/Grid/GridEntryMappingStorage.mqh`: per Account/Server/Symbol/Instance journal in MQL5/Files, schema version, sequence, checksum, UTF-8 hex payload, strict replay, incomplete final tail recovery via flushed temporary file replacement, and checked write/flush result.
- Added `Experts/TGK/Tests/Grids/test_grid_entry_mapping_storage.mq5`: no-trading tests for identity, append/replay, sequence, large decimal identifier strings, instance isolation, comment opacity, incomplete tail, and malformed complete record.
- User reported on 2026-11-12: source compiled, the new Unit Test passed, and all 12 Grid Regression Tests passed in MetaEditor/MT5 (13 Test EAs checked in total).
- Documentation updated to record the user-reported result. Assistant did not independently run MetaEditor/MT5.

## Remaining work in Round 1
1. Implement typed mapping payload/state validation and reducer, including conflicting Request/Deal/Position/Logical Target detection and failure-injection tests.
2. Implement Entry Execution Policy + tests.
3. Implement CTrade Adapter + no-live-trade seam tests; Intent must persist/flush before Trade API.
4. Integrate Adapter with Coordinator mapping/reconciliation contract.
5. Update docs/status and rerun regression; request user Compile/Run confirmation.
6. Demo Integration is separate and requires explicit user approval. Do not start production EA event-handler integration in this phase.

The generic journal foundation alone does not yet implement full Persistent Mapping semantics, Entry Policy, or trade execution. The next implementation slice should be the typed mapping payload/state reducer and its unit tests; do not start the Entry Policy or CTrade Adapter until that slice is complete and verified.