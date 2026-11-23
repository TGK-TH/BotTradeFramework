# Current TGK BotTradeFramework / Grid V1 Phase

อัปเดต: 2026-11-23

## Repository and authority
- Repository: `/Users/tachagon/Documents/13_Trade/1_Bot/BotTradeFramework`
- Branch: `feature/grid-trading`
- Source of Truth: Repository source/tests/docs. Recheck Git status and HEAD before every implementation handoff.
- Grid master roadmap: `Docs/EAs/Grid/ROADMAP.md`; current status: `PROJECT_STATUS.md`.
- ChatGPT = CTO/Technical Lead (design/spec/review/docs; does not implement source code); Freebuff = Developer Agent (works directly in repository; must read `AGENTS.md`, SPEC, TEST_PLAN, IMPLEMENTATION_TASK; no Serena MCP); user = Product Owner/QA and performs MetaEditor/MT5 verification.

## WP-05A status
- WP-05A parent remains In Progress.
- WP-05A.1 — Anchor State Model: Done. User reported MetaEditor Compile/Test PASS 2026-11-21; CTO Code Review APPROVED; user confirmed closure; Trello Done.
- WP-05A.2 — Anchor State Transitions: Product Owner approved SPEC and TEST_PLAN on 2026-11-23. Freebuff handoff prepared. Trello description/comment updated but card intentionally remains Product Backlog until the pre-change baseline is reported.
- Handoff files:
  - `Docs/EAs/Grid/WorkPackages/WP-05A/Phase-1.2/SPEC.md`
  - `Docs/EAs/Grid/WorkPackages/WP-05A/Phase-1.2/TEST_PLAN.md`
  - `Docs/EAs/Grid/WorkPackages/WP-05A/Phase-1.2/IMPLEMENTATION_TASK.md`
- Implementation is NOT yet authorized to start until user reports the latest pre-change no-trade Grid Regression Baseline. The historical 2026-11-20 WP-05A.1 baseline is not valid for WP-05A.2 because source changed afterward. Do not move Trello to In Progress before the new baseline.
- After baseline report, Freebuff may implement only approved WP-05A.2 scope, create `IMPLEMENTATION_REPORT.md`, and stop. User compiles/tests; CTO reviews only after user-reported PASS. No WP-05C work may begin without separate approval.

## WP-05A.2 approved design
- Full Close detection for Core Grid uses future authoritative Open Positions reconciliation, not Closing Deal History.
- Position Identifier is canonical Position lifecycle identity; Position Ticket is refreshable operational metadata.
- Anchor/Level becomes ACTIVE only after Position Mapping is confirmed.
- Partial Close updates remaining Volume / refreshed Ticket and keeps ACTIVE.
- Full Close is reason-free: no TP/SL/manual classification, closing price or Closing Deal Ticket identity. Position Mapping removal and Anchor/Level state update are one durable Journal transition.
- Operational states: READY, ACTIVE, WAIT_ACTIVATION. WAIT_RETURN is normalized to READY on legacy replay/load; new writes never emit it; preserve WAIT_ACTIVATION ordinal and reserve legacy WAIT_RETURN slot.
- BUY/SELL current executable-side quote determines READY vs WAIT_ACTIVATION.
- State-based durable idempotency; no processed close-event registry.
- WP-05A.2 does not implement MT5 account scanning; that belongs to WP-05C. Production event integration belongs to WP-05D.
- Entry Deal Association used by the current entry-fill correlation pipeline remains unchanged.

## Safety / workflow
- No source changes before the user-reported WP-05A.2 pre-change regression baseline.
- Unit tests never send Trade Requests. Demo tests require separate explicit approval and designated test positions. Never send Live orders.
- Preserve user changes; no reset/checkout/clean/stash/overwrite. No commit/push unless explicitly requested.
- MQL5 style: 2-space indent; multiline params one per line with minimal indent.
- After WP/phase completion, update status, Thai docs, test inventory, Serena memory, Trello; run documentation consistency gate, validate links and `git diff --check`.
