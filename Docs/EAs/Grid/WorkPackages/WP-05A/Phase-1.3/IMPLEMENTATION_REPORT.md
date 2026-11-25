# WP-05A.3 Implementation Report

**Implementer:** Codex (initial implementation); CTO (review follow-up)
**วันที่:** 2026-11-25
**สถานะ:** CTO review findings addressed in working tree; awaiting Product Owner Compile/Runtime verification and final CTO review

## ไฟล์ที่เปลี่ยน

- `Experts/TGK/Tests/Grids/test_grid_entry_mapping_snapshot.mq5` — เพิ่ม deterministic no-trade integration coverage สำหรับ A3-01 ถึง A3-09 ตาม persistence contract; ไม่พบ defect ที่จำเป็นต้องแก้ production code
- `Docs/EAs/Grid/WorkPackages/WP-05A/Phase-1.3/IMPLEMENTATION_REPORT.md` — บันทึกผลการ implement และหลักฐาน compile แยกจาก runtime test

การแก้ไขหลัง CTO review: เพิ่ม A3-08 case ที่ส่ง `ENTRY_INTENT` ใหม่ไปยัง Anchor ซึ่งอยู่ใน `WAIT_ACTIVATION` และยืนยันว่า Reducer Replay ปฏิเสธ, เข้า `RECOVERY_ERROR` และไม่สร้าง Mapping; คง orphan `POSITION_MAPPING` case เป็นการตรวจ fail-closed เพิ่มเติม พร้อมเปลี่ยนชื่อให้ไม่สื่อว่าได้ผ่าน Request validation แล้ว. ข้อจำกัดเชิง invariant: ไม่มี legal Journal sequence ที่สามารถเตรียม accepted Request + Deal Association ไว้ล่วงหน้าแล้วค่อยปิด Anchor เป็น `WAIT_ACTIVATION` ได้ เพราะ Reducer อนุญาต Entry Intent เฉพาะ Anchor `READY` และมี unresolved-request serialization เพียงหนึ่งรายการ; หลัง Mapping Confirm แล้ว Request/Deal ถูก consume. ดังนั้น orphan Mapping test ไม่ได้อ้างว่าทดสอบ guard ภายใน `ApplyPositionMapping()` โดยตรง. เพิ่ม assertion ว่า ACTIVE mapping ถูกกู้คืนและค้นคืนได้ด้วย Anchor target (`is_anchor=true`, `level_index=-1`).

## Acceptance Criteria Evidence

| Acceptance Criterion | หลักฐานใน Test |
|---|---|
| READY, ACTIVE และ WAIT_ACTIVATION ผ่าน Snapshot/Restore | A3-01, A3-02, A3-03 ครอบคลุม Reducer Export → Storage Bootstrap → Initialize/Replay → Reducer Restore |
| ACTIVE และ Anchor Mapping คง atomicity | A3-02 และ A3-07 ตรวจ State, Mapping count, Position Identifier, Ticket และ Remaining Volume |
| Reason-free Full Close คง WAIT_ACTIVATION และไม่มี Mapping | A3-03 ตรวจหลัง Bootstrap/Restart/Restore; A3-04 และ A3-06 ตรวจเส้นทาง Activation ต่อจาก Full Close |
| Journal หลัง Checkpoint ต่อที่ N+1 | A3-04 ตรวจ checkpoint 7, activation sequence 8 และ next sequence 9; A3-05 ตรวจ checkpoint 8 และ next sequence 9 หลัง Rotation |
| Pre-commit รักษา Generation เดิม; Post-commit ใช้ Generation ใหม่และ Cleanup ซ้ำได้ | A3-06 inject failure หลัง generation validation และตรวจ Journal/Generation เดิม; A3-07 inject failure หลัง Manifest commit และตรวจ recovery จาก Generation ใหม่ |
| ไม่มี Generation ผสมหรือ Partial Anchor State | A3-05 ถึง A3-07 ตรวจ Snapshot/Journal generation, checkpoint และ Anchor invariants หลัง recovery |
| Existing no-trade Grid Regression ยังคงผ่าน | ผู้ใช้รายงานว่า test ไฟล์อื่นที่รันผ่านทั้งหมด; ไม่มีรายชื่อ/จำนวนไฟล์หรือ per-file logs แนบในข้อความรายงานล่าสุด |
| ไม่มี Trade Request จาก Test | เพิ่มเฉพาะ fake records และ isolated test storage; ไม่เรียก Trade API |

## A3-01 ถึง A3-09

| Case | Implemented | Compile | Runtime |
|---|---|---|---|
| A3-01 READY ไม่มี Mapping ผ่าน restart | Yes | User-reported PASS รอบล่าสุด | User-reported PASS รอบล่าสุด |
| A3-02 ACTIVE พร้อม Mapping เดียวผ่าน restart | Yes | User-reported PASS รอบล่าสุด | User-reported PASS รอบล่าสุด |
| A3-03 reason-free Full Close เป็น WAIT_ACTIVATION ไม่มี Mapping | Yes | User-reported PASS รอบล่าสุด | User-reported PASS รอบล่าสุด |
| A3-04 READY lifecycle record ต่อจาก checkpoint ผ่าน restart/replay | Yes | User-reported PASS รอบล่าสุด | User-reported PASS รอบล่าสุด |
| A3-05 Anchor lifecycle rotation และ restart generation ใหม่ | Yes | User-reported PASS รอบล่าสุด | User-reported PASS รอบล่าสุด |
| A3-06 pre-commit rotation failure รักษา generation ก่อนหน้า | Yes | User-reported PASS รอบล่าสุด | User-reported PASS รอบล่าสุด |
| A3-07 post-commit cleanup failure กู้ generation ใหม่และ retry cleanup | Yes | User-reported PASS รอบล่าสุด | User-reported PASS รอบล่าสุด |
| A3-08 missing/invalid/conflicting Snapshot, WAIT_ACTIVATION Entry Intent rejection และ orphan Mapping fail closed | Yes | Pending user recompile | Pending user runtime verification |
| A3-09 duplicate activation ถูกปฏิเสธโดยไม่เพิ่ม sequence/mapping; repeated rotation คง READY | Yes | User-reported PASS รอบล่าสุด | User-reported PASS รอบล่าสุด |

ไม่มีกรณีใดถูกระบุว่าไม่เกี่ยวข้อง

## Compile Evidence

- โปรแกรมที่ compile: `Experts/TGK/Tests/Grids/test_grid_entry_mapping_snapshot.mq5`
- คำสั่ง: MetaEditor64 ผ่าน Wine ตาม Verified Compile Environment ใน `AGENTS.md`; `/inc:` ชี้ repository root
- ผลจาก `/private/tmp/wp05a3_snapshot_compile.log`: `Result: 0 errors, 0 warnings` (compile รอบสุดท้าย 2026-11-25)
- Log: `/private/tmp/wp05a3_snapshot_compile.log`
- ไม่ได้แก้ `.mqh`; จึงไม่มี consumer program อื่นที่ต้อง compile
- Compile รอบก่อน self-review follow-up: `Result: 0 errors, 0 warnings` ใน log ข้างต้น; ไม่ถือเป็นหลักฐาน compile ของไฟล์ฉบับล่าสุด
- พยายาม compile หลัง self-review follow-up ด้วย MetaEditor ที่กำหนดใน `AGENTS.md` แต่ Wine แจ้ง `wine: a wine server seems to be running, but I cannot connect to it` และไม่สร้าง `/private/tmp/wp05a3_snapshot_compile_selfreview.log`; จึงยังไม่มี compile evidence ของฉบับล่าสุด
- ภายหลัง Product Owner รายงานว่า Compile และรัน Test ทั้งหมดหลัง self-review follow-up ผ่าน; ไม่มี log, จำนวน test/assertion หรือรายละเอียดรายไฟล์แนบ จึงบันทึกเป็น User-reported PASS เท่านั้น

## Runtime, Safety และข้อจำกัด

- Product Owner รายงาน runtime รอบแรก 2026-11-25: 30 tests, 24 passed, 6 failed; 528 assertions, 483 passed, 45 failed. Failures อยู่ใน A3-04 ถึง A3-09
- Root cause จาก log รอบแรก: fixtures ของ A3-04/A3-06/A3-09 และ ACTIVE Snapshot ของ A3-07 ใช้ Snapshot `Instance ID` ไม่ตรงกับ Reducer ปลายทาง ทำให้ Restore fail และ assertions หลังจากนั้นล้มตาม; A3-08 ใช้ String replacement pattern ที่ไม่ตรงตำแหน่ง field จึงไม่ได้สร้าง READY-with-Mapping Snapshot ตามเจตนา
- มี exploratory MT5 UI run ที่ Codex รายงานก่อนแก้ A3-09: 29/30 tests และ 542/548 assertions ผ่าน; 6 assertions ที่เหลือเกิดจาก negative duplicate check ทำให้ Reducer ตัวที่ใช้ export/rotation เข้า `RECOVERY_ERROR`. การรันนี้ไม่ถือเป็น Runtime Verification ตาม workflow; แยก duplicate check ไป Reducer อีก instance แล้ว และให้ Product Owner เป็นผู้ยืนยัน Runtime Test อย่างเป็นทางการ
- Product Owner รายงาน runtime rerun หลังแก้ว่า Snapshot test ผ่าน และ test ไฟล์อื่นที่รันผ่านทั้งหมด; ไม่มี per-file logs/จำนวนไฟล์แนบในข้อความรายงานล่าสุด จึงบันทึกเป็น User-reported PASS โดยไม่ระบุจำนวนเพิ่มเติม
- Product Owner รายงาน Compile/Test ทั้งหมดหลัง Codex self-review follow-up ผ่าน; ไม่ได้รับ per-file log/count จึงบันทึกเป็น User-reported PASS เท่านั้น. การแก้ไข A3-08 โดย CTO หลังจากนั้นยังต้อง Compile และ Runtime Test ใหม่
- ไม่มี Trade Request ถูกส่ง และไม่มีการเปิด/ปิด/แก้ไข position
- Compile ไม่ได้เรียก test EA; ไม่มี storage ของ real Instance หรือ user data ถูกแตะต้อง
- ไม่มี production source เปลี่ยน; ไม่พบ defect ที่ทำซ้ำได้ซึ่งต้องแก้ภายในขอบเขตนี้
- Product Owner runtime PASS reported; รายละเอียด per-file ของชุด test อื่นยังไม่ได้แนบ

## Next Step

1. Product Owner Compile `test_grid_entry_mapping_snapshot.mq5` ฉบับล่าสุดและรายงานผล/Log
2. Product Owner รัน A3-01 ถึง A3-09 และ latest no-trade Grid Regression ใหม่
3. CTO ทำ final review หลังได้รับผล PASS; WP-05A.3 ยังไม่ถือว่า APPROVED หรือปิด Card
