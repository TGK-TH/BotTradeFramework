# Current TGK BotTradeFramework / Grid V1 Phase

อัปเดต: 2026-11-24

## Repository and authority
- Repository: `/Users/tachagon/Documents/13_Trade/1_Bot/BotTradeFramework`
- Branch: `feature/grid-trading`
- Source of Truth: Repository source/tests/docs. Recheck Git status and HEAD before every implementation handoff.
- Grid master roadmap: `Docs/EAs/Grid/ROADMAP.md`; current status: `PROJECT_STATUS.md`.
- ChatGPT = CTO/Technical Lead (design/spec/review/docs; does not implement source code); Freebuff = Developer Agent (works directly in repository; must read `AGENTS.md`, SPEC, TEST_PLAN, IMPLEMENTATION_TASK; no Serena MCP); user = Product Owner/QA and performs MetaEditor/MT5 verification.

## WP-05A status
- WP-05A parent remains In Progress pending its other child work packages.
- WP-05A.1 — Anchor State Model: Done. User reported MetaEditor Compile/Test PASS 2026-11-21; CTO Code Review APPROVED; user confirmed closure; Trello Done.
- WP-05A.2 — Anchor State Transitions: **Done / formally closed 2026-11-24.** CTO reviewed the complete implementation and CR-01/CR-02/CR-03 review fixes and approved. User confirmed the full no-trade Grid Regression suite passed, including CR02-01…04 and CR03-01. Freebuff's report records MetaEditor Compile PASS for `test_grid_entry_execution.mq5` and `test_grid_entry_execution_pipeline.mq5` (0 errors, 0 warnings). Trello card is in Done and marked complete.
- Review record: `Docs/EAs/Grid/WorkPackages/WP-05A/Phase-1.2/CODE_REVIEW.md`; implementation evidence: `Docs/EAs/Grid/WorkPackages/WP-05A/Phase-1.2/IMPLEMENTATION_REPORT.md`.
- CR-01: durable/replayable Anchor `WAIT_ACTIVATION -> READY` transition through `ANCHOR_STATE`, Engine signal, Coordinator durability gate and Adapter API; BUY/SELL direction and mapping invariants preserved.
- CR-02: Adapter validates healthy canonical Reducer context, exact `WAIT_ACTIVATION` state, absence of Anchor Position Mapping and matching pending Coordinator activation before any Journal append. Invalid/conflicting activation has no durable mutation. Fake-port tests cover READY disagreement, mapping disagreement, valid transition, duplicate and append failure.
- CR-03: SELL downward activation tested through Coordinator → Adapter → Journal → Reducer; exactly one `ANCHOR_STATE|READY` record and duplicate rejection.
- Freebuff implementation commit: `f76fec7` (`CR 02 - CR 03 -- Implement by Freebuff`). CTO did not commit or push. At closure, branch was ahead 3 commits; five documentation files had CTO-authored unstaged updates. Do not claim a clean worktree or push state.
- WP-05C and WP-05D remain separate and are NOT authorized by WP-05A.2 closure. Each requires its own scope, SPEC, TEST_PLAN and explicit Product Owner authorization.

## WP-05A.2 approved design
- Full Close detection for Core Grid uses future authoritative Open Positions reconciliation, not Closing Deal History.
- Position Identifier is canonical Position lifecycle identity; Position Ticket is refreshable operational metadata.
- Anchor/Level becomes ACTIVE only after Position Mapping is confirmed.
- Partial Close updates remaining Volume / refreshed Ticket and keeps ACTIVE.
- Full Close is reason-free: no TP/SL/manual classification, closing price or Closing Deal Ticket identity. Position Mapping removal and Anchor/Level state update are one durable Journal transition.
- Operational states: READY, ACTIVE, WAIT_ACTIVATION. WAIT_RETURN is normalized to READY on legacy replay/load; new writes never emit it; preserve WAIT_ACTIVATION ordinal and reserve legacy WAIT_RETURN slot.
- BUY/SELL current executable-side quote determines READY vs WAIT_ACTIVATION.
- State-based durable idempotency; no processed close-event registry.
- Entry Deal Association used by the current entry-fill correlation pipeline remains unchanged.

## Safety / workflow
- Before starting another Grid feature/refactor, remind the user to run the latest relevant no-trade Grid Regression tests and report the pre-change baseline.
- Unit tests never send Trade Requests. Demo tests require separate explicit approval and designated test positions. Never send Live orders.
- Preserve user changes; no reset/checkout/clean/stash/overwrite. No commit/push unless explicitly requested.
- MQL5 style: 2-space indent; multiline params one per line with minimal indent.
- After WP/phase completion, update status, Thai docs, test inventory, Serena memory, Trello; run documentation consistency gate, validate links and `git diff --check`.
