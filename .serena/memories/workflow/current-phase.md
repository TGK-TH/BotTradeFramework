# Current TGK BotTradeFramework / Grid V1 Phase

Updated: 2026-11-25

## Repository baseline
- Repository: `/Users/tachagon/Documents/13_Trade/1_Bot/BotTradeFramework`
- Branch: `feature/grid-trading`
- Baseline HEAD: `b092ae3` (`WP-05A.2 -- DONE`), matched origin at the start of this planning session; working tree was clean before CTO planning/docs changes.
- Recheck Git status and HEAD before every implementation handoff.
- Source of Truth: repository source/tests/docs; Grid master roadmap `Docs/EAs/Grid/ROADMAP.md`; current status `PROJECT_STATUS.md`.

## Roles and workflow
- ChatGPT = CTO/Technical Lead (design/spec/review/docs; no source implementation); Freebuff = Developer Agent (direct repository access; reads `AGENTS.md`, SPEC, TEST_PLAN, IMPLEMENTATION_TASK; no Serena MCP); user = Product Owner/QA and performs MetaEditor/MT5 runtime verification.
- **Parallel Planning, Sequential Execution**: CTO may design multiple related Cards, prepare multiple SPEC/TEST_PLAN documents, create Cards, and move them to Trello `In Progress` in parallel. Every planning Card must explicitly say `CTO Planning / Contract Design only; implementation not authorized`.
- Implementation by Freebuff, User Verification, and formal CTO Code Review remain sequential, one Card at a time.
- No implementation until SPEC/TEST_PLAN are final, Product Owner explicitly authorizes that Card, and the user reports the required pre-change no-trade Grid Regression baseline.
- Before new Grid feature/refactor implementation, remind the user to run latest relevant no-trade Grid Regression Tests and report baseline.
- Unit tests never send Trade Requests. Demo tests require separate explicit approval and designated test positions. Never Live trade. No commit/push unless explicitly requested. Preserve user changes; no destructive Git operations.

## WP-05A status
- WP-05A parent remains In Progress pending WP-05A.3.
- WP-05A.1 Anchor State Model: Done; user Compile/Test PASS and CTO Review APPROVED 2026-11-21.
- WP-05A.2 Anchor State Transitions: Done / formally closed 2026-11-24; CR-01/CR-02/CR-03 resolved; Freebuff compiled both Adapter consumers with 0 errors/0 warnings; user reported full no-trade Grid Regression PASS; CTO Review APPROVED.
- WP-05A.3 Anchor State Persistence Integration & Hardening: planning only; Trello https://trello.com/c/gaSElnBj/14-wp-05a3-anchor-state-persistence-integration-hardening; draft SPEC/TEST_PLAN at `Docs/EAs/Grid/WorkPackages/WP-05A/Phase-1.3/`.
- Concrete gap: `test_grid_entry_mapping_snapshot.mq5` covers Snapshot/Journal/rotation/recovery but its typed Reducer fixture validates a mapped Normal Level and default Anchor READY; it does not currently exercise non-default Anchor states through the full storage rotation/restart path. WP-05A.3 proposes to close that test gap.

## Parallel planning cards
- WP-05 parent: CTO Planning / Contract Design, Trello In Progress: https://trello.com/c/IlgR2VGj/7-wp-05-grid-deal-position-reconciliation-integration
- WP-05A parent: In Progress; A.1/A.2 Done; A.3 planning.
- WP-05B Runtime State Restoration: planning only, Trello In Progress: https://trello.com/c/86s3rVfy/9-wp-05b-runtime-state-restoration; draft SPEC/TEST_PLAN at `Docs/EAs/Grid/WorkPackages/WP-05B/`.
- WP-05B restore leaves runtime in RESTORED_PENDING_RECONCILIATION; Entry/Candidate gate remains closed until WP-05C validates live positions.
- WP-05C Open Positions Reconciliation: planning only, Trello In Progress: https://trello.com/c/c6iAiBw6/10-wp-05c-open-positions-reconciliation; draft SPEC/TEST_PLAN at `Docs/EAs/Grid/WorkPackages/WP-05C/`.
- WP-05C must consume complete/stable snapshots synchronously, use Position Identifier as canonical identity, compute Full Close post-state from current executable-side quote, and never use Closing Deal History/TP-NON_TP classification.
- Implementation dependency order: WP-05A.3 → WP-05B → WP-05C. WP-05B restores canonical persisted state into Engine/Coordinator and does not scan live account positions. WP-05C owns complete/stable Open Positions snapshots and reconciliation.

## WP-05A.2 approved architecture
- Full Close detection uses authoritative Open Positions reconciliation, not Closing Deal History.
- Position Identifier is canonical Position lifecycle identity; Position Ticket is refreshable operational metadata.
- Anchor/Level becomes ACTIVE only after Position Mapping is confirmed.
- Partial Close updates remaining Volume/refreshed Ticket and keeps ACTIVE.
- Full Close is reason-free; no TP/SL/manual classification, close price or Closing Deal Ticket identity. Position Mapping removal and Anchor/Level state update are one durable Journal transition.
- Operational states: READY, ACTIVE, WAIT_ACTIVATION. WAIT_RETURN normalizes to READY on legacy replay/load; new writes never emit it; preserve WAIT_ACTIVATION ordinal and reserve legacy WAIT_RETURN slot.
- BUY/SELL current executable-side quote determines READY vs WAIT_ACTIVATION.
- State-based durable idempotency; no processed-close-event registry.
- Existing Entry Deal Association used by the entry-fill correlation pipeline remains unchanged and separate from Closing Deal History.

## Safety / evidence
- WP-05A.2 final evidence: user-reported full no-trade Grid Regression PASS on 2026-11-24, including CR02-01…04 and CR03-01; Freebuff compile evidence for both Adapter consumers is 0 errors/0 warnings.
- No Demo/Live Trade Request authorized for WP-05A.3/WP-05B/WP-05C.
- After each WP, update status, Thai docs, Testing inventory as applicable, Serena memory and Trello; run Documentation Consistency Gate, local links, and `git diff --check`.
