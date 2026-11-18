# Current TGK BotTradeFramework / Grid V1 Phase

อัปเดต: 2026-11-18

## Repository and authority
- Repository: `/Users/tachagon/Documents/13_Trade/1_Bot/BotTradeFramework`
- Source of Truth: Repository source/tests/docs.
- Grid master roadmap and Definition of Done: `Docs/EAs/Grid/ROADMAP.md`
- Current status: `PROJECT_STATUS.md`
- Grid technical docs: `Docs/EAs/Grid/`
- Current Trello card: https://trello.com/c/KxLQWjWq/4-wp-02-grid-entry-execution-resolver-caller-integration

## Current Work Item
WP-03 Entry CTrade Adapter is the next planned Work Package; it has NOT STARTED and requires separate explicit user approval before work begins.
- WP-01 Entry Execution Policy: complete; user-reported Policy 44/44 and Grid Regression 15/15 Compile/Runtime PASS on 2026-11-17.
- WP-02 Target-Level Resolver / Caller Integration: complete based on user-reported Compile/Run PASS on 2026-11-18 after correcting the Reducer out-of-range test index from 2 (valid) to 200. This is user-reported evidence, not independently run by Assistant.
- WP-02 includes 17 Resolver/Caller test IDs plus direct Reducer/Coordinator context API coverage; see `Docs/EAs/Grid/Phases/phase-grid-entry-execution-resolver.md`.
- WP-02 changed Reducer/Coordinator read-only context APIs and added Resolver/Caller; no Trade Request or persistent write is part of this Work Package.

## Next Work
- Stop at the WP-02 boundary; get explicit approval before starting WP-03 Entry CTrade Adapter.
- Do not begin WP-03 implementation during a status audit.
- Demo Integration EA remains excluded because it sends Trade Requests.
- Current Grid test source inventory: 18 `.mq5` files under `Experts/TGK/Tests/Grids/`: 15 component/regression tests, 1 Policy Test EA, 1 Resolver/Caller Test EA, and 1 separate Demo Integration test. Recount the directory before relying on this number.

## Existing verified foundations
User-reported MetaEditor/MT5 validation (not independently run by Assistant):
- Grid identity, persistence, state machine, lifecycle, position reconciler, runtime orchestrator and close execution adapter.
- Close adapter Demo Integration Test FINAL PASS on 2026-11-02.
- Two-sided Grid Level Engine Round 1: 11/11 tests PASS on 2026-11-04.
- Grid Level Runtime Coordinator Round 1: new test + 11 regression tests, 12/12 PASS on 2026-11-09.
- Entry Mapping Journal Storage tests and regression PASS on 2026-11-12.
- Typed Mapping Reducer, Snapshot Serialization/Journal Rotation, and current Grid regression tests PASS as reported on 2026-11-15.
- User reported latest Grid Regression tests PASS on 2026-11-17 as precondition for Policy Phase 2.

## Grid V1 non-negotiable design
- MT5 Hedging; one Grid Instance per chart; chart Symbol only; BUY/SELL; system-managed Instance ID and Magic.
- Anchor is actual initial Position Fill Price; two-sided levels derive from Anchor + Grid Step; Bounds are exact hard filters and do not shift levels.
- Initial entry only inside Bounds; outside Bounds block new entries but existing positions/TP continue.
- BUY uses Ask and SELL uses Bid; BUY selects lowest eligible crossed level, SELL highest; at most one candidate per price check.
- TP close waits for return to same Entry Level; partial close keeps ACTIVE until no volume remains.
- Accepted/PLACED is not proof of Fill; explicit Deal/Position reconciliation required before ACTIVE.
- Persistent typed mapping is authoritative; never use Order Comment or approximate Fill Price as Mapping Key; use Position Identifier as logical key.
- Persist/Flush Entry Intent before sending a Trade Request; one unresolved request per Instance; Fail Closed on identity/storage/resolver uncertainty.
- Mode change closes old positions and waits for confirmed zero before new mode/Anchor; Step change closes and rebuilds levels from same Anchor.
- New chart is a new Instance; restoring original chart/profile restores original Instance; never adopt foreign/manual positions.

## Workflow / safety
- Grid is test-first. Before each new feature/refactor, remind user to run latest Grid Regression Tests; run relevant tests again after source changes.
- User runs MetaEditor/MT5 compile/runtime and reports results. Never claim those results independently.
- Unit tests never send Trade Requests. Demo tests require explicit separate user approval and Safety Gate. Never send live orders.
- After each Work Package, update PROJECT_STATUS.md, relevant Thai technical docs, Testing inventory, and this memory. Preserve staged/unstaged work; do not commit/push unless asked.
- Stop at every Phase boundary and ask for explicit user authorization before starting the next Phase, even if a prior kickoff authorized continuing through the Roadmap. Once a Phase is authorized, ensure an appropriately scoped Trello card exists before implementation when needed, and update it at meaningful status transitions and Phase completion to match verified progress.
