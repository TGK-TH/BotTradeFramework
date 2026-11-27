# Current TGK BotTradeFramework / Grid V1 Phase

Updated: 2026-11-27 — WP-05A/B/C complete; roadmap reprioritized to MT5 Strategy Tester first.

## Repository checkpoint
- Repository: /Users/tachagon/Documents/13_Trade/1_Bot/BotTradeFramework
- Branch: feature/grid-trading
- Latest inspected HEAD: 642aec2 (WP-05C -- Complete).
- Latest inspected `git status --short --branch`: clean; branch aligned with origin/feature/grid-trading at that checkpoint.
- No source files changed during the current roadmap/Trello update.

## Roles / workflow
- User = Product Owner / QA; ChatGPT = CTO / Technical Lead; user chooses Codex or Freebuff for implementation.
- Planning may proceed in parallel; implementation, user verification, and formal CTO review remain sequential, one card at a time.
- No source implementation until final SPEC/TEST_PLAN, explicit Product Owner implementation authorization, and fresh pre-change no-trade Grid Regression baseline PASS.
- User runs MetaEditor/MT5 tests. No commit/push unless explicitly authorized. Preserve staged/unstaged/untracked work; no destructive Git operations. Unit tests must not send Trade Requests.

## Latest Product Roadmap Decision (2026-11-27)
User explicitly prioritized making Grid V1 operational on MT5 Strategy Tester before Demo.
1. GRID V1 — Strategy Tester Readiness.
2. GRID V1 — Strategy Tester Validation and reproducible trading data collection.
3. ARCH — Support Multiple Positions per Grid Level / Entry Request, after Tester validation and before broker Demo.
4. Demo Readiness & Demo Validation.
- Current one Entry Request : one Position Identifier contract may be used only within a verified safe Tester configuration. Do not assume Strategy Tester always yields one Position per request; inspect actual Tester execution semantics and fail closed on conflicting evidence.
- WP-05D OnTradeTransaction/production event integration is not assumed to be necessary or unnecessary for Tester. Prove exact event lifecycle requirements from code paths and Tester behavior; only minimum necessary scope can be proposed.
- CR-07 is deferred because its current acceptance criteria assume multiple Position Identifiers per Request and conflict with the current Reducer contract. Reassess after Multi-Position Architecture.
- No Demo/Live trade testing is authorized by this roadmap decision.

## Trello state
Board: TGK Grid Bot (https://trello.com/b/cYLUMIui/tgk-grid-bot)
- GRID V1 — Strategy Tester Readiness: In Progress, CTO Planning / Contract Design only; implementation NOT authorized. https://trello.com/c/VlBVaRt2/17-grid-v1-strategy-tester-readiness
- GRID V1 — Strategy Tester Validation: Product Backlog. https://trello.com/c/4bJ5F1DE/18-grid-v1-strategy-tester-validation
- ARCH — Support Multiple Positions per Grid Level / Entry Request: Product Backlog; sequence updated to after Tester validation and before Demo. https://trello.com/c/Q9l3YpRF/16-arch-support-multiple-positions-per-grid-level-entry-request
- CR-07: Product Backlog / deferred; acceptance criteria to be reassessed after architecture decision. https://trello.com/c/RBpHlOmK/15-cr-07-aggregate-unmapped-position-volume-for-unresolved-entry-evidence
- WP-05D Production Event Integration: Product Backlog / deferred for later Demo readiness; minimum Tester event integration to be established by evidence.
- WP-05 parent: Done list as reconciliation foundation WP-05A/B/C is complete; WP-05D is separately tracked as a deferred placeholder.
- WP-05A, WP-05B, WP-05C child packages are complete; WP-05B closed 2026-11-26, WP-05C closed 2026-11-27 after user-reported Compile/Test PASS and CTO review APPROVED.

## Source inspection findings for Strategy Tester Readiness
- Repository source is technical authority; `AGENTS.md`, `PROJECT_STATUS.md`, Grid Roadmap, README, Architecture, and Testing guide were read.
- `Experts/TGK` currently contains other EAs and Grid test EAs, but no production Grid V1 EA shell/source file.
- Search of `Experts/**/*.mq5` found OnInit/OnTick handlers in test EAs and unrelated EAs; no OnTradeTransaction handler was found.
- Grid Architecture document explicitly states there is not yet a Production EA Event Handler or End-to-End Grid V1.
- Existing components include Grid Identity, Lifecycle, Runtime Orchestrator, State Machine, Position Reconciler, Order Execution Adapter, Level Engine/Coordinator, Entry Execution Policy/Resolver/Adapter/Pipeline, Persistence, Runtime Restoration, and Open Positions Reconciliation.
- Therefore Strategy Tester Readiness must first define and implement the minimum production EA lifecycle/integration path, but exact boundaries/dependencies (including whether OnTradeTransaction is needed) require further design/source inspection.
- Existing `PROJECT_STATUS.md` and `Docs/EAs/Grid/ROADMAP.md` still contain stale pre-WP-05C status/roadmap statements; update them during the formal planning/specification work and run the Documentation Consistency Gate before closing the planning phase.

## Exact next step
Continue CTO source/architecture audit for Strategy Tester Readiness, trace the minimum EA event loop and dependency order, then prepare a bounded implementation breakdown with SPEC and TEST_PLAN. Do not edit source or start implementation until Product Owner explicitly authorizes the finalized implementation card.