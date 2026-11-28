# D-06-02 — Minimal Strategy Tester Probe / TEST_PLAN

อัปเดต: 2026-11-28

สถานะ: Test design พร้อม; ห้ามรัน Probe หรือส่ง Tester Trade Request จนกว่า Product Owner จะอนุมัติขั้นตอน execution หลัง Source Compile ผ่าน

## 1. Preconditions

1. Product Owner อนุมัติ Probe scope นี้แล้ว
2. Implementer ได้รับมอบหมายและได้รับอนุมัติให้สร้าง Probe source แยกต่างหาก
3. อ่าน `AGENTS.md`, Probe `SPEC.md`, และไฟล์ที่ SPEC ระบุ
4. ผู้ใช้รัน latest no-trade Grid Regression baseline ก่อนเริ่ม implementation และรายงาน PASS
5. Probe source compile ผ่าน `0 errors, 0 warnings` ก่อนขออนุมัติรัน
6. เตรียม Strategy Tester configuration แบบ Hedging และระบุ Symbol / date range / tick model / execution delay
7. กำหนด Probe Magic ที่ไม่ชนกับ Magic อื่นใน Tester และกำหนด Session ID ใหม่ที่ไม่เคยใช้
8. `EnableTestTrade` ต้องเป็น false ในค่า Default; ผู้ใช้จะเปลี่ยนเป็น true เฉพาะเมื่ออนุมัติ execution run แล้วเท่านั้น
9. ห้ามใช้ Optimization และห้ามรันในบัญชี Demo/Live

## 2. Test Cases

| ID | Scenario | Expected |
|---|---|---|
| P-01 | Attach/run Probe outside Strategy Tester | Initialization rejected; no Trade API call |
| P-02 | Run in Tester Optimization | Initialization rejected; no Trade API call |
| P-03 | EnableTestTrade=false | No Trade Request; environment diagnostics only |
| P-04 | Non-Hedging Tester account | Initialization rejected; no Trade Request |
| P-05 | Invalid volume / volume step | Rejected before sending |
| P-06 | Existing Position or active Order with same Symbol + Magic | Rejected before sending |
| P-07 | Valid single Market Buy request | Exactly one request; request result/order ticket recorded |
| P-08 | Valid single Market Sell request | Exactly one request; request result/order ticket recorded |
| P-09 | Request rejected / not accepted | No automatic retry; record retcode and stop |
| P-10 | Transaction callbacks after request | Callback types and receive sequence recorded |
| P-11 | REQUEST callback | Request/Result fields recorded only for REQUEST transaction |
| P-12 | DEAL_ADD immediate History select succeeds | Deal properties and success recorded |
| P-13 | DEAL_ADD immediate History select fails | Failure/error recorded; later exact History scan may recover |
| P-14 | Exact History Order selection by ResultOrder | Exact Order properties retrieved or explicit failure |
| P-15 | Exact-order scan with unrelated nearby Deals | Only Deals whose DEAL_ORDER exactly matches are retained |
| P-16 | ResultDeal hint is one of multiple exact-order Deals | All exact-order Deals retained; ResultDeal treated only as hint |
| P-17 | Deal required-property read fails | Evidence marked incomplete; no fabricated defaults |
| P-18 | One exact-order Deal | Single Deal recorded; no claim that partial fills are impossible |
| P-19 | Multiple exact-order Deals with same Position Identifier | All Deals retained; volume aggregated and bounded by Requested Volume |
| P-20 | Multiple exact-order Deals with different Position Identifiers | Critical Contract Conflict; no mapping/aggregation across Positions |
| P-21 | Exact Deal aggregate volume exceeds Requested Volume | Critical evidence conflict; no success |
| P-22 | Exact Deal Symbol/Magic/Entry/Direction mismatch | Evidence rejected / Critical diagnostic |
| P-23 | Live Position snapshot matches exact Deal Position Identifier | Position ticket, identifier, volume and average open price recorded and compared |
| P-24 | No Deal found while History selection/property access incomplete | Remains unresolved; cannot classify as no-fill |
| P-25 | Bounded callback buffer reaches capacity | Overflow counter/diagnostic visible; no silent overwrite |
| P-26 | Persisted Order Ticket uses a large 64-bit value | Decimal string round-trip exact; no floating-point conversion |
| P-27 | Clear volatile queue then reload persisted Request state | Recovery scan reproduces same exact-order Deal set and aggregate |
| P-28 | Recovery scan differs from first scan | Report discrepancy; no silent correction |
| P-29 | Attempt to force EA reinit via ChartSetSymbolPeriod in Tester | Must not be used as restart proof; record Tester limitation |
| P-30 | True EA/Terminal restart recovery | NOT_TESTED in normal Tester run unless a genuine supported restart path is independently demonstrated |
| P-31 | Duplicate Session ID / persisted state exists | Refuse new Trade Request; no accidental second request |
| P-32 | Probe completes | Emit final summary with PASS / FAIL / NOT_OBSERVED / NOT_TESTED per evidence item |
| P-33 | Session file contains REQUEST_STARTED but no durable Order Ticket | Fail Closed; no second Trade Request is sent |

## 3. Required Run Matrix

Run only after separate explicit Product Owner authorization.

| Run | Direction | Volume | Purpose |
|---|---|---|---|
| R-01 | BUY | Valid minimum/approved volume | Baseline event + exact History + Position correlation |
| R-02 | SELL | Same approved volume | Verify direction/type evidence symmetry |
| R-03 | BUY or SELL | Approved volume | Recovery simulation from persisted ticket |
| R-04 | Optional | Only if the supported Tester configuration can naturally produce partial fills | Observe multi-Deal behavior; do not create multiple Requests to imitate partial fill |

R-01/R-02 may be combined only if the Probe design can guarantee exactly one Request per Session and the Product Owner explicitly approves each run. Prefer separate Session IDs for clean evidence.

## 4. Evidence Capture Checklist

For each run preserve:
- Tester Journal and Experts log containing Probe Session ID
- Terminal build
- Symbol, date range, timeframe
- Hedging account margin mode
- Tick model / price generation mode
- Execution delay
- Symbol execution mode / filling mode
- Order filling type
- Request return / retcode / Order Ticket / ResultDeal hint
- Callback sequence and timestamps
- Immediate History read result from DEAL_ADD callback
- Exact History Order properties
- Every exact-order Deal Ticket and required properties
- Aggregate Deal volume and distinct Position Identifier count
- Live Position snapshot and matching result
- Recovery simulation persisted record + second scan output
- Final Probe summary and any NOT_OBSERVED / NOT_TESTED items

## 5. Interpretation Rules

- Callback order observed in one run is evidence of that run only; do not convert it into a universal MT5 ordering guarantee.
- A Deal property unavailable immediately in callback but available later means production must rely on serialized deferred History processing.
- If ResultDeal is zero or points to only one Deal, exact-order enumeration remains the source of the complete Deal set.
- One Deal in a run does not prove partial fills cannot happen.
- Multiple Deals with one Position Identifier may support same-Position partial fill behavior for that tested configuration.
- Multiple Position Identifiers for one Order is a blocker for current one-Request-to-one-Position contract; stop WP-06B progression and reopen Multi-Position Architecture review.
- Incomplete History selection/property reads never prove no-fill.
- Recovery simulation is not a true EA/Terminal restart.
- If actual restart cannot be proven within Strategy Tester, keep the restart acceptance open and request a separate Product Owner decision; do not quietly mark D-06-02 fully passed.

## 6. Regression / Safety

- No existing Unit Test may send a Trade Request.
- Probe is the only approved exception once the user separately authorizes a Tester execution run.
- No Production source changes are allowed in this task.
- No Demo/Live Trade Request, no close/modify request, and no foreign Position access.
- User runs MT5 Strategy Tester and reports actual results.
- Compile PASS and Tester PASS are separate evidence.
