# Current TGK BotTradeFramework Phase

As of 2026-11-02, Grid Order Execution — Demo Integration Test implementation is in progress and awaiting user MetaEditor compile/review. No Demo orders have been sent.

## Completed immediately before this phase
- User reported all 10 Grid Regression Tests passed on 2026-11-02 before source changes:
  1. test_grid_order_execution.mq5
  2. test_grid_runtime_orchestrator.mq5
  3. test_grid_position_reconciler.mq5
  4. test_grid_lifecycle.mq5
  5. test_grid_state_machine.mq5
  6. test_grid_types.mq5
  7. test_grid_persistence.mq5
  8. test_grid_identity.mq5
  9. test_grid_identity_multichart.mq5
  10. test_grid_restart_persistence.mq5

## Current phase: Grid Order Execution — Demo Integration Test
- User approved the Test Plan and confirmed Demo account availability.
- User approved manual Foreign Position verification followed by a chart-button-triggered cleanup.
- Added Experts/TGK/Tests/Grids/test_grid_order_execution_demo.mq5.
- The Test EA is separate from Production Grid EA and uses:
  - CTGKGridIdentity
  - CTGKGridRuntimeOrchestrator
  - CTGKGridOrderExecutionAdapter
  - CTrade
- Safety gates:
  - EnableDemoTest=false by default; user must set true and click START.
  - Rejects non-Demo accounts.
  - Requires Hedging margin mode.
  - Requires Terminal, EA and Account trade permissions.
  - Validates TestLot against Symbol Volume Min/Max/Step.
  - Foreign Magic = Instance Magic + 100,000,000; rejects if currently used by any open position/order on the account.
  - Uses chart Symbol only.
  - Checks Runtime is freshly initialized and in WAIT_INITIAL_ENTRY before sending seed orders, so stale/non-empty Instance state is rejected before opening anything.
- Test sequence:
  1. Open two BUY positions using Instance Magic.
  2. Record first actual fill price as Runtime Anchor.
  3. Open one BUY Foreign Position with separate Magic.
  4. Verify exactly two owned positions and exactly one foreign position/ticket.
  5. Request BUY -> SELL Mode reset.
  6. Runtime + Adapter close only exact chart Symbol + Instance Magic positions; Runtime reconciles fresh account state and retries.
  7. Verify Foreign Position remains with same Symbol/Magic/Ticket.
  8. Show CLEANUP FOREIGN POSITION button and wait for user inspection.
  9. On click, revalidate exact count, ticket, symbol and magic before closing that ticket.
  10. Final scan must show zero owned and zero foreign positions; delete only this Instance's test persistence snapshot and report FINAL PASS.
- If test fails, it stops and logs remaining owned/foreign counts, Magic Numbers and foreign ticket for manual inspection; it does not blindly clean up positions.
- Test opens three BUY market positions in total, default TestLot=0.01, and incurs Demo spread/commission.
- Requires a fresh dedicated chart with no Production Grid EA attached. Identity is chart-scoped and a chart with an existing Grid marker may reuse that Identity/Magic.
- Added phase documentation Docs/EAs/Grid/Phases/phase-grid-order-execution-demo-integration.md.
- Updated Docs/EAs/Grid/README.md, Docs/EAs/Grid/architecture.md, Docs/EAs/Grid/Testing/testing.md, and PROJECT_STATUS.md.
- git diff --check passed on 2026-11-02.
- MetaEditor compiler/runtime has not been run by assistant; user must compile/review before any Demo execution. The CPP/Python language server diagnostics for .mq5 are not valid MQL5 diagnostics (Serena previously could not recognize .mq5/.mqh syntax).
- No production EA or Adapter source was changed.

## Next action
Ask user to compile test_grid_order_execution_demo.mq5 in MetaEditor and report compiler errors/warnings. Do not ask them to run Demo trading before compile review and source inspection are accepted. Once compile passes, walk through safe Demo execution and ask them to inspect the Foreign Position before clicking cleanup. Only mark phase complete after user-reported MetaEditor compile and Demo integration PASS.

## Workflow
- Work phase by phase; do not start later phases without explicit approval.
- User performs MetaEditor/MT5 tests and reports results.
- Update Thai Docs and this memory after each completed phase.
- Before new Grid feature/refactor, run relevant Grid Regression Tests first.
- Use 2-space indentation and one parameter per line for multi-parameter test calls.
- If Serena/MCP fails, remind user to check the MCP Serena server.
