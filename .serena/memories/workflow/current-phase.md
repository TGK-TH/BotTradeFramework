# Current TGK BotTradeFramework / Grid V1 Phase

อัปเดต: 2026-11-19

## Repository and authority
- Repository: `/Users/tachagon/Documents/13_Trade/1_Bot/BotTradeFramework`
- Branch: `feature/grid-trading`
- Historical HEAD during the 2026-11-19 WP-03 status/docs update: `8034217`.
- Documentation Consistency Gate work started from HEAD `b3bb2d7` on `feature/grid-trading`; working tree was clean before these workflow edits.
- Source of Truth: Repository source/tests/docs.
- Grid master roadmap and Definition of Done: `Docs/EAs/Grid/ROADMAP.md`
- Current status: `PROJECT_STATUS.md`
- Grid technical docs: `Docs/EAs/Grid/`

## Current Work Item
WP-03 Entry CTrade Adapter is complete; user reported all Compile/Run tests passed on 2026-11-19. Stop at the WP boundary; WP-04 requires explicit user authorization.
- WP-01 Entry Execution Policy: complete; user-reported Policy 44/44 and Grid Regression 15/15 Compile/Runtime PASS on 2026-11-17.
- WP-02 Target-Level Resolver / Caller Integration: complete based on user-reported Compile/Run PASS on 2026-11-18 after correcting Reducer out-of-range test index from 2 to 200. Includes 17 Resolver/Caller test IDs plus direct Reducer/Coordinator context API coverage.
- WP-03 added `Include/BotTrade/Grid/GridEntryExecutionAdapter.mqh` and 13 Fake Port tests in `Experts/TGK/Tests/Grids/test_grid_entry_execution.mq5`. Static Review and `git diff --check` passed; user reported all Compile/Run tests passed on 2026-11-19. Production Port uses Snapshot Storage; sequence mismatch between storage and Reducer fails closed. No real Trade Request is sent by the WP-03 unit tests.
- WP-03 accepted outcomes `DONE`, `DONE_PARTIAL`, `PLACED` remain unresolved until Position/Deal reconciliation; Adapter does not create Position Mapping or set Level ACTIVE itself.
- Trello WP-03 card: https://trello.com/c/Jvj4Aawo/5-wp-03-grid-entry-ctrade-adapter (Done per project status).
- WP-04 Entry Pipeline Integration: NOT STARTED; requires explicit user authorization.
- WP-05 through WP-09: NOT STARTED.

## Documentation update 2026-11-19
- Corrected stale `PROJECT_STATUS.md` implementation snapshot: Entry CTrade Adapter exists; Entry Pipeline Integration, Production EA Event Handler, and End-to-End Grid V1 remain incomplete.
- Updated `Docs/EAs/Grid/architecture.md` scope/date to include Entry Policy, Resolver/Caller, and Entry CTrade Adapter while clearly stating pipeline/EA event integration remains incomplete.
- Updated `Docs/EAs/Grid/Testing/testing.md` WP-03 evidence from pending MT5 validation to user-reported Compile/Run PASS on 2026-11-19; Demo Entry Integration remains separately gated.
- Corrected the historical WP-02 phase note so it states WP-03 was not started at the time WP-02 closed, and points to the current WP-03 completion record.
- `Docs/EAs/Grid/ROADMAP.md` and `README.md` already reflected WP-03 complete / WP-04 awaiting approval and were not changed.
- Grid test inventory verified from directory: 19 `.mq5` sources (15 component/regression + Policy + Resolver/Caller + Entry Adapter + separate Demo Integration).
- Validation after docs changes: `git diff --check` passed; local Markdown link scan found 0 missing targets. No MQL5 source changed and no MT5 tests were run as part of this documentation-only update.

## Next Work
Await explicit user authorization before starting WP-04 Entry Pipeline Integration. Once approved, do Dependency Review, contract/design and Test Plan first; do not jump straight to implementation.
Demo Entry Integration sends Trade Requests and remains excluded unless separately approved.

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
- User cancelled DeepSeek Agent workflow; use original ChatGPT + Serena MCP workflow.
- Before each new Grid feature/refactor, remind user to run latest Grid Regression Tests and record pre-change baseline; run relevant tests again after source changes.
- User runs MetaEditor/MT5 compile/runtime and reports results. Never claim those results independently.
- Unit tests never send Trade Requests. Demo tests require explicit separate user approval and Safety Gate. Never send live orders.
- After each WP, update PROJECT_STATUS.md, relevant Thai technical docs, Testing inventory, Serena current-phase memory, and Trello card as applicable.
- Preserve staged/unstaged/untracked changes. No reset/checkout/clean/stash or overwrite unrelated work. No commit/push unless asked.
- Stop at every WP/Phase boundary and ask for explicit user authorization before starting the next one.

## Documentation Consistency Gate — added 2026-11-19
- Mandatory before closing any WP/Phase or documentation-maintenance task; details: `Docs/Development/documentation-consistency-gate.md`.
- Gate compares current status across status/docs/source/tests/Serena memories, checks positive and negative stale claims, evidence levels, actual test inventory, historical-context labeling, and exact authorization boundary.
- Final checks: inspect full diff, `git diff --check`, local Markdown links, actual test inventory when affected, and final working-tree state.
- Do not report the gate passed or close work while contradictions remain unresolved.
