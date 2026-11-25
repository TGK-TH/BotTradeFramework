# Current TGK BotTradeFramework / Grid V1 Phase

Updated: 2026-11-25 — Product Owner approved Design/Scope for WP-05A.3, WP-05B, WP-05C.

## Repository baseline
- Repository: `/Users/tachagon/Documents/13_Trade/1_Bot/BotTradeFramework`
- Branch: `feature/grid-trading`
- Current HEAD: `ced62b9` (`Enhance implementation report and tests for WP-05A.3; update status, add assertions for invalid Anchor State and orphan Anchor Mapping, and improve test coverage for rejected journal records`), ahead of `origin/feature/grid-trading` by 9 commits.
- WP-05A.3 neutral implementation handoff is prepared in `Docs/EAs/Grid/WorkPackages/WP-05A/Phase-1.3/IMPLEMENTATION_TASK.md`. User reported current tests PASS on 2026-11-25; exact per-file logs were not attached. Explicit implementation authorization remains pending. WP-05B/WP-05C remain blocked by dependency order.
- Current handoff/status documentation changes are local and uncommitted. No commit/push was performed during this update. Preserve them.
- Recheck Git status and HEAD before every implementation handoff.
- Source of Truth: repository source/tests/docs; Grid master roadmap `Docs/EAs/Grid/ROADMAP.md`; current status `PROJECT_STATUS.md`.

## Roles and workflow
- ChatGPT = CTO/Technical Lead (design/spec/review/docs; no source implementation); Codex or Freebuff = Developer Agent selected exclusively by the user for each Card (direct repository access; reads `AGENTS.md`, SPEC, TEST_PLAN and referenced source/docs; no dependence on chat history or Serena memories; Freebuff must not use Serena MCP); user = Product Owner/QA, chooses the Implementer, and performs MetaEditor/MT5 runtime verification.
- Implementer preference: user uses Codex first until monthly quota is exhausted, then uses Freebuff. ChatGPT must not choose or switch Implementers and must prepare neutral handoffs usable by either.
- **Parallel Planning, Sequential Execution**: CTO may design multiple related Cards, prepare multiple SPEC/TEST_PLAN documents, create Cards, and move them to Trello `In Progress` in parallel. Every planning Card must explicitly say `CTO Planning / Contract Design only; implementation not authorized`.
- Implementation by the user-selected Implementer (Codex or Freebuff), User Verification, and formal CTO Code Review remain sequential, one Card at a time.
- Design/Scope approved by Product Owner on 2026-11-25 for WP-05A.3, WP-05B, WP-05C. WP-05A.3 subsequently received explicit implementation authorization; WP-05B and WP-05C remain design-only and unauthorized.
- No implementation until SPEC/TEST_PLAN are final, Product Owner explicitly authorizes that Card, and user reports the required pre-change no-trade Grid Regression baseline. WP-05A.3 has passed these gates; next it requires Product Owner recompile/runtime verification of the CTO follow-up before final approval.
- Before new Grid feature/refactor implementation, remind the user to run latest relevant no-trade Grid Regression Tests and report baseline.
- Unit tests never send Trade Requests. Demo tests require separate explicit approval and designated test positions. Never Live trade. No commit/push unless explicitly requested. Preserve user changes; no destructive Git operations.

## WP-05 status and approvals
- WP-05 parent remains In Progress; WP-05A parent remains In Progress pending WP-05A.3 implementation/verification.
- WP-05A.1 Anchor State Model: Done; user Compile/Test PASS and CTO Review APPROVED 2026-11-21.
- WP-05A.2 Anchor State Transitions: Done / formally closed 2026-11-24; CR-01/CR-02/CR-03 resolved; Freebuff compiled both Adapter consumers with 0 errors/0 warnings; user reported full no-trade Grid Regression PASS; CTO Review APPROVED.
- WP-05A.3 Anchor State Persistence Integration & Hardening: Design/Scope approved and Codex implementation explicitly authorized by Product Owner on 2026-11-25. Codex implementation is in latest commit `eea39b1` plus working-tree changes. CTO review follow-up added A3-08 WAIT_ACTIVATION Entry Intent rejection coverage and corrected Implementation Report; awaiting Product Owner Compile/Runtime verification and final CTO approval. Trello https://trello.com/c/gaSElnBj/14-wp-05a3-anchor-state-persistence-integration-hardening.
- WP-05B Runtime State Restoration: Design/Scope approved 2026-11-25; SPEC/TEST_PLAN final in `Docs/EAs/Grid/WorkPackages/WP-05B/`; Trello https://trello.com/c/86s3rVfy/9-wp-05b-runtime-state-restoration. Runtime ends RESTORED_PENDING_RECONCILIATION with Entry/Candidate gate closed. Implementation NOT AUTHORIZED.
- WP-05C Open Positions Reconciliation: Design/Scope approved 2026-11-25; SPEC/TEST_PLAN final in `Docs/EAs/Grid/WorkPackages/WP-05C/`; Trello https://trello.com/c/c6iAiBw6/10-wp-05c-open-positions-reconciliation. It owns complete/stable Open Positions snapshots, Position Identifier reconciliation, current executable-side quote for reason-free Full Close (BUY=Ask, SELL=Bid), and releasing WP-05B gate only after successful reconciliation. No Closing Deal History or TP/NON_TP. Implementation NOT AUTHORIZED.
- Implementation dependency order: WP-05A.3 → WP-05B → WP-05C. WP-05B restores canonical persisted state into Engine/Coordinator and does not scan live account positions. WP-05C owns complete/stable Open Positions snapshots and reconciliation.
- WP-05D Production Event Integration remains separate and unauthorized.

## WP-05A.2 approved architecture
- Full Close detection uses authoritative Open Positions reconciliation, not Closing Deal History.
- Position Identifier is canonical Position lifecycle identity; Position Ticket is refreshable operational metadata.
- Anchor/Level becomes ACTIVE only after Position Mapping is confirmed.
- Partial Close updates remaining Volume/refreshed Ticket and keeps ACTIVE.
- Full Close is reason-free; no TP/SL/manual classification, close price or Closing Deal Ticket identity. Position Mapping removal and Anchor/Level state update are one durable Journal transition.
- Operational states: READY, ACTIVE, WAIT_ACTIVATION. WAIT_RETURN normalizes to READY on legacy replay/load; new writes never emit it; preserve WAIT_ACTIVATION ordinal and reserve legacy WAIT_RETURN slot.
- BUY/SELL executable-side quote determines READY vs WAIT_ACTIVATION. Full Close post-state rule: BUY uses Ask; SELL uses Bid; equality is wrong-side / WAIT_ACTIVATION.
- State-based durable idempotency; no processed-close-event registry.
- Existing Entry Deal Association used by the entry-fill correlation pipeline remains unchanged and separate from Closing Deal History.

## Safety / evidence
- WP-05A.2 final evidence: user-reported full no-trade Grid Regression PASS on 2026-11-24, including CR02-01…04 and CR03-01; Freebuff compile evidence for both Adapter consumers is 0 errors/0 warnings.
- No Demo/Live Trade Request authorized for WP-05A.3/WP-05B/WP-05C.
- After each WP, update status, Thai docs, Testing inventory as applicable, Serena memory and Trello; run Documentation Consistency Gate, local links, and `git diff --check`. Do not mark WP-05A.3 approved/closed until Product Owner reports PASS on latest test source and CTO completes final review.
