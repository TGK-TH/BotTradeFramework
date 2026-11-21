# Current TGK BotTradeFramework / Grid V1 Phase

อัปเดต: 2026-11-21

## Repository and authority
- Repository: `/Users/tachagon/Documents/13_Trade/1_Bot/BotTradeFramework`
- Branch: `feature/grid-trading`
- HEAD observed after WP-05A.1 closure: `4aa36961f4ae0948afa99ab70203ccac07f68bdb` — documentation/status completion commit, author shown by Git as Tatchagon Koonkoei, 2026-11-21 15:58 +07. ChatGPT did not run a commit or push command.
- Source of Truth: Repository source/tests/docs.
- Grid master roadmap and Definition of Done: `Docs/EAs/Grid/ROADMAP.md`
- Current status: `PROJECT_STATUS.md`

## Current Work Item
WP-05A — Persistence Foundation remains In Progress. WP-05A.1 — Anchor State Model is **Done**:
- User reported MetaEditor Compile and all Tests PASS on 2026-11-21 after correcting A06.
- CTO formal Code Review: **APPROVED**, no code fixes requested.
- User explicitly confirmed closure on 2026-11-21.
- Trello WP-05A.1: https://trello.com/c/K2y13ndo/12-wp-05a1-anchor-state-model — in Done and marked complete.
- SPEC: `Docs/EAs/Grid/WorkPackages/WP-05A/Phase-1.1/SPEC.md`; TEST_PLAN: same directory; Implementation Report: `IMPLEMENTATION_REPORT.md`; CTO Review: `CODE_REVIEW.md`.
- Source: `Include/BotTrade/Grid/GridEntryMappingReducer.mqh`; tests: `Experts/TGK/Tests/Grids/test_grid_entry_mapping_reducer.mq5`.
- Implemented typed in-memory Anchor State, default READY with configured-state gate, successful RESET_COMMITTED initialization, enum validation, and read-only TryGetAnchorState. Normal Level behavior preserved.
- Not implemented in WP-05A.1: Journal/Snapshot serialization, Anchor close transitions, runtime restore, reconciliation, production event integration, or trade execution.
- WP-05A.2 — Anchor State Transitions remains Product Backlog planning placeholder. No detailed SPEC/TEST_PLAN approval and no implementation authorization. Stop and ask user before proceeding.
- WP-05A parent remains In Progress; Journal/Snapshot persistence and remaining Cards are still open.
- Latest observed working tree after closure: documentation and Serena current-phase memory have uncommitted modifications; Git status showed no staged changes. The HEAD commit exists as noted above. Do not infer any push occurred.

## WP-05A approved architecture / contract
- CTGKGridPersistence owns Instance/Lifecycle/Configuration persistence.
- CTGKGridEntryMappingReducer + CTGKGridEntryMappingSnapshotStorage own canonical Trading State (Entry Requests/Deal associations, Position Mappings, Normal Level States, Anchor State).
- Anchor State and Position Mapping changes from one close event must be one durable logical transition.
- Schema remains V1; revised V1 requires Anchor State; old incomplete V1 unsupported; no migration/backward compatibility.
- Missing/invalid required Anchor State or persistence/recovery inconsistency => Fail Closed / Recovery Required.
- Engine transition semantics remain authoritative; persistence must not invent transitions.
- WP-05A plan: Reducer model/transitions; Journal replay; Snapshot/checkpoint/rotation/recovery; end-to-end hardening/tests/docs. Each implementation Card needs separate SPEC/TEST_PLAN and user approval.

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
- Workflow V2: ChatGPT = CTO/Technical Lead (design, specifications, formal review, documentation; does not implement source code); Freebuff = Developer Agent (implements within approved Card/spec, works directly from repository and must not use Serena MCP); user = Product Owner/QA and runs MetaEditor/MT5 compile/tests.
- Formal review starts only after user reports Compile/Test PASS. Review outcomes and fixes are recorded in CODE_REVIEW.md. After APPROVED, update docs/status and wait for user confirmation before Done.
- Developer handoff uses separate SPEC.md and TEST_PLAN.md, plus IMPLEMENTATION_REPORT.md and CODE_REVIEW.md. Do not rely on chat history as Freebuff task handoff.
- Before new Grid feature/refactor, remind user to run latest relevant Grid Regression Tests and record pre-change baseline.
- Unit tests never send Trade Requests. Demo tests require separate explicit user approval and designated test positions. Never send Live orders.
- Preserve staged/unstaged/untracked changes. No destructive Git operations. No commit/push unless explicitly requested.
- Stop at every WP/Phase boundary and obtain explicit user authorization before starting the next one.
- After each WP/Phase, update PROJECT_STATUS.md, relevant Thai docs, test inventory where applicable, Serena current-phase memory, and Trello. Run Documentation Consistency Gate, validate local Markdown links, and run git diff --check.
