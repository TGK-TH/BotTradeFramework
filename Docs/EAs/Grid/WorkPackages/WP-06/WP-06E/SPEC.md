# WP-06E — Strategy Tester End-to-End Readiness

สถานะ: CTO Design Draft — implementation not authorized

## Objective
Prove the integrated Production Grid V1 EA can execute the approved functional lifecycle in MT5 Strategy Tester under a documented Hedging configuration and emit reproducible trade-level evidence.

## Scope
- Compile and run the Production Grid V1 EA in MT5 Strategy Tester.
- Define supported account mode, symbol, timeframe, date range, tick model, execution settings, spread/commission/swap/deposit/leverage assumptions.
- Capture transaction/deal/position lifecycle telemetry and compare it with durable Reducer/Coordinator state.
- Validate initial Anchor, BUY/SELL, Bounds, activation/retrace, one-candidate selection, entry correlation, mapping, TP/close, re-entry, Mode/Step reset, foreign-position isolation, and restart/recovery scenarios where the Tester supports them.
- Validate one Request : one Position Identifier contract under the chosen Tester execution configuration; fail closed and stop if multiple identifiers appear for one Request.
- Record known limitations versus real broker Demo execution.
- Prepare handoff to the separate Strategy Tester Validation milestone; do not optimize strategy parameters in this WP.

## D-06-02 Dependency Evidence
D-06-02 Minimal Strategy Tester Probe is CLOSED / Product Owner accepted (2026-11-28). Its R-03 run validates one BUY request, exact Deal-set recovery, Position Identifier correlation, callbacks, and same-run recovery only. It does not establish true EA/Terminal restart recovery, SELL symmetry, partial-fill/multi-Deal behavior, or crash/power-loss durability. True EA/Terminal restart is tracked separately in D-06-06 and must not be inferred from Strategy Tester same-run recovery.

## Out of Scope
- Profitability claims or parameter optimization.
- Multi-Position Architecture implementation.
- Broker Demo/Live testing.
- Unapproved trade scenarios outside the agreed Tester matrix.

## Dependencies
- WP-06A through WP-06D accepted, including TP contract decision.
- User explicitly authorizes the Strategy Tester trading test scenario and approves symbol/date range/inputs.
- Dedicated Tester profile/config and safety boundaries prepared.

## Acceptance Criteria
- Production EA compiles with 0 errors / 0 warnings.
- All agreed functional Tester scenarios pass or have documented Product Owner-accepted limitations.
- Trade-level records agree with expected Request/Order/Deal/Position/Level state.
- No duplicate request, foreign-position mutation, premature ACTIVE, or silent orphan adoption.
- Tester settings and reports are reproducible from saved source revision and configuration.
- Known differences from live broker execution are documented.
- Product Owner accepts the readiness evidence; CTO formal review APPROVED.
