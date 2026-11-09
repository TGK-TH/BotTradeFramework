# Current TGK BotTradeFramework Phase

As of 2026-11-09, Grid Level Runtime Coordinator — Round 1 is completed and user-verified: the user reported 12/12 Grid tests passed in MetaEditor/MT5. Assistant did not independently run MT5.

## Current phase: Grid Entry Execution Adapter — Round 1
Status: **Design agreed; implementation not started.**
Design contract/test plan: `Docs/EAs/Grid/Phases/phase-grid-entry-execution-adapter-round-1.md`.

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

Next step before any source edits: rerun the 12 Grid Regression Tests from the phase document as the implementation baseline. Then implement in test-first order: Mapping journal tests/storage, Entry policy tests, Adapter tests with a no-live-trade seam. Demo Integration is separate and requires explicit user approval. Do not start production EA event-handler integration in this phase.

## Most recently completed phase
Grid Level Runtime Coordinator — Round 1, user-reported 12/12 PASS on 2026-11-09. The Coordinator remains pure: no CTrade or live Account scan.