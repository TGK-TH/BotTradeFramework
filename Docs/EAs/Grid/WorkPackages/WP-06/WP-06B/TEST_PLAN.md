# WP-06B — Test Plan

สถานะ: Draft — no implementation authorization

## Preconditions
- D-06-02 approved with observed Strategy Tester evidence.
- WP-06A integration seam defined.
- No-trade Regression baseline recorded.
- Unit tests use fake transaction/history/deal sources and fake journal; no Trade Requests.

## Test Cases
| ID | Scenario | Expected |
|---|---|---|
| B-01 | Valid entry deal for persisted Order Ticket | One exact Deal Association appended |
| B-02 | Multiple partial Deals, same Position Identifier | Unique Deal associations; aggregate volume <= Requested Volume |
| B-03 | Repeated same transaction callback | No duplicate association/volume |
| B-04 | Deal event arrives before execution result correlation is available | Defer; later exact correlation resolves or fail closed |
| B-05 | History query/select/property read fails | No association; request remains unresolved |
| B-06 | Wrong Symbol or Magic | Reject as foreign evidence |
| B-07 | Deal is not entry/increasing exposure | Ignore for entry association; no mapping side effect |
| B-08 | Deal Order Ticket does not match durable Request | Reject; no time/price heuristic |
| B-09 | Invalid/zero Position Identifier or Deal Ticket | Reject |
| B-10 | Multiple Position Identifiers for one Request | Fail closed under current contract; no partial activation |
| B-11 | Aggregate Deal volume exceeds Requested Volume | Fail closed; no durable over-association |
| B-12 | Out-of-order deals for same order/position | Deterministic projection and sequence |
| B-13 | Duplicate deal ticket with conflicting fields | Recovery/error; no guessed overwrite |
| B-14 | Deal Association persisted then WP-05C sees matching Position | Reconciliation maps exact target and releases gate |
| B-15 | WP-05C runs before Deal Association is durable | Orphan/unresolved; no mapping; retry only after evidence is processed |

## Regression
- Entry Adapter/Pipeline, Reducer, Snapshot Storage, Runtime Restoration, Open Position Snapshot/Reconciliation.
- Verify no Trade API is called by Unit Tests.
- Tester-specific transaction trace captured by a separate explicitly approved Strategy Tester integration test.
