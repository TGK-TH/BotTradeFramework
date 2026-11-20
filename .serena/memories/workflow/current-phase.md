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
WP-04 Grid Entry Pipeline Integration is in progress, authorized by the user on 2026-11-20. Baseline: user reported all latest Grid Tests passed before changes; repository was clean on `feature/grid-trading` at HEAD `9d4a4965a182348dea8a2e01e8b9c23d8dc1998d`.
- Contract/Test Plan: `Docs/EAs/Grid/Phases/phase-grid-entry-pipeline-integration.md`.
- Source added: `Include/BotTrade/Grid/GridEntryExecutionPipeline.mqh`; it sends the exact offered candidate through Resolver/Policy/Adapter and updates Runtime Coordinator request state.
- Test added: `Experts/TGK/Tests/Grids/test_grid_entry_execution_pipeline.mq5` now has 9 Fake Port tests (P01–P08, P11). User reported all tests passed on 2026-11-20 before P08/P11 were added; latest additions still need user Compile/Run. No real Trade Request is sent.
- Accepted and uncertain requests remain unresolved until reconciliation. Pipeline does not create Position Mapping or set ACTIVE from CTrade return/retcode. Deal/Position reconciliation is a WP-05 dependency.
- Trello WP-04 card: https://trello.com/c/pk6abEBf/6-wp-04-grid-entry-pipeline-integration (In Progress).
- Next: complete static review and tests in the agreed Test Plan; user compiles/runs the new EA plus relevant Grid Regression before WP-04 can close. No Demo/Live trade request is authorized.
- WP-01 through WP-03 remain complete on user-reported evidence. WP-05 through WP-09 remain not started.

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
