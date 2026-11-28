# D-06-02 Minimal Strategy Tester Probe — Implementation Report (CTO Remediation)

อัปเดต: 2026-11-28
Work Package / Card: WP-06 / D-06-02 Minimal Strategy Tester Probe
Trello: https://trello.com/c/7S8Pw7nE/24-d-06-02-minimal-strategy-tester-probe
อ้างอิง:
- `Docs/EAs/Grid/WorkPackages/WP-06/D-06-02_PROBE/SPEC.md`
- `Docs/EAs/Grid/WorkPackages/WP-06/D-06-02_PROBE/TEST_PLAN.md`
- `Docs/EAs/Grid/WorkPackages/WP-06/D-06-02_PROBE/CTO_REVIEW_HANDOFF_REMEDIATION_V3.md`
- `.agents/skills/tgk-implementation-self-review/SKILL.md`
- `.agents/skills/tgk-implementation-self-review/references/adversarial-review-protocol.md`

Implementer: **ChatGPT (CTO acting as Implementer after explicit Product Owner instruction on 2026-11-28)**
สถานะ: **Source remediation implemented; MetaEditor compile reports 0 errors / 0 warnings; Product Owner compile verification PASS; Strategy Tester R-03 BUY runtime evidence received and CTO-reviewed. Core BUY request/event/History/Position/same-run recovery path PASS for this run. TRUE_RESTART_RECOVERY remains NOT_TESTED; environment evidence and FileFlush durability limitations remain documented. D-06-02 is not declared fully complete until the outstanding restart acceptance is dispositioned by Product Owner.**

---

## 1. Authority and Scope

ผู้ใช้เปลี่ยน role agreement อย่างชัดเจนให้ ChatGPT รับช่วง implementation เนื่องจากโควต้า Antigravity หมด จึงอนุญาตให้แก้เฉพาะขอบเขต remediation ของ D-06-02 ตาม SPEC และ Findings CR-09..CR-14

แก้ไขเฉพาะ:
- `Experts/TGK/Tests/Grids/test_grid_trade_event_probe.mq5`
- `Docs/EAs/Grid/WorkPackages/WP-06/D-06-02_PROBE/IMPLEMENTATION_REPORT.md`

ไม่แก้ Production EA / Production `.mqh`, SPEC, TEST_PLAN, Handoff, Skill หรือไฟล์ทดสอบ Grid อื่น

ไม่มีการรัน Strategy Tester, ไม่มี Trade Request, ไม่มี Close/Modify Request, ไม่มีการเปลี่ยน Product/Trading Contract, ไม่มี Git staging operation, Commit หรือ Push

## 2. Implementation Summary

| Finding | Status | Implementation / Evidence |
|---|---|---|
| **CR-09 — Callback evidence lost before summary** | **FIXED (Static)** | เพิ่ม immutable callback archive ก่อน clear volatile queue; sequence number แยกจาก queue index; จำกัดจำนวนหลักฐานรวมไม่เกิน `MAX_CALLBACKS`; เลื่อน Trade Path Final Summary ผ่าน `OnTimer()` หลัง observation window อย่างน้อย 2 วินาทีและ callback quiet period 1 วินาที; หาก callback มาหลัง summary จะเปิด summary ใหม่เพื่อสะท้อน late evidence; เพิ่ม `OnDeinit()` fallback เพื่อ emit pending summary หาก Strategy Tester จบก่อน Timer event (ระบุชัดว่า quiet period อาจยังไม่ครบ) |
| **CR-10 — Recovery compares aggregates only** | **FIXED (Static)** | เพิ่ม `SnapshotFirstScanDeals()`, `DealRecordsEqual()`, `CompareExactDealSets()`; เก็บ First Scan Deal Ticket set และ properties ทั้งหมด; เปรียบเทียบแบบ one-to-one ด้วย Ticket ไม่ขึ้นกับลำดับ enumeration; ตรวจ count, Order, Entry, Type, Symbol, Magic, Position ID, Volume, Price, Time, property completeness, validation status และ conflict string; `AC-11` PASS ได้เมื่อทั้ง First Scan และ Recovery Scan เป็น `SCAN_COMPLETE_MATCH` เท่านั้น และ aggregate projection ตรงกัน |
| **CR-11 — Safety Gate skips incomplete enumeration** | **FIXED (Static)** | `PassesTradeGates()` fail closed เมื่อ `PositionGetTicket(i)` หรือ `OrderGetTicket(i)` คืน 0; ใช้ bool-returning overloads สำหรับ Symbol/Magic property reads; property-read failure ทุกกรณีหยุด Gate-8 ก่อน Trade Request |
| **CR-12 — Persistence byte count / FileFlush semantics** | **FIXED WITH API LIMITATION (Static)** | เพิ่ม `ExpectedFileWriteStringBytes()` แปลงด้วย `CP_ACP` และนับ bare LF ที่ FILE_TXT ขยายเป็น CRLF; `WriteLineChecked()` ต้องได้จำนวน bytes ตรงกับค่าคาดหมายแบบ exact และไม่มี observable write error; `PersistState()` fail เมื่อพบ non-zero error หลังเรียก `FileFlush()`; Source/Log ไม่อ้างว่า `GetLastError()==0` พิสูจน์ flush/durability สำเร็จ |
| **CR-13 — Immediate Deal property reads use value overloads** | **FIXED (Static)** | `OnTradeTransaction()` ใช้ bool-returning `HistoryDealGetInteger/Double/String` overload สำหรับทุก required property; `imm_read_ok=true` ได้เมื่อทุก read คืน true เท่านั้น; error code เป็นข้อมูลประกอบ ไม่ใช่เกณฑ์ success |
| **CR-14 — Missing finite-number validation** | **FIXED (Static)** | ตรวจ `MathIsValidNumber()` สำหรับ Deal Volume/Price ก่อน validation/aggregation และ Position Volume/Open Price ก่อนยอมรับ Position snapshot; ค่า non-finite หรือ non-positive ทำให้ Deal invalid หรือ Position snapshot incomplete |

### Additional regression hardening

- **CR-06:** Parser นับ physical lines จริงและปฏิเสธ blank physical lines; blank lines ไม่สามารถหลบ `MAX_PERSIST_LINES` ได้
- **CR-07 / CR-12:** Exact byte-count validation และข้อจำกัดของ void-returning `FileFlush()` ระบุชัด; ไม่มีการ retry หลัง post-request persistence failure
- **CR-08:** ยังคงใช้ valid Deal Position ID และ complete Position snapshot; AC-10 ยังตรวจ `g_positions[0].props_ok`
- **MR-05 / MR-06:** Zero History Deal Ticket / Position Ticket ยังทำให้ enumeration incomplete; Gate-8 เพิ่ม fail-closed handling แยกต่างหาก
- **MR-07:** Report นี้บันทึก Git status ก่อน/หลังอย่างแยกกัน และไม่อ้างว่า staging state คงเดิมโดยไม่มีหลักฐาน

## 3. Requirement-to-Code Trace

| Requirement / Test | Code path | Expected evidence |
|---|---|---|
| CR-09 / AC-05 / AC-06 | `ArchiveCallbacksAndClearQueue()`, `AppendCallback()`, `OnTradeTransaction()`, `ScheduleFinalSummary()`, `OnTimer()`, `OnDeinit()`, `EmitFinalSummary()` | Summary แสดง archived + current callback count, overflow, sequence และ immediate DEAL_ADD evidence; late callback ทำให้เกิด refreshed summary |
| CR-10 / P-27 / P-28 / AC-11 | `SnapshotFirstScanDeals()` → `RunExactOrderScan()` → `CompareExactDealSets()` → AC-11 | Exact Deal Ticket set และ relevant properties ตรงกัน; scan ทั้งสองรอบ complete; otherwise INCOMPLETE/FAIL |
| CR-11 / P-06 / Gate-8 | `PassesTradeGates()` | Ticket 0 หรือ Symbol/Magic read failure ทำให้ gate fail ก่อน `PersistState(REQUEST_STARTED)` และก่อน Trade API |
| CR-12 / P-09 / P-33 / AC-15 / AC-16 | `ExpectedFileWriteStringBytes()`, `WriteLineChecked()`, `PersistState()`, `OnTick()` | Exact byte count; observable write/flush error aborts; REQUEST_STARTED failure prevents request; ticket persistence failure remains ambiguous and no retry |
| CR-13 / P-12 / P-13 | `OnTradeTransaction()` | Immediate read success only if all bool overloads return true; any failed read remains incomplete |
| CR-14 / P-17 / P-23 | `RunExactOrderScan()`, `CapturePositionSnapshot()` | Non-finite Deal data cannot aggregate; non-finite Position data makes snapshot incomplete |
| CR-06 regression | `LoadPersistedRecord()` | Physical line cap enforced; blank, malformed, duplicate, unknown, missing and invalid fields fail closed |

## 4. Regression Matrix

| Prior Finding | Re-check result | Evidence location |
|---|---|---|
| CR-01 | PASS (Static) | `OnTick()`, `PersistState()`: REQUEST_STARTED before send; post-request ticket persistence failure stops without retry |
| CR-02 | PASS (Static) | `LoadPersistedRecord()`: NOT_FOUND / CORRUPT / IO_ERROR distinct; existing session blocks replay |
| CR-03 | PASS (Static) | `EmitFinalSummary()`: AC verdicts depend on observed evidence; AC-14 remains NOT_RUNTIME_VERIFIED |
| CR-04 | PASS (Static) | `RunExactOrderScan()`, `AggregateScanResults()`: exact Order, required Deal properties and request matching before aggregation |
| CR-05 | PASS (Static) | `RunExactOrderScan()`: History selection, Order properties, Deal properties and enumeration anomalies produce non-complete status |
| MR-01 | PASS (Static) | `RunExactOrderScan()`: Deal buffer capacity overflow -> SCAN_INCOMPLETE |
| MR-02 | PASS (Static) | `CapturePositionSnapshot()`: all matching Positions enumerated; zero ticket, property error, capacity overflow or invalid numeric data -> incomplete |
| MR-03 | PASS (Static) | `ProbeCallback`, `OnTradeTransaction()`, archive + deferred summary: bounded callback evidence and required transaction fields |
| MR-04 | PASS (Static; runtime retest required) | `UlongToDecStr()`, `DecStrToUlong()`, `VerifySerializationSelfCheck()`; parser now bounds-checks normalized decimal text against `18446744073709551615` before accumulation, and max test value is constructed as `~(ulong)0` to avoid oversized-literal interpretation |
| CR-06 | PASS (Static) | `LoadPersistedRecord()`: strict physical line count and blank-line rejection added |
| CR-07 | PASS WITH API LIMITATION (Static) | `WriteLineChecked()`, `PersistState()`: exact bytes; FileFlush is void and no durability claim |
| CR-08 | PASS (Static) | `AggregateScanResults()`, `EmitFinalSummary()`: valid Deal evidence and complete Position properties |
| MR-05 | PASS (Static) | `RunExactOrderScan()`: HistoryDealGetTicket(index)==0 -> SCAN_INCOMPLETE |
| MR-06 | PASS (Static) | `CapturePositionSnapshot()` and `PassesTradeGates()`: PositionGetTicket(index)==0 -> incomplete/fail closed |
| MR-07 | PASS (Report audit) | Git baseline/final status recorded below; no unsupported staging-preservation claim |

## 5. Adversarial Self-Review

### Pass A — Requirement-to-Code Trace

ตรวจเส้นทางจาก API result ไปถึง state/verdict สำหรับทุก CR-09..CR-14:
- Callback data: bounded queue → immutable archive before recovery clear → callback events received after OnTick → deferred timer summary → AC-05/AC-06.
- Recovery data: First Scan snapshot → second scan from persisted ticket → one-to-one exact Ticket match → property equality → both scan statuses complete → aggregate cross-check → AC-11.
- Safety Gate: enumeration index → nonzero ticket → bool property reads → exact Symbol+Magic comparison → only then permit request.
- Persistence: string → ANSI encoded bytes + newline expansion → exact FileWriteString count → FileFlush invocation/error observation → request gate.
- Immediate callback read: HistoryDealSelect → all required bool property reads → `imm_read_ok`.
- Numeric data: API property read → finite validation → Deal aggregation / Position snapshot validity.

### Pass B — Adversarial challenges

| Challenge | Result |
|---|---|
| Callback queue cleared before summary | Archived first; summary deferred until callback quiet period; late callback triggers refreshed summary; pending summary is emitted during deinit if timer never fires |
| Callback count reset changes sequence identity | Sequence uses monotonic `g_callback_sequence`, not queue index |
| More than one callback buffer fills across archive/current queues | Combined count is capped at `MAX_CALLBACKS`; archive allocation failure/capacity overflow is counted and visible |
| First and recovery scans have same count/volume/Position IDs but different Deal Tickets | Exact one-to-one Ticket set comparison rejects mismatch |
| First scan is incomplete but recovery scan is complete | AC-11 cannot PASS; first scan must be `SCAN_COMPLETE_MATCH` |
| Position/Order ticket enumeration silently skips zero | Gate-8 returns false immediately |
| Position/Order properties fail | Gate-8 returns false; no request |
| FileWriteString writes fewer/more bytes than expected | Exact byte mismatch returns false |
| FileFlush returns void | No success claim is made from LastError==0; non-zero observed error fails persistence |
| One immediate Deal property read fails but later calls succeed | Bool result is retained; `imm_read_ok` remains false |
| Deal/Position values are NaN or infinity | `MathIsValidNumber()` rejects the evidence |
| Recovery summary reads recovery buffer instead of first-scan buffer | AC-09 reads the immutable first-scan Deal snapshot |

## 6. Runtime Incident — First Approved Tester Attempt

- Session: `PROBE-D0602-R01`, XAUUSD M1, real ticks, 2026-10-01 to 2026-10-10.
- Inputs included `EnableTestTrade=true`, BUY, volume 0.01, Magic 123456.
- Tester stopped during `OnInit()` with `INIT REJECTED: 64-bit ticket serialization self-check failed`.
- No `OnTick()` probe execution occurred; no Trade Request was sent. This is a safe initialization failure, not a trade failure.
- Root-cause hypothesis: the self-check supplied ULLONG_MAX as an oversized numeric literal; MQL5 literal interpretation may not preserve the intended unsigned 64-bit value. The parser also used arithmetic wraparound as its overflow detector.
- Remediation: construct ULLONG_MAX using `(ulong)(~(ulong)0)`; normalize decimal input and compare it lexicographically against the maximum ulong decimal string before accumulation.
- **Verification status:** source remediation applied; MetaEditor compile and a fresh Strategy Tester initialization/runtime retest are still required. Do not reuse the previous Session ID; use a new unique Session ID for the next authorized run.

### Runtime Incident — Second Approved Tester Attempt

- Session: `PROBE-D0602-R02`, XAUUSD M1, 2026-10-01 to 2026-10-02.
- `OnInit()` passed. At the first `OnTick()`, `FileIsExist()` returned false and `GetLastError()` returned 5019.
- MQL5 defines 5019 as `ERR_FILE_NOT_EXIST`; this is the expected result for a fresh session file, not an I/O failure. The source incorrectly treated 5004 as the not-found code (5004 is `ERR_CANNOT_OPEN_FILE`).
- The fail-closed branch therefore prevented the first `REQUEST_STARTED` persistence and no Trade Request was sent. AC-15/AC-16 confirm the safety behavior, but this run does not validate request/event/recovery behavior.
- Remediation: treat 5019 as the expected not-found result; retain fail-closed behavior for other unexpected errors.
- Tick-data caveat: the selected date had no real ticks; MT5 generated ticks for the test. This did not cause the file error, but the run is not evidence using real historical ticks.
- **Verification status:** source fix applied; compile and fresh-session Tester rerun are required. Use a new unique Session ID.

## 7. API Semantics and Limitations

- `FileWriteString()` returns bytes written. Expected bytes are calculated from the same ANSI code page (`CP_ACP`) and FILE_TXT bare-LF to CRLF expansion.
- `FileFlush()` returns void. A zero LastError after invocation is not proof of successful flush, OS fsync, hardware durability, or crash-safe persistence. The code logs invocation and treats an observable non-zero error as failure, but cannot independently prove durability through this API.
- History Deal property reads use bool-returning overloads. `GetLastError()` is diagnostic only and does not substitute for the bool result.
- Position/Order property reads in Gate-8 use bool-returning overloads. A failed read cannot be interpreted as absence.
- Callback summary uses a minimum observation delay and quiet period; callback event ordering/timing remains runtime evidence to be observed in the approved Tester run. A callback arriving after a summary causes a refreshed summary.

## 7. Compile Evidence (Implementer)

- **Affected program:** `Experts/TGK/Tests/Grids/test_grid_trade_event_probe.mq5`
- **Command:**
  `WINEPREFIX="$HOME/wine-python-mt5" /usr/local/bin/wine "C:\\Program Files\\MetaTrader 5\\MetaEditor64.exe" /compile:"Z:\\Users\\tachagon\\Documents\\13_Trade\\1_Bot\\BotTradeFramework\\Experts\\TGK\\Tests\\Grids\\test_grid_trade_event_probe.mq5" /inc:"Z:\\Users\\tachagon\\Documents\\13_Trade\\1_Bot\\BotTradeFramework" /log:"Z:\\Users\\tachagon\\Documents\\13_Trade\\1_Bot\\BotTradeFramework\\compile.log"`
- **Compile log:** `compile.log` (UTF-16LE; decoded for inspection)
- **Exact result:** `Result: 0 errors, 0 warnings, 2723 ms elapsed, cpu='X64 Regular'`
- **Generated artifact:** `Experts/TGK/Tests/Grids/test_grid_trade_event_probe.ex5` timestamp updated with the compile.
- **Process exit caveat:** MetaEditor/Wine launcher returned process exit code `1` even though the newly timestamped compile log reports `0 errors, 0 warnings` and the `.ex5` artifact was regenerated. This discrepancy is recorded rather than hidden. Product Owner subsequently reported an independent MetaEditor Compile PASS; after the final `OnDeinit()` fallback patch, a further local compile again reported `0 errors, 0 warnings` (2723 ms).
- This is compile evidence only, not runtime or Strategy Tester evidence.

## 8. Tests and Runtime Evidence

### Compile

- MetaEditor compile: compile log reports 0 errors / 0 warnings (see caveat above).
- Product Owner independently confirmed Compile PASS before Strategy Tester execution.

### Strategy Tester — R-03

- Session: `PROBE-D0602-R03`.
- Terminal build: 6361; Symbol: XAUUSD; timeframe: M1.
- Test interval: 2026-11-27 00:00 to 2026-11-28 00:00 (Tester log timestamps are terminal-local test time).
- Tick model: `generating based on real ticks`; log confirms real tick data available from 2020-01-02.
- Inputs: `EnableTestTrade=true`, BUY, volume 0.01, Magic 123456, `HistoryMarginSec=60`.
- Session started with a new unique Session ID. `OnInit()` passed all reported safety gates.
- Persistence: `REQUEST_STARTED` write count verified and `FileFlush()` invoked before the request. `CTrade` returned `ok=YES`, retcode `10009`, Order Ticket `2`, Result Deal `2`, volume `0.01`, price `3568.02`; Order Ticket `2` was persisted.
- Exact History scan: complete; exactly one matching Deal (`#2`) with `DEAL_ORDER=2`, `DEAL_POSITION_ID=2`, Symbol XAUUSD, Magic 123456, volume 0.01 and price 3568.02; required properties read and validation passed.
- Live Position snapshot: one Position; ticket `2`, identifier `2`, volume 0.01, open price 3568.02; snapshot complete and Position Identifier matched the Deal.
- Same-run recovery: persisted Order Ticket `2` reloaded; recovery exact-order scan returned the same complete Deal set; exact-set comparison and aggregate projection matched.
- Callbacks: 4 captured, overflow 0. Observed sequence: `DEAL_ADD`, `ORDER_DELETE`, `HISTORY_ADD`, `REQUEST`. Immediate `HistoryDealSelect()` and all required immediate Deal property reads succeeded for the `DEAL_ADD` callback.
- Summary: AC-01..AC-13, AC-15 and AC-16 reported PASS for the applicable evidence; AC-14 correctly reported `NOT_RUNTIME_VERIFIED` by the EA. The user-provided log independently confirms the run's concrete evidence described above.
- At the end of the Tester run, MT5 closed the remaining Position due to end of test and generated a closing SELL Deal `#3`. This was Tester cleanup, not a second Probe Entry Request or a Probe-issued Close/Modify request. Probe summary had already recorded the open Position snapshot. Final balance reflects this Tester end-of-run close.
- No partial-fill conclusion: this run produced one Deal only; it does not prove that partial fills cannot occur.
- `TRUE_RESTART_RECOVERY=NOT_TESTED`; the recovery evidence is same-run cold-state simulation only.

### Evidence gaps / limitations

- The supplied Journal does not explicitly print `ACCOUNT_MARGIN_MODE` or the actual Order Filling Type selected by `CTrade`; it prints symbol filling flags (`Fill=3`) and the safety-gate pass message. Retain this as an environment evidence gap rather than infer the missing values.
- `FileFlush()` is a void API. The log proves invocation, not OS-level flush or crash-safe durability.
- Only BUY was exercised. SELL symmetry and natural multi-Deal/partial-fill behavior were not tested.
- No genuine EA/Terminal restart was performed.
- Unit / Grid Regression runtime suites were not rerun as part of R-03; this diagnostic probe is not a replacement for those suites.

### CTO assessment

- **R-03 core BUY path: PASS** — one request, persisted request state and order ticket, exact Order→Deal evidence, live Position correlation, callbacks and same-run recovery all matched.
- **D-06-02 full acceptance: OPEN / NOT FULLY CLOSED** — true restart remains NOT_TESTED as required by SPEC/TEST_PLAN; Product Owner must decide whether to track it as a separate follow-up (e.g. WP-06E / D-06-06) or require further evidence before closing the parent acceptance.

## 9. Git State and Change Preservation

**Git status before this implementation (observed immediately before editing):**
```text
M  .serena/memories/workflow/current-phase.md
A  Docs/EAs/Grid/WorkPackages/WP-06/D-06-02_PROBE/CTO_REVIEW_HANDOFF.md
A  Docs/EAs/Grid/WorkPackages/WP-06/D-06-02_PROBE/CTO_REVIEW_HANDOFF_REMEDIATION_V3.md
A  Docs/EAs/Grid/WorkPackages/WP-06/D-06-02_PROBE/IMPLEMENTATION_REPORT.md
A  Experts/TGK/Tests/Grids/test_grid_trade_event_probe.mq5
```

**Git status after implementation/report update:**
```text
M  .serena/memories/workflow/current-phase.md
A  Docs/EAs/Grid/WorkPackages/WP-06/D-06-02_PROBE/CTO_REVIEW_HANDOFF.md
A  Docs/EAs/Grid/WorkPackages/WP-06/D-06-02_PROBE/CTO_REVIEW_HANDOFF_REMEDIATION_V3.md
AM Docs/EAs/Grid/WorkPackages/WP-06/D-06-02_PROBE/IMPLEMENTATION_REPORT.md
AM Experts/TGK/Tests/Grids/test_grid_trade_event_probe.mq5
```

- `AM` means the pre-existing staged addition remains staged and this implementation adds an unstaged modification. No staging operation was performed.
- `git diff --check` for the new unstaged changes: PASS.
- `git diff --cached --check`: still reports pre-existing trailing whitespace in `CTO_REVIEW_HANDOFF.md` lines 3–6. This file was not modified in this task and was not restaged or edited.
- No commit, push, reset, checkout, restore, clean, or stash operation was performed.

## 10. Remaining Limitations and Product Owner Next Step

1. R-03 BUY core path has passed CTO review based on the supplied Strategy Tester Journal.
2. Record the missing Environment evidence if available from the Strategy Tester configuration/account properties: exact `ACCOUNT_MARGIN_MODE` and actual Order Filling Type. Do not infer these from `Fill=3` alone.
3. `TRUE_RESTART_RECOVERY=NOT_TESTED` remains open. Same-run recovery simulation is not a true EA/Terminal restart. Product Owner decision is required on whether to create/retain a separate true-restart follow-up (e.g. WP-06E / D-06-06) and close only the minimal probe scope, or keep D-06-02 full acceptance open.
4. `FileFlush()` cannot expose a verifiable success return or OS-level crash durability through the MQL5 API; this is a documented platform limitation, not a proven durability guarantee.
5. SELL, partial-fill/multi-Deal behavior and true restart were not exercised in R-03. Do not claim those scenarios passed. Any additional Tester request requires a separately scoped run and a new unique Session ID; no automatic retry is permitted.
6. No Production EA changes, no Commit/Push, and no Git staging operation were performed as part of the R-03 review.
