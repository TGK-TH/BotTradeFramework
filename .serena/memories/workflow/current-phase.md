# Current TGK BotTradeFramework / Grid V1 Phase

อัปเดต: 2026-11-21

## Repository and authority
- Repository: `/Users/tachagon/Documents/13_Trade/1_Bot/BotTradeFramework`
- Branch: `feature/grid-trading`
- Source of Truth: Repository source/tests/docs.
- Grid master roadmap and Definition of Done: `Docs/EAs/Grid/ROADMAP.md`
- Current status: `PROJECT_STATUS.md`
- Grid technical docs: `Docs/EAs/Grid/`

## Current Work Item
WP-04 Grid Entry Pipeline Integration was completed after the user reported all tests compiled and ran successfully on 2026-11-20, including latest P08/P11 additions. No real Trade Request was sent by its Fake Port tests. Accepted/uncertain requests remain unresolved until reconciliation; Pipeline does not create Position Mapping or set ACTIVE from CTrade result. WP-04 is complete; P09 partial-fill mapping remains a WP-05 reconciliation dependency and P10 duplicate blocking is covered by P01.

WP-05A — Persistence Foundation is now active:
- WP-05A approved architecture: `CTGKGridPersistence` owns Instance/Lifecycle/Configuration persistence; `CTGKGridEntryMappingReducer` + `CTGKGridEntryMappingSnapshotStorage` own canonical Trading State (Entry Request/Deal associations, Position Mappings, Normal Level States, Anchor State).
- Schema remains V1; revised V1 requires Anchor State; old incomplete V1 is unsupported; no migration/backward compatibility. Missing/invalid Anchor State must fail closed / Recovery Required.
- WP-05A.1 — Anchor State Model implementation is complete. User reported MetaEditor Compile and all Tests PASS on 2026-11-21 after fixing the A06 Test Harness issue. CTO formal Code Review is **APPROVED**, no code fixes requested.
- WP-05A.1 Trello: https://trello.com/c/K2y13ndo/12-wp-05a1-anchor-state-model — moved to Code Review; awaiting user confirmation before Done.
- WP-05A.1 files: `Include/BotTrade/Grid/GridEntryMappingReducer.mqh`, `Experts/TGK/Tests/Grids/test_grid_entry_mapping_reducer.mq5`, and `Docs/EAs/Grid/WorkPackages/WP-05A/Phase-1.1/IMPLEMENTATION_REPORT.md`.
- SPEC: `Docs/EAs/Grid/WorkPackages/WP-05A/Phase-1.1/SPEC.md`; TEST_PLAN: same directory; CTO Review: `CODE_REVIEW.md`.
- Implementation adds typed in-memory Anchor State, default READY with configured-state gate, successful RESET_COMMITTED initialization, enum validation, and read-only TryGetAnchorState. Normal Level behavior preserved. No Journal/Snapshot serialization, Anchor close transitions, runtime restore, reconciliation, production event integration, or trade execution changes.
- Known planned boundary: Anchor State is not durable across restart in this Card; WP-05A.2 handles Anchor Mapping/close transitions; later WP-05A Cards handle Journal/Snapshot persistence.
- WP-05A.2 — Anchor State Transitions remains Product Backlog planning placeholder; no detailed SPEC/TEST_PLAN approval or implementation authorization yet. Stop and ask user before proceeding.
- WP-05B through WP-09 remain not started.
- Working tree: Freebuff's implementation/test/report files are staged; CTO review and documentation updates are unstaged/untracked. No commit/push has been made.

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
- Formal review starts only after user reports Compile/Test PASS. Review outcomes and fixes are recorded in Card-linked CODE_REVIEW.md. After APPROVED, update docs/status and wait for user confirmation before Done.
- Developer handoff uses separate SPEC.md and TEST_PLAN.md, plus IMPLEMENTATION_REPORT.md and CODE_REVIEW.md. Do not rely on chat history as Freebuff task handoff.
- Before new Grid feature/refactor, remind user to run latest relevant Grid Regression Tests and record pre-change baseline.
- Unit tests never send Trade Requests. Demo tests require separate explicit user approval and designated test positions. Never send Live orders.
- Preserve staged/unstaged/untracked changes. No destructive Git operations. No commit/push unless explicitly requested.
- Stop at every WP/Phase boundary and obtain explicit user authorization before starting the next one.
- After each WP/Phase, update PROJECT_STATUS.md, relevant Thai docs, test inventory where applicable, Serena current-phase memory, and Trello. Run Documentation Consistency Gate, validate local Markdown links, and run git diff --check.
