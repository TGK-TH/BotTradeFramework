# D-06-02 — CTO Review Handoff (Antigravity Remediation)

วันที่: 2026-11-28  
สถานะ: **REVIEW REJECTED — Remediation required before any Strategy Tester execution**  
ผู้รับผิดชอบ: Google Antigravity (Implementer)  
ผู้ตรวจ: ChatGPT (CTO / Technical Lead)  
Product Owner / QA: ผู้ใช้

## 1. วัตถุประสงค์

แก้ไข Findings จาก CTO Code Review ของ Minimal Strategy Tester Probe ให้โค้ดมีความปลอดภัยและให้หลักฐานที่เชื่อถือได้ ก่อนอนุญาตให้เปิด Strategy Tester ในโหมดที่ส่ง Trade Request

เอกสารอ้างอิงหลัก:

- `SPEC.md`
- `TEST_PLAN.md`
- `Experts/TGK/Tests/Grids/test_grid_trade_event_probe.mq5`
- `IMPLEMENTATION_REPORT.md`
- Repository `AGENTS.md`
- Skill: `.agents/skills/tgk-implementation-self-review/SKILL.md`

**ห้ามตีความ Handoff นี้ว่าเป็นการอนุมัติให้รัน Strategy Tester หรือส่ง Trade Request**

## 2. สถานะและข้อจำกัดที่ต้องรักษา

- Implementer ที่ได้รับมอบหมายคือ **Google Antigravity** ไม่ใช่ Freebuff
- ผู้ใช้รายงานว่า Source Compile ผ่านแล้ว แต่ CTO Review ยังไม่ผ่าน
- Source และ Implementation Report ปัจจุบันถูก Stage ไว้แล้ว ห้าม Unstage หรือเปลี่ยน staging state
- ห้าม Commit / Push
- ห้ามแก้ Production Grid files หรือ WP-06B Production implementation
- ห้ามแก้ SPEC/TEST_PLAN เว้นแต่พบความขัดแย้งที่จำเป็นจริง ๆ; หากจำเป็นให้หยุดและรายงานเหตุผลก่อน
- Scope การแก้ไขหลักจำกัดอยู่ที่:
  - `Experts/TGK/Tests/Grids/test_grid_trade_event_probe.mq5`
  - `Docs/EAs/Grid/WorkPackages/WP-06/D-06-02_PROBE/IMPLEMENTATION_REPORT.md`
  - ไฟล์ Handoff นี้เป็นข้อกำหนด ไม่ใช่ไฟล์ที่ต้องแก้
- Preserve staged, unstaged และ untracked changes ทั้งหมด
- ห้ามรัน Strategy Tester, ห้ามเปิด `EnableTestTrade`, ห้ามส่ง Trade Request, ห้าม Close/Modify Position
- ห้ามอ้างว่า True EA/Terminal Restart ผ่านจาก same-run simulation

ก่อนเริ่ม ให้ตรวจ `git status` และ diff เพื่อทำความเข้าใจสถานะเดิม และบันทึกไฟล์ที่อยู่ใน staged/unstaged/untracked โดยไม่เปลี่ยนสถานะเหล่านั้น

## 3. Findings ที่ต้องแก้ (Critical)

### CR-01 — Persistence ต้องรับประกันการเขียนและ Flush

บริเวณฟังก์ชัน `PersistState()`

ปัญหา:
- ไม่ตรวจผลการเขียน `FileWriteString()` อย่างครบถ้วน
- ไม่มีการยืนยัน `FileFlush()` ก่อนรายงานว่า Persist สำเร็จ
- Contract กำหนดให้ `REQUEST_STARTED` ต้องถูก Persist และ Flush ก่อนเรียก Trade Request

สิ่งที่ต้องทำ:
1. ตรวจผลการเขียนทุกส่วนของ Record รวมถึง delimiter/newline ที่ใช้จริง
2. เรียก `FileFlush()` หลังเขียน Record และตรวจผลตาม API contract ของ MQL5
3. คืนค่า success เฉพาะเมื่อ open/write/flush/close (ตามรูปแบบการจัดการไฟล์ที่เลือก) สำเร็จครบ
4. ถ้าเขียนหรือ Flush ไม่สำเร็จ ต้องไม่ส่ง Trade Request
5. หากเขียน Order Ticket หลัง Request ไม่สำเร็จ ให้จัดเป็น **AMBIGUOUS EXECUTION** และหยุดทันที ห้าม Retry
6. อย่ากล่าวอ้างว่า Flush เท่ากับรับประกันความทนทานต่อทุกกรณีของ OS/Terminal; ระบุขอบเขตตามความหมายของ MQL5 API

Acceptance:
- `REQUEST_STARTED` จะถูกยืนยันว่าบันทึกสำเร็จก่อน Request เท่านั้น
- Persistence failure ทุกจุดต้องปิดทางการส่ง Request หรือหยุดการทำงานตามสถานะที่ปลอดภัย
- ไม่มี automatic retry

### CR-02 — Existing Session ที่อ่านไม่ได้/ผิดรูปแบบต้อง Fail Closed

บริเวณ `LoadPersistedRecord()` และ Logic ตรวจ Session ก่อนส่ง Request

ปัญหา:
- ต้องแยกกรณีไม่มี Session File จริง ออกจากกรณีไฟล์มีอยู่แต่เปิด/อ่านไม่ได้, format ผิด, field ไม่ครบ หรือ checksum/ข้อมูลไม่สมเหตุสมผล
- ห้าม treat corrupted/unreadable record เป็น fresh session เพราะอาจทำให้ Request ซ้ำ

สิ่งที่ต้องทำ:
1. ออกแบบผลลัพธ์แบบแยกสถานะอย่างชัดเจน เช่น `NOT_FOUND`, `VALID`, `CORRUPT`, `IO_ERROR` (ใช้ enum/struct ที่เหมาะกับโค้ด)
2. อนุญาตเริ่ม Session ใหม่ได้เฉพาะเมื่อพิสูจน์ได้ว่าไม่มีไฟล์/Record สำหรับ Session นั้นจริง
3. Record ที่ format version ไม่รองรับ, Session ID ไม่ตรง, field หาย, Ticket parse ไม่ได้, state ไม่รู้จัก หรือข้อมูลขัดแย้ง ต้อง Fail Closed
4. ห้ามเขียนทับ Record ที่อ่านไม่ได้เพื่อเริ่มใหม่
5. `REQUEST_STARTED` ที่ไม่มี durable Order Ticket ต้อง Fail Closed และห้ามส่ง Request ซ้ำ
6. ตรวจการเลือก File Flags/Shared/Common path ให้สอดคล้องกับ Session identity และ Scope ที่ SPEC กำหนด

Acceptance:
- Existing but invalid/unreadable session never becomes a new session
- Only proven NOT_FOUND can proceed as fresh session
- No duplicate Trade Request from corrupted or ambiguous persistence

### CR-03 — Acceptance Criteria ต้องสะท้อนหลักฐานจริง

บริเวณ `EmitFinalSummary()`

ปัญหา:
- หลาย AC ถูกพิมพ์เป็น PASS จากเงื่อนไขเพียงว่า Request ถูกส่งแล้ว
- การมี Request ไม่ได้พิสูจน์ว่า History selection, Deal enumeration, property reads หรือ Position correlation สำเร็จ

สิ่งที่ต้องทำ:
1. สร้างผลลัพธ์เชิงหลักฐานแยกจากกัน เช่น:
   - `PASS`: เงื่อนไขผ่านครบและมีหลักฐาน
   - `FAIL`: มีหลักฐานขัดแย้ง/ไม่ผ่าน
   - `INCOMPLETE` หรือ `NOT_OBSERVED`: ไม่มีหลักฐานพอ
   - `NOT_APPLICABLE`: ไม่เกี่ยวกับ execution path นั้น
2. AC-05 ต้องไม่รายงาน PASS หาก callback buffer overflow เกิดขึ้นโดยทำให้ callback evidence สูญหาย; ให้ระบุจำนวนและผลกระทบ
3. AC-06 ต้องอ้างผล immediate History selection/read จริง ไม่ใช่เพียงมี Request
4. AC-07/08 ต้องผ่านเมื่อ exact Order selection, History scan completion และ exact `DEAL_ORDER` filtering ผ่านจริงเท่านั้น
5. AC-09 ต้องผ่านเมื่อ required Deal properties อ่านได้ครบทุก Deal ที่นำมาสรุป
6. AC-10 ต้องผ่านเมื่อ aggregate volume, Position Identifier set และ live Position snapshot ผ่าน validation/correlation จริง
7. AC-11 ต้องผ่านเมื่อ persisted-state reload และ second scan complete และผลเทียบกันตรงกัน
8. AC-12 ให้คง `TRUE_RESTART_RECOVERY=NOT_TESTED`; ห้ามนับเป็นการพิสูจน์ Restart
9. AC-13/14/15/16 ต้องรายงานตามสิ่งที่ implementation ทำและตรวจยืนยันได้ ห้าม hardcode PASS หากไม่มี verification path
10. ถ้า scan ไม่ complete หรือ evidence ขาด ให้ verdict เป็น INCOMPLETE/NOT_OBSERVED ไม่ใช่ PASS

Acceptance:
- ไม่มี AC ที่ขึ้น PASS เพียงเพราะ `g_trade_sent == true`
- ทุก PASS ผูกกับ flag/ผลตรวจที่ตรงกับ AC นั้น
- Summary แสดง failure/incomplete reason อย่างอ่านย้อนกลับได้

### CR-04 — Deal Evidence ต้อง Validate ครบก่อน Aggregate/Pass

บริเวณ `AggregateScanResults()` และการอ่าน Deal properties

ปัญหา:
- มีการอ่าน Deal fields หลายตัว แต่ยังไม่ใช้สถานะ `all_props_ok` เป็น gate ที่เข้มงวด
- ต้องยืนยันว่า Deal ที่นำมานับเป็นหลักฐานตรงกับ Request จริง

Required validation ต่อ Deal:
- `DEAL_TICKET` เป็น Ticket ที่เลือกอยู่จริงและไม่เป็นศูนย์
- `DEAL_ORDER` เท่ากับ exact Order Ticket ที่กำลังตรวจ
- `DEAL_ENTRY` เป็น Entry semantics ที่ Probe รองรับและสอดคล้องกับการเพิ่ม Exposure
- `DEAL_TYPE` ตรงกับ BUY/SELL direction ที่ส่ง
- `DEAL_SYMBOL` ตรงกับ `_Symbol`
- `DEAL_MAGIC` ตรงกับ `ProbeMagic`
- `DEAL_POSITION_ID` ไม่เป็นศูนย์
- `DEAL_VOLUME` เป็นบวกและอยู่ในขอบเขตที่สมเหตุสมผล
- `DEAL_PRICE` เป็นค่าที่อ่านได้และสมเหตุสมผล

สิ่งที่ต้องทำ:
1. ถ้าอ่าน Required Property ตัวใดไม่ได้ ให้ Deal evidence เป็น incomplete/invalid; ห้ามนับเป็น valid Deal
2. ถ้า field ใดขัดกับ Request ให้บันทึก conflict และ Fail Closed/FAIL ตาม SPEC
3. แยกผล `History scan complete but zero matching deals` ออกจาก `History scan/property read failed`
4. Aggregate เฉพาะ Deal ที่ผ่าน validation ครบ
5. ตรวจ aggregate volume เทียบ Requested Volume ด้วย Symbol Volume Step/precision ที่ถูกต้อง
6. ตรวจ distinct Position Identifier count; มากกว่าหนึ่งต้องถูกระบุเป็น architecture-contract conflict / fail closed ตาม SPEC ไม่ใช่ปกปิดด้วยการเลือกตัวแรก
7. ตรวจ `ResultDeal()` เป็นเพียง hint: ถ้าไม่พบใน exact-order enumeration ให้รายงาน discrepancy ไม่ใช่ใช้แทน enumeration

Acceptance:
- Missing property never silently contributes to a PASS aggregate
- Wrong Symbol/Magic/Direction/Entry/Order association is surfaced as conflict
- Incomplete History access is never interpreted as proof of no fill

### CR-05 — Exact-Order Scan ต้องแยก Scan Failure จาก Zero Deals

บริเวณ `RunExactOrderScan()`

สิ่งที่ต้องทำ:
1. ส่งคืนสถานะ Scan ที่ชัดเจนพร้อมข้อมูลจำนวน Deal เช่น `COMPLETE_WITH_MATCHES`, `COMPLETE_EMPTY`, `INCOMPLETE`, `INVALID_ORDER` (ปรับชื่อให้เหมาะกับ implementation)
2. ตรวจผล `HistorySelectByPosition` / `HistoryOrderSelect` / `HistoryDealSelect` หรือ API ที่เลือกใช้ตาม semantics ที่ถูกต้องของ MQL5
3. ตรวจ property access ทุกครั้ง ไม่ถือว่าการเลือก History สำเร็จแปลว่าอ่านทุก Property สำเร็จ
4. ตรวจ exact `DEAL_ORDER == OrderTicket` ทุก Deal ก่อนนับ
5. ถ้าการ enumerate/อ่านข้อมูลล้มเหลวระหว่างทาง ให้ Scan เป็น INCOMPLETE แม้จะพบ Deal บางรายการแล้ว
6. ห้ามคืนค่าเพียง integer count ที่ทำให้ caller แยก zero-result กับ failed scan ไม่ได้

Acceptance:
- Caller can distinguish complete empty result from incomplete/failed scan
- No downstream PASS or no-fill conclusion from an incomplete scan

## 4. Findings ระดับ Major ที่ต้องแก้ในรอบเดียวกัน

### MR-01 — Deal Buffer Capacity

บริเวณ Exact Order Deal enumeration / Deal buffer

- หาก Deal Buffer เต็ม ห้ามเพียง Log แล้วดำเนินการต่อเสมือน scan complete
- Mark scan as `INCOMPLETE/CAPACITY_EXCEEDED`
- บันทึก capacity, จำนวนที่พบ, จำนวนที่เก็บได้ และผลกระทบ
- ห้าม truncate evidence แล้วรายงาน aggregate เป็น PASS

### MR-02 — Position Snapshot ต้องครอบคลุมทุก Position ที่ตรงเงื่อนไข

บริเวณ `CapturePositionSnapshot()`

- ปัจจุบันเก็บเฉพาะ Position แรกที่พบ
- ให้ enumerate ทุก Position ที่ตรง exact Symbol + Magic
- บันทึก ticket, identifier, volume, open price และจำนวนรวม
- ตรวจว่าจำนวน Position/Identifier สอดคล้องกับ Deal evidence ตาม Hedging semantics
- หากพบหลาย Position หรือหลาย Identifier ให้รายงานอย่างชัดเจน ไม่เลือกตัวแรกแล้วละทิ้งส่วนที่เหลือ
- ถ้า Position enumeration/property access ไม่ครบ ให้ snapshot เป็น INCOMPLETE

### MR-03 — Callback Evidence ต้อง Log Field ที่ SPEC ต้องการ

บริเวณ `OnTradeTransaction()`, callback struct และ `EmitFinalSummary()`

- ตรวจ field ที่ capture เทียบ SPEC และ MQL5 `MqlTradeTransaction` / `MqlTradeRequest` / `MqlTradeResult`
- อย่างน้อยให้มีข้อมูลที่จำเป็นต่อการวิเคราะห์ callback ordering และ association:
  - transaction type / sequence
  - order ticket, order type, order state
  - deal ticket, deal type
  - position / position-by identifier ตามที่ API ส่งมา
  - symbol, volume, price, price trigger (ถ้ามี)
  - request action/type/volume/price/symbol/magic ที่เกี่ยวข้อง
  - result retcode, order, deal, volume, price, bid/ask ตาม field ที่ใช้ได้
  - immediate History select/read outcome สำหรับ DEAL_ADD
- แสดง unavailable/not-applicable ให้ชัดเจน อย่าแปลงเป็นค่าที่ดูเหมือน valid
- Callback ต้องคง bounded และ lightweight: ห้ามทำ Reducer mutation, File I/O, หรือ long History scan ใน callback

### MR-04 — 64-bit Ticket/Identifier Serialization

- หลีกเลี่ยง conversion ผ่าน `double` โดยเด็ดขาด
- ตรวจว่า conversion ผ่าน signed `long` ไม่ทำให้ `ulong` ที่เกินขอบเขต signed long เสียค่า
- ใช้ decimal-string serialization/parsing ที่ round-trip ได้ตามช่วงที่ระบบต้องรองรับ
- ตรวจ empty, non-digit, overflow, zero และ leading/format edge cases
- เพิ่ม diagnostic เมื่อ Ticket ไม่สามารถ serialize/parse ได้แบบ lossless
- ถ้า MQL5 type/API มีขอบเขตที่ไม่สามารถรองรับเต็ม ulong ให้ระบุข้อจำกัดและ Fail Closed เมื่อเกินขอบเขต แทนการ truncate

## 5. Test / Self-Review Requirements

ก่อนส่งกลับ:
1. อ่าน `AGENTS.md` และ `.agents/skills/tgk-implementation-self-review/SKILL.md` ให้ครบ
2. อ่าน SPEC และ TEST_PLAN
3. Map CR-01..CR-05 และ MR-01..MR-04 เข้ากับ Test Plan cases P-01..P-33
4. เพิ่ม/ปรับ Unit-level testability หรือ deterministic helper checks เท่าที่ทำได้โดยไม่ส่ง Trade Request
5. ห้ามเปลี่ยน Unit Tests เดิมให้ส่ง Trade Request
6. ตรวจ MQL5 API signatures/semantics จากเอกสารอ้างอิงที่มีใน SPEC หรือ official MQL5 documentation
7. ทำ Static Self-Review:
   - every persistence path checked
   - every History selection/property read checked
   - no false PASS paths
   - no unbounded callback work
   - no retry
   - no close/modify
   - no Production source changes
8. Update Implementation Report:
   - Implementer: Google Antigravity (ระบุ model/version เฉพาะเมื่อทราบจริง)
   - changed files
   - CR/MR disposition
   - compile result ตามหลักฐานจริงเท่านั้น
   - known limitations
   - ยืนยันว่าไม่มี Tester execution/Trade Request เกิดขึ้น
9. ตรวจ `git diff --check` และตรวจ diff เฉพาะไฟล์ที่แก้
10. รักษา Git staging state เดิม ห้าม stage/unstage/commit/push

## 6. Compile และ Execution Gates

หลัง Remediation:

**Gate A — Antigravity self-review**
- ทุก CR/MR addressed หรือมีเหตุผลทางเทคนิคที่ชัดเจนและรายงานให้ CTO
- Implementation Report ถูกต้อง

**Gate B — User Compile**
- ผู้ใช้ Compile ใน MetaEditor
- เป้าหมาย: 0 errors, 0 warnings
- หากมี error/warning ให้แก้ก่อน CTO Final Review

**Gate C — CTO Re-review**
- ส่ง Source + Report + diff + Compile result ให้ CTO
- CTO ตรวจซ้ำทั้งหมด
- Handoff นี้ไม่ได้อนุมัติ Gate D

**Gate D — Separate Product Owner authorization**
- ต้องได้รับอนุมัติอย่างชัดเจนก่อนเปิด Strategy Tester โดย `EnableTestTrade=true`
- ต้องยืนยัน no-trade Grid Regression baseline PASS ล่าสุดก่อน
- หากยังไม่มี baseline result ให้หยุดและขอผลจาก Product Owner
- รันเฉพาะ Strategy Tester configuration ที่อนุมัติ
- ห้าม Demo/Live
- Probe ส่งได้ไม่เกินหนึ่ง Market Request ต่อ unique Session ตาม Safety Contract
- ไม่มี Retry และไม่มี Close/Modify Request

## 7. Definition of Done สำหรับ Remediation

- [ ] CR-01 Persistence write/flush verified
- [ ] CR-02 Missing vs corrupt/unreadable Session distinguished; fail closed
- [ ] CR-03 Acceptance statuses evidence-based; no false PASS
- [ ] CR-04 Full Deal validation enforced before aggregation
- [ ] CR-05 Scan complete/empty/incomplete statuses distinguished
- [ ] MR-01 Buffer overflow/capacity reported as incomplete
- [ ] MR-02 Full matching Position snapshot captured
- [ ] MR-03 Required callback evidence captured and logged
- [ ] MR-04 Ticket/identifier serialization round-trip and overflow behavior validated
- [ ] Implementation Report corrected to Google Antigravity
- [ ] No Production source changed
- [ ] No Trade Request / Strategy Tester execution performed
- [ ] Git staged/unstaged/untracked state preserved
- [ ] User Compile PASS (0 errors, 0 warnings) reported
- [ ] CTO Re-review PASS

**Final status after this handoff: NOT AUTHORIZED FOR STRATEGY TESTER EXECUTION.**

## 8. Response Format เมื่อส่งงานกลับ

ให้ Antigravity ส่งกลับ:
1. Summary ของการแก้ไขแต่ละ CR/MR
2. Changed files เท่านั้น พร้อมเหตุผล
3. Mapping Finding → Function/Code location → Test Plan case
4. Self-review checklist และผล
5. Compile status: `NOT_RUN_BY_ANTIGRAVITY` หากไม่มี MetaEditor compile จริง
6. ยืนยันว่าไม่ได้รัน Strategy Tester และไม่ได้ส่ง Trade Request
7. Git status ก่อน/หลัง และยืนยันว่าไม่เปลี่ยน staging state
8. Open risks / limitations

อย่าเริ่ม Gate D หรือเปลี่ยน `EnableTestTrade` เป็น true
