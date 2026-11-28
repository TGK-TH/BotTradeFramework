# WP-06E — Test Plan

สถานะ: Draft — requires separate Product Owner authorization for Strategy Tester Trade Requests

## Preconditions
- WP-06A/B/C/D formally complete.
- Fresh full no-trade regression PASS.
- Production EA compile PASS.
- Product Owner approves Tester account mode, Symbol, period, model, inputs, deposit/leverage and test scenario.
- Tester is isolated from other EAs and no real account is used.

## Functional Matrix
| ID | Scenario | Expected |
|---|---|---|
| E-01 | Fresh BUY Grid, price initially outside Bounds | Wait; no request until inside |
| E-02 | Fresh SELL Grid, price inside Bounds | One initial entry; actual fill becomes Anchor |
| E-03 | Initial fill correlation | Exact Order/Deal/Position evidence; durable Anchor mapping |
| E-04 | BUY level activation/retrace | Expected candidate and one entry |
| E-05 | SELL level activation/retrace | Expected candidate and one entry |
| E-06 | Multi-level gap/cross | At most one candidate with correct priority |
| E-07 | Entry request pending/duplicate ticks | No duplicate request |
| E-08 | Partial Deals for one Position Identifier | Correct aggregate association |
| E-09 | Multiple Position Identifiers for one Request | Fail closed; no guessed mapping |
| E-10 | TP/close and re-entry | Matches approved D-06-01 and reason-free close contract |
| E-11 | Bounds crossed while Position open | No new entry outside; management continues |
| E-12 | Mode reset | Close → stable reconcile → apply new mode → wait for new Anchor |
| E-13 | GridStep reset | Close → stable reconcile → rebuild same Anchor per approved contract |
| E-14 | Foreign position exists | Remains untouched |
| E-15 | Tester-supported state restore only (if available) | Durable state restored; gate closed until stable reconcile; not accepted as proof of true Terminal Process Restart |
| E-16 | Storage/event/history failure injection where feasible | No unsafe new entry; clear Recovery Required |
| E-17 | Repeat identical configuration | Reproducible report and trade records |

## Restart Evidence Boundary
D-06-02 same-run recovery is already accepted for its limited Probe scope. It is not a terminal restart. A genuine EA/Terminal restart proof is tracked separately in D-06-06 and is not a prerequisite that Strategy Tester can claim to satisfy through same-run recovery. Do not expand WP-06E into a second restart-proof project.

## Reproducibility Record
- EA source revision / version.
- MT5 build and Tester mode.
- Hedging setting and Symbol contract.
- Timeframe, date range, tick model.
- Inputs including Bounds, Mode, Step, Lot.
- Initial deposit, currency, leverage, spread, commission, swap.
- Tester report, deal/order/position export, Experts log, diagnostics.
- Known limitations and any non-default settings.

## Safety
- This is a real Strategy Tester execution test that sends simulated trade requests; it is not a Unit Test.
- No Demo/Live account. No real broker orders.
- If test data shows unsupported multiple Position Identifiers per request, stop the run and preserve evidence; do not bypass Fail Closed.
