# D-06-02 — CTO Review Handoff (Remediation v3)

อัปเดต: 2026-11-28
ผู้รับงาน: Google Antigravity (Implementer เดิม)
สถานะ: **CHANGES REQUESTED — ห้ามรัน Strategy Tester จนกว่า CTO Review จะ APPROVE และ Product Owner อนุมัติ Gate D แยกต่างหาก**

เอกสารนี้เป็น Handoff รอบถัดไปหลัง CTO Re-review Remediation v2 ซึ่งยังไม่ผ่าน ให้แก้เฉพาะ Findings ที่ยังเปิดอยู่ และตรวจ regression ของ CR-01..CR-05 / MR-01..MR-04 ที่แก้ในรอบก่อนด้วย

---

## 1. เป้าหมาย

ปิดช่องโหว่ที่เหลือใน Probe เพื่อให้ผล Strategy Tester มีความน่าเชื่อถือ โดยเฉพาะ:
1. Session persistence/parser ต้องไม่ยอมรับข้อมูลที่เขียนไม่ครบหรือผิดรูปแบบ
2. Deal และ Position evidence ต้องเชื่อมโยงกันจากข้อมูลที่ผ่าน Validation จริงเท่านั้น
3. History/Position enumeration ที่อ่านรายการไม่ได้ต้องไม่ถูกตีความเป็น Scan/Snapshot ที่สมบูรณ์
4. Implementation Report ต้องตรงกับ Source, Git status และหลักฐาน Compile จริง
5. Self-review ต้องตรวจเชิงลบ/เชิง adversarial ไม่ใช่เพียงติ๊ก checklist ตามสิ่งที่ผู้ implement ตั้งใจทำ

ห้ามเปลี่ยน Product/Trading Contract หรือขยาย Scope เอง หากพบว่าต้องแก้ SPEC/TEST_PLAN หรือเปลี่ยนพฤติกรรม ให้หยุดและรายงาน CTO/PO ก่อน

## 2. ขอบเขตและข้อจำกัด

### ไฟล์ที่อนุญาตให้แก้
- Experts/TGK/Tests/Grids/test_grid_trade_event_probe.mq5
- Docs/EAs/Grid/WorkPackages/WP-06/D-06-02_PROBE/IMPLEMENTATION_REPORT.md

### ไฟล์อ้างอิงที่ต้องอ่าน
- AGENTS.md
- .agents/skills/tgk-implementation-self-review/SKILL.md
- .agents/skills/tgk-implementation-self-review/references/self-review-checklist.md
- .agents/skills/tgk-implementation-self-review/references/review-lessons.md
- Docs/EAs/Grid/WorkPackages/WP-06/D-06-02_PROBE/SPEC.md
- Docs/EAs/Grid/WorkPackages/WP-06/D-06-02_PROBE/TEST_PLAN.md
- Handoff ฉบับนี้

ห้ามแก้ Skill หรือ Reference files ในรอบนี้ ให้รายงานข้อเสนอปรับปรุง Skill แยกต่างหากเท่านั้น

### Git / Safety
- ตรวจ git status --short --branch ก่อนเริ่ม และบันทึก baseline staged/unstaged/untracked
- รักษา staging state และการเปลี่ยนแปลงทั้งหมด ห้าม stage, unstage, commit, push, reset, checkout, restore, clean หรือ stash
- ห้ามแก้ Production EA / Production .mqh
- ห้ามแก้ SPEC/TEST_PLAN โดยไม่ได้รับอนุมัติ
- ห้ามรัน Strategy Tester, ห้ามเปิด EnableTestTrade=true, ห้ามส่ง Trade Request, ห้าม Close/Modify
- ห้ามอ้างว่า runtime behavior ผ่านจาก Compile หรือ Static Review

## 3. Findings ที่ยังเปิดอยู่

### CR-06 — Session Parser ต้องตรวจ Record แบบ Strict และ Fail Closed

จุดตรวจหลัก: LoadPersistedRecord(), ReadKey(), PersistedRecord

ปัญหาที่พบ:
- Parser อ่านสูงสุด 20 บรรทัด แต่ไม่ตรวจว่ามีข้อมูลบรรทัดที่ 21 หรือข้อมูลส่วนเกินหลังขีดจำกัดหรือไม่
- ReadKey() คืนค่า occurrence แรก จึงไม่ตรวจ Duplicate Keys
- Numeric fields ใช้ StringToInteger() / StringToDouble() โดยไม่มี Strict Format Validation; malformed input อาจถูกแปลงเป็น 0 หรือค่าที่ไม่ตรงกับข้อความต้นฉบับ
- ORDER_SETUP_TIME ไม่ได้ถูกตรวจว่ามีและ parse ถูกต้องตาม schema/state หรือไม่
- ต้องตรวจให้แน่ใจว่า File ที่มีอยู่แต่เปิด/อ่านไม่ได้จะไม่ถูกตีความเป็น LOAD_NOT_FOUND

สิ่งที่ต้องทำ:
1. กำหนด schema ว่าแต่ละ STATE ต้องมี Key ใดบ้าง และ Key ใด optional ได้จริง
2. ตรวจจำนวนบรรทัด/ขนาด record และตรวจ extra data เกินขอบเขต; ถ้าเกินให้ LOAD_CORRUPT
3. ปฏิเสธ Duplicate Keys, missing keys, unknown keys (เว้นแต่ schema รองรับ), malformed line ที่ไม่ใช่ KEY=VALUE, empty required value และ unsupported format version
4. ตรวจ Numeric String ก่อนแปลง: grammar, overflow/range, partial parse และ suffix/prefix
5. แยก NOT_FOUND จาก IO/access/read error โดยอิง API behavior ที่ตรวจสอบแล้ว ไม่ใช่ดูเพียง Boolean จาก FileIsExist()
6. หากพิสูจน์ไม่ได้ว่า Record ถูกต้องครบถ้วน ให้ Fail Closed และห้ามส่ง Request

Acceptance:
- เฉพาะ Record ที่ถูกต้องตาม schema เท่านั้นได้ LOAD_VALID
- Duplicate/missing/extra/malformed/overflow/unsupported version ต้องได้ LOAD_CORRUPT
- File ที่มีอยู่แต่อ่านไม่ได้ต้องได้ LOAD_IO_ERROR หรือสถานะ fail-closed ที่แยกจาก NOT_FOUND
- ทุกกรณีที่ไม่ใช่ LOAD_NOT_FOUND ต้องไม่ส่ง Trade Request
- REQUEST_STARTED ที่ไม่มี durable Order Ticket ต้องไม่ retry

### CR-07 — Persistence ต้องตรวจจำนวนข้อมูลที่เขียนจริง และอธิบาย FileFlush ตาม API Contract

จุดตรวจหลัก: PersistState()

ปัญหาที่พบ:
- ปัจจุบันตรวจ FileWriteString() เพียงว่า return value ไม่เท่ากับ 0 แต่ไม่ได้ตรวจว่าเขียนครบตามจำนวนตัวอักษรที่ต้องการ
- FileFlush() ไม่มี return value ให้ตรวจโดยตรง แต่โค้ดใช้ GetLastError() หลังเรียกเพื่อสรุปผล ซึ่งต้องพิสูจน์ให้ตรงกับ API semantics และไม่ควรอ้างเป็นหลักฐาน durability ที่ API ไม่รับประกัน

สิ่งที่ต้องทำ:
1. ตรวจ MQL5 API contract ของ FileWriteString(), FileFlush(), FileClose() จากเอกสารทางการ/Reference ที่มี
2. เก็บข้อความแต่ละบรรทัดไว้ก่อนเขียน และตรวจจำนวนตัวอักษรที่ API รายงานว่าเขียน เทียบกับจำนวนที่คาดหวังตาม encoding/terminator semantics
3. เมื่อ write ไม่ครบหรือเกิด error ให้หยุดการเขียนต่อเท่าที่ทำได้, ปิด Handle อย่างปลอดภัย, คืน failure และห้ามส่ง Request หากเป็น REQUEST_STARTED
4. เรียก FileFlush() หลังเขียนครบทุกบรรทัด และบันทึกข้อจำกัดตามจริง: API เป็น void และไม่ใช่หลักฐาน OS-level fsync/hardware durability
5. อย่าใช้ GetLastError()==0 เป็นหลักฐานความสำเร็จของ Flush เว้นแต่ API contract ระบุชัด; ResetLastError ก่อน operation เพื่อไม่ให้ปน error เก่า แต่ห้ามอ้างเกิน API
6. หลัง Request หาก persist Order Ticket ไม่สำเร็จ ให้ระบุ AMBIGUOUS และไม่ retry; Session เดิมต้อง fail closed ในการเริ่มครั้งถัดไป

Acceptance:
- Write ที่ไม่ครบตาม semantics ของ API ต้องไม่คืน success
- REQUEST_STARTED อนุญาตให้ส่ง Request ได้หลัง write ครบและเรียก Flush ตาม contract แล้วเท่านั้น
- หลัง Request หากบันทึก Order Ticket ไม่สำเร็จ ต้องไม่ retry และต้องคงสถานะ ambiguous/fail-closed
- Report อธิบาย durability boundary โดยไม่กล่าวอ้างเกินความสามารถของ MQL5 File API

### CR-08 — AC-10 ต้อง Correlate กับ Valid Deal และ Valid Position เท่านั้น

จุดตรวจหลัก: EmitFinalSummary(), AggregateScanResults(), ProbeDeal, ProbePosition

ปัญหาที่พบ:
- AC-10 เปรียบเทียบ Position Identifier กับ g_deals[0] ซึ่งอาจไม่ใช่ Deal ที่ผ่าน Validation และอาจมี valid_for_aggregate=false
- AC-10 ไม่ตรวจ g_positions[0].props_ok ก่อนใช้ Identifier/Volume/Open Price เป็นหลักฐาน
- deal_count_valid > 0 อย่างเดียวไม่พอ ต้องเลือก Deal record ที่ผ่าน Validation จริง
- ต้องตรวจว่าการเปรียบเทียบครอบคลุม Deal set ทั้งหมด ไม่ใช่เพียง array element แรก

สิ่งที่ต้องทำ:
1. เก็บ/หา index ของ Deal ที่ผ่าน Validation จริง; ห้ามใช้ index 0 โดยไม่มีการตรวจ
2. ก่อน AC-10 PASS ต้องยืนยัน Scan complete, ทุก Deal ที่ใช้มี required properties ครบ, ไม่มี critical conflict, distinct Position Identifier ตาม contract และ aggregate volume ผ่าน
3. ตรวจ props_ok ของ Position ก่อนใช้ property ใด ๆ; ถ้า false ต้องเป็น INCOMPLETE
4. Correlate Position Identifier กับ valid Deal Position Identifier set และตรวจ Position count/volume ตาม SPEC
5. หาก evidence ไม่ครบหรือขัดแย้ง ให้ INCOMPLETE/FAIL ตามชนิดหลักฐาน ห้าม fallback ไปใช้ Deal ที่ไม่ valid

Acceptance:
- AC-10 PASS ได้เมื่อ Scan complete และ Deal evidence ทุกตัวที่ใช้ผ่าน Validation
- Position snapshot ต้อง complete และ Position properties ที่ใช้ต้อง props_ok=true
- Identifier/volume correlation ต้องมาจาก Valid Deal เท่านั้น
- Invalid Deal ที่อยู่ก่อน Valid Deal ใน array ต้องไม่ทำให้ correlation ผิด
- ไม่มี evidence ที่ไม่ครบถูกยกระดับเป็น PASS

### MR-05 — History Deal Enumeration: Ticket = 0 ต้องไม่ถูกข้ามแบบเงียบ ๆ

จุดตรวจหลัก: RunExactOrderScan()

ปัญหาที่พบ:
- เมื่อ HistoryDealGetTicket(i) คืน 0 โค้ดตั้ง Incomplete เฉพาะเมื่อ GetLastError()!=0; ถ้า error code เป็น 0 จะ continue และอาจสรุป Scan เป็น complete ทั้งที่ enumeration ไม่ได้คืน Ticket สำหรับ index ที่ควรอ่าน

สิ่งที่ต้องทำ:
1. ตรวจ API contract และ semantics ของ HistoryDealGetTicket(index)
2. หาก index อยู่ในช่วง 0..HistoryDealsTotal()-1 แต่ได้ Ticket 0 ให้ถือว่า enumeration มี anomaly และ Scan เป็น SCAN_INCOMPLETE เว้นแต่เอกสาร/API จะระบุชัดว่าเป็น expected condition
3. ห้ามใช้ GetLastError()==0 เพื่อเปลี่ยน missing Ticket ให้กลายเป็นหลักฐานว่า enumeration สมบูรณ์
4. Log index, total count และ error code

Acceptance:
- ทุก index ที่ประกาศว่า enumerated ต้องมี Ticket ที่อ่านได้
- Ticket 0 ในช่วง index ที่ถูกต้องทำให้ Scan ไม่ complete และห้าม AC-07/08/10 PASS

### MR-06 — Position Enumeration: Ticket = 0 ต้องทำให้ Snapshot Incomplete

จุดตรวจหลัก: CapturePositionSnapshot()

ปัญหาที่พบ:
- เมื่อ PositionGetTicket(i) คืน 0 โค้ด continue โดยไม่ตั้ง g_position_snapshot_incomplete
- Snapshot อาจรายงาน complete แม้ Position enumeration บาง index อ่าน Ticket ไม่ได้

สิ่งที่ต้องทำ:
1. ตรวจ API semantics ของ PositionGetTicket(index)
2. ถ้า index อยู่ในช่วง PositionsTotal ที่กำลังอ่านแล้วคืน Ticket 0 ให้ mark snapshot incomplete และ log index/error
3. ห้ามตีความการข้าม index ที่อ่านไม่ได้ว่าไม่มี Position ที่ตรง Symbol+Magic
4. รักษา capacity overflow และ property-read error handling

Acceptance:
- Snapshot complete ได้เมื่อ enumeration ครบทุก index และ properties ของ matching Positions ที่นำมาใช้ครบ
- Ticket 0 หรือ property-read failure ทำให้ snapshot incomplete
- AC-10 ห้าม PASS เมื่อ snapshot incomplete

### MR-07 — Implementation Report ต้องตรงกับ Git State และ Source จริง

จุดตรวจหลัก: IMPLEMENTATION_REPORT.md

ปัญหาที่พบ:
- Report ระบุว่าไม่มีการเปลี่ยน Git staging state แต่ Handoff ที่เดิมเป็น untracked ปรากฏเป็น staged ใน Git status ล่าสุด จึงไม่ควรยืนยันว่า staging state ไม่เปลี่ยนโดยไม่มี baseline
- Report มี checklist ที่ติ๊กครบ แต่ CTO พบประเด็นที่ checklist ไม่ได้ตรวจ จึงต้องเปลี่ยนจาก self-assertion เป็น evidence-backed checklist

สิ่งที่ต้องทำ:
1. แยก Git status ณ เวลารายงาน ออกจากการกระทำที่ Implementer ทำ และอย่าอ้างว่า staging state ไม่เปลี่ยนหากไม่มี before/after evidence
2. ระบุ Source, Report, Handoff และ Serena memory ว่า staged/unstaged/untracked ตาม status จริง โดยไม่แก้ staging
3. อัปเดต finding disposition ตามผลจริงของ CR-06..CR-08 / MR-05..MR-06
4. ทุก checklist item ต้องอ้าง function/line/test/evidence; หากตรวจไม่ได้ให้ NOT_VERIFIED ไม่ใช่ [x]
5. เก็บ Compile evidence ที่ผู้ใช้รายงานแยกจาก Static Self-review และห้ามอ้าง Tester runtime PASS

Acceptance:
- Report สอดคล้องกับ Source และ Git status ที่บันทึกในเวลาจัดทำ
- ไม่มี false claim ว่า staging state คงเดิมโดยไม่มีหลักฐาน
- Findings ทุกข้อมีสถานะ FIXED / NOT_FIXED / DEFERRED พร้อมตำแหน่งและ acceptance evidence
- Compile และ Tester evidence แยกจากกันชัดเจน

## 4. Regression Verification ของ Findings รอบก่อน

ห้ามถือว่า CR-01..CR-05 / MR-01..MR-04 ปิดถาวรโดยไม่ตรวจ regression ใน Source ปัจจุบัน:

| Finding | ต้องยืนยันอีกครั้ง |
|---|---|
| CR-01 | REQUEST_STARTED persist ก่อน Request; ticket persist failure = ambiguous/no retry; ตรวจ write/flush ตาม CR-07 |
| CR-02 | NOT_FOUND แยกจาก corrupt/IO; existing REQUEST_STARTED no ticket = fail closed; ตรวจ strict parser ตาม CR-06 |
| CR-03 | ทุก AC verdict มีหลักฐานตรงกับสิ่งที่วัด; ไม่มี PASS จาก request sent เพียงอย่างเดียว |
| CR-04 | Deal Order/Entry/Type/Symbol/Magic/Position ID/Volume/Price และ property completeness validate ก่อน aggregate |
| CR-05 | HistorySelect/OrderSelect/Deal property errors และ enumeration anomalies ทำให้ Scan incomplete |
| MR-01 | Deal buffer overflow ทำให้ Scan incomplete |
| MR-02 | ทุก matching Position ถูก enumerate; capacity/property/enumeration errors ไม่ถูกซ่อน |
| MR-03 | Callback เก็บและ Summary แสดง field ที่ SPEC ต้องการ; callback bounded และไม่มี full scan/file I/O |
| MR-04 | ulong decimal serialization round-trip, malformed/overflow/zero boundary behavior ถูกตรวจ |

ข้อสังเกต: ประเด็น Boolean return ของ PassesTradeGates() ที่ CTO เคยแจ้งในรอบก่อน ตอนนี้ Source ใช้ return false/true สอดคล้องกับชนิด bool แล้ว จึงไม่ใช่ Finding เปิดใน Handoff นี้ แต่ต้องตรวจ Caller/Control Flow อีกครั้งเพื่อยืนยันว่า Gate ผ่าน/ไม่ผ่านทำงานถูกต้องจริง

## 5. Mandatory Self-Review Protocol — ห้ามทำเพียงติ๊ก Checklist

ก่อนส่งกลับ ต้องทำ Self-review 2 รอบที่แยกกัน:

### Pass A — Requirement-to-Code Trace
- ทำตาราง CR-06..CR-08 / MR-05..MR-07 → Function → Exact code path → Test Plan ID → Expected evidence
- ทำตาราง regression CR-01..CR-05 / MR-01..MR-04
- Trace จาก input/API result ไปถึง state/return/verdict ทุกเส้นทาง
- ตรวจ success, failure, boundary, malformed, duplicate, overflow และ ambiguous cases
- ระบุว่าแต่ละ test ทำให้ execution ถึง invariant ที่ตั้งใจทดสอบจริงหรือไม่

### Pass B — Adversarial Review (เริ่มจากสมมติว่าโค้ดยังผิด)
ตรวจใหม่โดยไม่อาศัยคำอธิบายใน comment หรือ Implementation Report:
- อ่าน Source จริงและถามว่า "มีทางไหนที่ข้อมูลไม่ครบแต่ยังคืน success/PASS ได้?"
- ตรวจ Boolean/enum/integer return semantics และ caller interpretation
- ตรวจ API signature/return semantics/error behavior จาก MQL5 Reference; ห้ามเดาจากชื่อ
- ตรวจ GetLastError lifecycle: reset ก่อน operation, อ่านทันทีหลัง operation และไม่ใช้ error=0 เป็นหลักฐาน success หาก API ไม่รับประกัน
- ตรวจ array index, first-valid vs first-element, loop bounds, zero handles/tickets, capacity limits, stale data และ partial reads
- ตรวจ conversion/overflow/round-trip/locale/precision และ signed/unsigned boundaries
- ตรวจว่าทุก PASS มี positive evidence และทุก INCOMPLETE/FAIL path ไม่ถูกกลบด้วย fallback
- ตรวจว่า recovery simulation ไม่ถูกอธิบายเป็น true restart
- ตรวจ Source กับ Report แบบอิสระ ไม่ใช้ Report เป็นหลักฐานว่า Source ทำตามที่เขียน

### Finding Closure Matrix

สำหรับทุก Finding ให้ระบุ:
- Finding ID
- Status: FIXED / NOT_FIXED / NOT_APPLICABLE พร้อมเหตุผล
- Exact function + line range
- Code-path explanation
- Test Plan ID และ test mechanism
- Evidence/expected log or assertion
- Remaining limitation

ห้ามใช้เพียงคำว่า "แก้แล้ว" หรือ checklist [x] โดยไม่มี evidence ที่ชี้กลับไปยัง implementation/test

## 6. Compile / Execution Gates

1. Antigravity ทำ Static Self-review และอัปเดต Report
2. ผู้ใช้ Compile ใน MetaEditor ตาม AGENTS.md — เป้าหมาย 0 errors, 0 warnings
3. ส่งกลับให้ CTO Re-review
4. หาก CTO Review APPROVED จึงค่อยพิจารณา Gate D
5. ก่อน Gate D ต้องยืนยัน Fresh no-trade Grid Regression baseline PASS
6. ต้องได้รับ Product Owner อนุมัติอย่างชัดแจ้งก่อน Strategy Tester execution ที่ส่ง Market Request

ในรอบนี้ไม่มีสิทธิ์รัน Strategy Tester หรือส่ง Trade Request

## 7. Definition of Done

- CR-06..CR-08 และ MR-05..MR-07 ปิดตาม Acceptance
- CR-01..CR-05 / MR-01..MR-04 ผ่าน regression re-check
- Self-review Pass A และ Pass B เสร็จ พร้อม matrices
- Implementation Report ตรงกับ Source/Git state/Compile evidence
- Compile โดยผู้ใช้ผ่าน 0 errors, 0 warnings
- git diff --check ผ่าน
- ไม่เปลี่ยน staging state, ไม่ commit/push
- ไม่มี Tester run / Trade Request
- CTO Re-review รอบถัดไปเป็น APPROVED ก่อนขอ Gate D

## 8. รูปแบบรายงานส่งกลับ

1. Files changed
2. Git status baseline และ final พร้อมยืนยันว่าไม่มี staging operation
3. Finding Closure Matrix (CR-06..CR-08, MR-05..MR-07)
4. Regression Matrix (CR-01..CR-05, MR-01..MR-04)
5. Requirement-to-Code/Test mapping
6. Adversarial Self-review Pass B — ระบุกรณีที่พยายามหาทางทำให้โค้ดผิด/ให้ PASS ผิด และผลตรวจ
7. Compile command, exact log path, result (แยกจากผู้ใช้ Compile หาก Antigravity Compile เอง)
8. Static checks และ diff checks
9. Tests run/not run; ระบุชัดว่า Strategy Tester NOT RUN
10. Skill improvement suggestions (ไม่แก้ Skill ในรอบนี้)
11. Remaining limitations / questions

หาก API semantics หรือ SPEC ไม่ชัดจนตัดสินใจไม่ได้ ให้หยุดและถาม CTO แทนการเดา/เปลี่ยน Contract เอง
