# WP-06D — Test Plan

สถานะ: Draft — TP rule known; test must verify reason-free close compatibility

## Preconditions
- WP-06A/B/C complete.
- Apply D-06-01: broker-side TP per Position = actual fill + GridStep for BUY, actual fill − GridStep for SELL.
- No Basket TP. Same rule applies to Anchor and normal Positions.
- Fresh no-trade Grid Regression baseline recorded.

## Test Cases
| ID | Scenario | Expected |
|---|---|---|
| D-01 | Owned BUY/SELL Position | Broker-side TP equals actual fill ± one GridStep; same for Anchor and normal Levels |
| D-01a | GridStep reset is pending while old Positions are being closed | Existing broker TP is not rewritten during close/reconciliation; rebuilt Grid uses the new Step for new Positions |
| D-02 | Foreign Symbol/Magic Position | Never modified or closed |
| D-03 | TP modify/close rejected | Mapping and ACTIVE retained; retry/error policy explicit |
| D-04 | Partial Close | Position remains ACTIVE while volume > 0 |
| D-05 | Full Close absent from stable snapshot | Reason-free durable Full Close transition |
| D-06 | Position remains in snapshot after close request | No reset/rebuild; wait/retry per policy |
| D-07 | Mode change with owned Positions | Close owned positions only, reconcile, then apply mode |
| D-08 | GridStep change with owned Positions | Close owned positions only, reconcile, then rebuild with same Anchor per approved contract |
| D-09 | Close scan invalid/unstable | No Full Close / no rebuild |
| D-10 | Bounds outside market with open Position | Broker-side TP remains active; block only new entries |
| D-10a | Position closes by TP | Full Close remains reason-free; Level cannot re-enter until price retouches/crosses original Entry Level |
| D-11 | Storage/reconciliation failure | Fail closed; never assume flat |
| D-12 | Restart during pending reset | Restore pending reset; do not apply until fresh reconciliation |
