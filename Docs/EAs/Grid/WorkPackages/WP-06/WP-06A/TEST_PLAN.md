# WP-06A — Test Plan

สถานะ: CTO Design — approved contract; no implementation authorization

## Preconditions
- D-06-04 canonical configuration authority and Fixed Lot migration contract approved.
- Latest no-trade Grid Regression baseline run and recorded by Product Owner before implementation.
- Tests use fake identity/storage/snapshot/journal ports where possible; no Trade Request.

## Test Cases
| ID | Scenario | Expected |
|---|---|---|
| A-01 | Valid new instance, no owned Positions | Initialize safely; WAIT_INITIAL_ENTRY; no request |
| A-02 | Invalid Mode/Bounds/Step/Lot | Reject initialization before any mutation/trade |
| A-03 | Symbol volume min/max/step invalid for Fixed Lot | Reject config; no request |
| A-04 | Identity initialization fails | Block all runtime actions |
| A-05 | Snapshot missing and no owned Position | Fresh bootstrap allowed |
| A-06 | Snapshot missing but owned Position exists | RECOVERY_ERROR; no adoption |
| A-07 | Snapshot exists but checksum/replay invalid | RECOVERY_ERROR; gate closed |
| A-08 | Restored identity/config mismatch | RECOVERY_ERROR; no request |
| A-09 | Complete/stable empty owned snapshot and canonical projection agrees | Reconciliation succeeds; gate released |
| A-10 | Invalid/unstable/incomplete snapshot | Gate remains closed; no durable mutation |
| A-11 | Owned unmapped Position / orphan | Fail closed; no mapping guess |
| A-12 | Foreign Symbol/Magic positions present | Not adopted; untouched |
| A-13 | Repeated init after persisted state | No duplicate state transition |
| A-14 | OnDeinit while Positions exist | No close request; persisted state retained |
| A-15 | Any bootstrap/storage/reconcile error | New entry remains blocked and diagnostic identifies stage |
| A-16 | Legacy schema has no canonical Fixed Lot; no owned Positions and no unresolved Request; current Input valid | Durable, idempotent migration adopts exactly the validated Input before gate release |
| A-17 | Legacy schema has an owned live Position | Migration blocked; Recovery Error; do not infer Fixed Lot |
| A-18 | Legacy schema has an unresolved Entry Request | Migration blocked; Recovery Error; do not infer Fixed Lot |
| A-19 | Legacy Lifecycle mirror differs from canonical projection | Recovery Error; no precedence or silent repair |
| A-20 | Migration append/flush fails | No in-memory migration commit; gate remains closed |
| A-21 | Restart after durable migration commit | Same Fixed Lot restored; migration is not applied twice |
| A-22 | Config Epoch change requested by uncommitted Inputs | Canonical Config Epoch/config remains unchanged until reset commit succeeds |

## Regression / Evidence
- Compile production EA and test EA.
- Run relevant Identity, Lifecycle, Runtime Restoration, Mapping Reducer/Snapshot, Open Position Snapshot/Reconciliation tests.
- Run full latest no-trade Grid Regression suite.
- Product Owner records exact MetaEditor output and Test EA PASS summary.
