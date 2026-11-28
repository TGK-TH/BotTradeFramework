# WP-06B — Test Plan

สถานะ: CTO Design — Tester proof pending; no implementation authorization

## Preconditions
- D-06-02 Probe evidence reviewed and approved by Product Owner; see [Probe TEST_PLAN](../D-06-02_PROBE/TEST_PLAN.md).
- Any true restart claim is backed by an actual EA/Terminal restart test; same-run recovery simulation is not equivalent.
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
| B-13 | Same Deal Ticket observed again with byte-for-byte equivalent evidence | Idempotent no-op; no duplicate journal record or volume |
| B-14 | Same Deal Ticket observed with one or more conflicting properties | Recovery Error; no overwrite or double count |
| B-15 | Deal Association persisted then WP-05C sees matching Position | Reconciliation maps exact target and releases gate |
| B-16 | WP-05C runs before Deal Association is durable | Orphan/unresolved; no mapping; retry only after evidence is processed |

| B-17 | Pending callback queue reaches capacity | Overflow is observable and triggers exact-order History recovery |
| B-18 | Exact History Order selection by Order Ticket fails | Do not assume no fill; remain unresolved / Recovery Error |
| B-19 | Restart with accepted unresolved Request and known Order Ticket | Exact-order History recovery runs before entry gate opens |
| B-20 | History scan returns unrelated Deals with nearby time/price/Magic | Reject unless exact DEAL_ORDER matches |
| B-21 | History scan is incomplete or bounded interval cannot be proven complete | No association from partial evidence; gate remains closed |
| B-22 | Legacy Deal Association records lack v2 evidence fields | Preserve/replay legacy mapping history; do not fabricate Deal price or Order Ticket |
| B-23 | Legacy unresolved Initial Request lacks sufficient Deal evidence for Anchor reconstruction | Fail closed; no bootstrap from incomplete evidence |
| B-24 | Snapshot/journal migration interrupted after durable version marker | Restart deterministically completes/replays once; no duplicate Deal volume |
| B-25 | Identical Deal evidence is replayed after restart | Reducer treats it as idempotent no-op; aggregate volume unchanged |
| B-26 | Initial Entry Deal arrives before normal Config Epoch exists but matches typed INITIAL_ENTRY Request | Exact correlation succeeds without fabricating normal Grid config; Bootstrap remains pending until WP-06C commit |
| B-27 | OnTradeTransaction receives DEAL_ADD | Callback only enqueues/marks dirty; no Reducer mutation, journal write, mapping or long History scan |
| B-28 | CTrade ResultDeal identifies one Deal but History contains additional exact-order Deals | Enumerate and persist every matching Deal exactly once; ResultDeal is not treated as the complete set |

## Strategy Tester Integration Trace
Capture terminal/build, Hedging mode, symbol, filling/execution settings, tick model, callback types/order, Deal and Order Tickets, Entry type, Symbol, Magic, Position Identifier, volume/price, History selection behavior, partial-fill behavior where available, and restart recovery of an unresolved Request. This is a separately approved Tester-only integration test; Unit Tests remain no-trade.

## Regression
- Entry Adapter/Pipeline, Reducer, Snapshot Storage, Runtime Restoration, Open Position Snapshot/Reconciliation.
- Verify no Trade API is called by Unit Tests.
- Tester-specific transaction trace captured by a separate explicitly approved Strategy Tester integration test.
