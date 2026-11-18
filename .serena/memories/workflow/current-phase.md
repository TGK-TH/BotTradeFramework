# Current TGK BotTradeFramework / Grid V1 Phase

อัปเดต: 2026-11-17

## Repository and authority
- Repository: `/Users/tachagon/Documents/13_Trade/1_Bot/BotTradeFramework`
- Source of Truth: Repository source/tests/docs.
- Grid master roadmap and Definition of Done: `Docs/EAs/Grid/ROADMAP.md`
- Current status: `PROJECT_STATUS.md`
- Grid technical docs: `Docs/EAs/Grid/`
- Current Trello card: https://trello.com/c/Wt3XbHva/3-grid-entry-execution-policy-pure-decision-component-unit-tests

## Current Work Item
WP-02 Target-Level Resolver / Caller Integration (WP-01 Policy is complete by user-reported PASS):
- Phase 1 Design/Contract/Test Plan: approved.
- Phase 2 Test-First Specification: finalized on 2026-11-17.
- Dedicated Test EA: `Experts/TGK/Tests/Grids/test_grid_entry_execution_policy.mq5`
- 44 unique Test IDs across groups A-F: 4/13/6/9/6/6.
- Final contract includes grouped Candidate/Level Context/Execution Context inputs; single Reason Code; eligible Level States READY and WAIT_RETURN; finite positive Entry Price; Target-Level-only mapping check; Validation Order INVALID_CANDIDATE -> IDENTITY_MISMATCH -> EXECUTION_BLOCKED -> UNRESOLVED_REQUEST -> LEVEL_NOT_FOUND -> LEVEL_NOT_ELIGIBLE -> ALREADY_MAPPED -> ELIGIBLE.
- F02: Level 0 READY/unmapped ALLOW -> Level 7 READY/mapped REJECT ALREADY_MAPPED -> re-evaluate Level 0 ALLOW; same Result object across all three calls.
- Resolver failure is Caller-owned Fail Closed; do not call Policy when Resolve fails.
- Phase 2 Static Acceptance Checks passed 2026-11-17.
- WP-01 created `Include/BotTrade/Grid/GridEntryExecutionPolicy.mqh` strictly against the approved contract. Static review confirms validation precedence, complete result assignment on all paths, and no Trade API/storage/reducer dependency.
- User reported on 2026-11-18 that all test files passed after correcting the Reducer out-of-range query from index 2 (valid) to index 200. This is user-reported Compile/Runtime validation. WP-02 is complete; stop and request explicit approval before starting WP-03.

## Next Work
- WP-02 Resolver/Caller, direct Reducer/Coordinator unit tests, and relevant regression test files passed according to the user's 2026-11-18 report after correcting the Reducer boundary query from index 2 to 200.
- WP-02 is complete and documented in Trello: https://trello.com/c/KxLQWjWq/4-wp-02-grid-entry-execution-resolver-caller-integration
- Stop at the Phase boundary and ask for explicit authorization before starting WP-03 Entry CTrade Adapter, even though the broader Grid V1 kickoff had previously authorized the roadmap.
- The Demo Integration EA remains excluded because it sends Trade Requests.
- Current test source inventory at 2026-11-17: 18 `.mq5` files under `Experts/TGK/Tests/Grids/`: 15 component/regression tests, 1 Policy Test EA, 1 Resolver/Caller Test EA, and 1 separate Demo Integration test. Always inspect directory; do not trust old hard-coded counts.

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
