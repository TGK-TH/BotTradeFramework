# Current TGK BotTradeFramework Phase

As of 2026-11-07, Grid Level Runtime Coordinator — Round 1 Contract and Test Design are approved by the user. Implementation has NOT started.

## Current phase: Grid Level Runtime Coordinator — Round 1

Design document: Docs/EAs/Grid/Phases/phase-grid-level-runtime-coordinator-round-1.md.

User-approved contracts:
- One unresolved Entry Request maximum per Grid Instance.
- Retain the best Deferred Candidate while the current request is unresolved: BUY lowest price; SELL highest price.
- Accepted/Placed is not proof of an opened Position. Do not set Level ACTIVE until reconciliation confirms a Position mapped to the same Candidate.
- A missing Position alone does not prove request failure; Execution/Reconciliation must confirm terminal no-position/no-order.
- Position-to-Level Mapping is supplied explicitly by Integration Layer using Anchor flag or Level Index; never infer from approximate Fill Price.
- Partial Close retains ACTIVE while volume remains. Full Close requires resolved TP/Non-TP reason before updating Level state.
- Coordinator is pure coordination logic: no CTrade and no live Account scan.

## Current gate
Before changing source code, user must compile/run and report PASS for all 11 existing Grid Regression Tests. If any fail, stop and diagnose first.

After baseline confirmation:
1. Implement GridLevelRuntimeCoordinator.mqh and its Test EA test-first.
2. Run new test and all relevant regression tests.
3. User performs MetaEditor/MT5 compile/runtime validation.
4. Update Thai Docs, PROJECT_STATUS.md, and this memory based on actual results.

## Previous completed phase
Grid Level Engine — Round 1; user reported all 11 Grid Regression Tests passed on 2026-11-04. See Docs/EAs/Grid/Phases/phase-grid-level-engine-implementation-round-1.md.

## Workflow
- Do not begin later phases without explicit user approval.
- Before new Grid feature/refactor, run relevant regression baseline first.
- User compiles/runs MQL5 in MetaEditor/MT5; do not claim assistant ran it.
- Use 2-space indentation and one parameter per line in multi-parameter test calls.
- If Serena/MCP fails, remind the user to check the MCP Serena server.
