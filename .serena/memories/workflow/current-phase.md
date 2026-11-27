# Current TGK BotTradeFramework / Grid V1 Phase

Updated: 2026-11-27 — WP-05A/B/C complete; WP-06 Strategy Tester Readiness decomposition created.

## Repository checkpoint
- Repository: /Users/tachagon/Documents/13_Trade/1_Bot/BotTradeFramework
- Branch: feature/grid-trading
- HEAD: ca560ac, branch ahead of origin by 1 commit.
- Latest working tree contains documentation modifications and new untracked `Docs/EAs/Grid/WorkPackages/WP-06/` documents; no source implementation files changed.
- `git diff --check` passed; 13 WP-06 Markdown documents' relative links validated before final TP update (new edits do not change link paths).
- No commit/push.

## Roles / workflow
- User = Product Owner / QA; ChatGPT = CTO / Technical Lead; user chooses Codex or Freebuff.
- Planning may cover multiple related cards concurrently; implementation, user verification and CTO formal review remain sequential, one card at a time.
- No source implementation until final SPEC/TEST_PLAN, explicit Product Owner implementation authorization, and fresh pre-change no-trade Grid Regression baseline PASS.
- User runs MetaEditor/MT5 tests. No commit/push unless explicitly authorized. Preserve staged/unstaged/untracked work; no destructive Git operations. Unit tests must not send Trade Requests.

## Latest Product Roadmap Decision (2026-11-27)
User explicitly prioritized making Grid V1 operational on MT5 Strategy Tester before Demo.
1. Grid V1 Strategy Tester Readiness.
2. Strategy Tester Validation and reproducible trading data collection.
3. Multi-Position Architecture (one Entry Request / Grid Level -> multiple Position Identifiers) after Tester validation and before broker Demo.
4. Demo Readiness & Demo Validation.
- Current one Entry Request : one Position Identifier contract may be used only within a specifically verified safe Tester configuration. Do not assume Strategy Tester always yields one Position per request; inspect actual Tester execution semantics and fail closed on conflicting evidence.
- WP-05D full Production Event Integration is deferred for Demo readiness. Only minimum evidence-backed event/deal correlation needed for Strategy Tester may be included in WP-06.
- CR-07 is deferred until after Strategy Tester validation and Multi-Position Architecture review. It is not a current Tester gate unless concrete evidence shows a safety defect under supported Tester contract.
- No Demo/Live execution is authorized.

## WP-06 Design & Planning created (2026-11-27)
Parent Trello card:
- GRID V1 — Strategy Tester Readiness, In Progress, CTO Planning/Contract Design only; implementation NOT authorized.
- https://trello.com/c/VlBVaRt2/17-grid-v1-strategy-tester-readiness

Child cards (all In Progress, planning only):
- WP-06A Production EA Bootstrap & Recovery Gate: https://trello.com/c/3mG6BCRO/19-wp-06a-production-ea-bootstrap-recovery-gate
- WP-06B Trade Event Intake & Entry Deal Correlation: https://trello.com/c/5xtxDsXT/20-wp-06b-trade-event-intake-entry-deal-correlation
- WP-06C Initial Anchor & Grid Entry Runtime: https://trello.com/c/MmnD8CYg/21-wp-06c-initial-anchor-grid-entry-runtime
- WP-06D Position Management, TP & Configuration Reset: https://trello.com/c/najXLNdE/22-wp-06d-position-management-tp-configuration-reset
- WP-06E Strategy Tester End-to-End Readiness: https://trello.com/c/hgid1fJi/23-wp-06e-strategy-tester-end-to-end-readiness

Repository documents created:
- `Docs/EAs/Grid/WorkPackages/WP-06/README.md`
- `Docs/EAs/Grid/WorkPackages/WP-06/ARCHITECTURE.md`
- `Docs/EAs/Grid/WorkPackages/WP-06/WP-06_DECISIONS.md`
- Separate SPEC.md and TEST_PLAN.md for WP-06A, WP-06B, WP-06C, WP-06D, WP-06E.
- Updated `PROJECT_STATUS.md`, Grid `README.md`, `ROADMAP.md`, and `architecture.md`.
- Child cards have Architecture/Integration/Unit Test/Feature/Research labels as appropriate.
- No source code changed.

## Key technical findings / design constraints
- No production Grid V1 EA shell/event loop exists under `Experts/TGK`.
- No `OnTradeTransaction` handler or production deal-history correlation bridge was found in current EA sources.
- WP-05C acquires complete/stable Open Positions snapshots and performs reconciliation, but it consumes durable Deal Association evidence; it does not discover Entry Deals or create Deal Association records.
- `CTGKGridLevelRuntimeCoordinator::UpdatePrice()` selects candidates; `Reconcile()` accepts Position/Close facts and updates candidate state; `CTGKGridEntryExecutionPipeline` connects Candidate → Resolver/Policy/Adapter.
- Initial Anchor bootstrap is distinct: actual fill establishes Anchor, then geometry and canonical config need durable atomic bootstrap.
- `CTGKGridOrderExecutionAdapter` is current reset/close adapter, not a general TP manager.
- Current canonical WP-05A.2 close transition is reason-free; do not reintroduce TP/Non-TP/SL/manual classification.
- Legacy Lifecycle Persistence and canonical Mapping Reducer Snapshot persist overlapping configuration-related state; authoritative configuration and Config Epoch contract must be resolved before production integration.
- Strategy Tester must verify whether one Entry Request -> one Position Identifier holds under the exact Hedging execution configuration.

## Resolved TP Contract (previous Product Owner decision recovered)
- TP is per Position, not Basket TP.
- BUY TP = actual Entry Fill Price + 1 × GridStep.
- SELL TP = actual Entry Fill Price − 1 × GridStep.
- TP is broker-side / Position-level, applies to Anchor and normal Positions.
- After TP, re-entry waits until price retouches/crosses original Entry Level.
- Existing Positions retain their already-set TP when GridStep input changes; new Positions use the new Step. Approved GridStep reset still closes old Positions before rebuilding.
- WP-05A.2 Full Close remains reason-free. WP-06D must verify the Level/quote state transition preserves retouch-before-reentry without close-reason inference.
- D-06-01 is resolved and recorded in `WP-06_DECISIONS.md`; WP-06D is no longer blocked waiting for Product Owner TP confirmation.

## Open decisions
1. D-06-02 CTO must verify Tester OnTradeTransaction/History event semantics and choose deterministic event intake/fallback.
2. D-06-03 define atomic initial Anchor + Position Mapping bootstrap from actual fill evidence.
3. D-06-04 define authoritative config source between Lifecycle and canonical Reducer.
4. D-06-05 verify exact Tester execution contract; multi-Identifier evidence stops the flow and triggers architecture review.
5. D-06-06 define realistic restart/recovery coverage in Strategy Tester.

## Exact next step
Continue CTO design review: resolve event/deal correlation and initial Anchor/config authority contracts, check draft WPs against full source and tests, then finalize implementation-ready SPEC/TEST_PLAN for WP-06A and its dependencies. No source coding authorized yet.