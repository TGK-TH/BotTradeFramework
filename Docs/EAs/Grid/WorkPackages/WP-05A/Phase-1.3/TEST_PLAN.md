# WP-05A.3 — Test Plan

**สถานะ: APPROVED สำหรับ Design/Scope 2026-11-25 — Implementation ยัง NOT AUTHORIZED**
**Test Type:** No-trade Reducer / Snapshot Storage Integration

## 1. Preconditions

- WP-05A.1 และ WP-05A.2 ต้องคงสถานะ Done / CTO APPROVED
- ผู้ใช้รายงานเมื่อ 2026-11-25 ว่ารัน Test ปัจจุบันแล้วผ่านทั้งหมด; ใช้เป็น Pre-change Baseline ที่ผู้ใช้รายงานสำหรับ WP-05A.3 (ไม่มี per-file log แนบในเอกสารนี้)
- Implementation ยังต้องได้รับ Explicit Product Owner Authorization แยกจาก Design/Scope Approval
- ใช้ Test Instance ID แยกสำหรับแต่ละ Scenario และ Cleanup เฉพาะ Storage Files ของ Test Instance นั้น
- ใช้ Fake Journal Records / Deterministic Fixtures
- ห้ามเรียก CTrade, OrderSend, PositionClose หรือส่ง Trade Request

## 2. Test Cases

| ID | Scenario | Expected Result |
|---|---|---|
| A3-01 | Reducer ที่ Anchor = READY ไม่มี Mapping ถูก Export เป็น Snapshot แล้ว Restore ผ่าน Storage | Anchor ยังคง READY และไม่มี Anchor Mapping |
| A3-02 | Anchor Mapping ถูก Confirm และ Anchor = ACTIVE ก่อน Export/Bootstrap/Restart | Anchor ยังคง ACTIVE และ Mapping เดิม (Position Identifier, Ticket, Volume, Target) ครบถ้วน |
| A3-03 | Anchor Full Close เป็น Reason-free และได้ WAIT_ACTIVATION ก่อน Snapshot/Rotation | Restore แล้ว Anchor ยังคง WAIT_ACTIVATION และไม่มี Mapping |
| A3-04 | Append `ANCHOR_STATE|READY` หลัง Checkpoint แล้ว Restart/Replay | Anchor กลับเป็น READY; Sequence และ Mapping Invariant ถูกต้อง |
| A3-05 | Anchor-bearing Snapshot ผ่าน Rotation สำเร็จ | Generation ใหม่ Commit; Restore ได้ State เดิม; Journal ต่อจาก Checkpoint + 1 |
| A3-06 | Pre-commit Rotation Failure กับ Anchor-bearing State | Generation เดิมยังเป็น Authority; State ไม่เปลี่ยน; Recovery ทำงานตาม Contract |
| A3-07 | Post-commit / Cleanup Failure หลัง Anchor-bearing Rotation | Generation ใหม่เป็น Authority; Restart ทำ Cleanup ซ้ำได้; Anchor State ไม่สูญหาย |
| A3-08 | Snapshot/Journal มี Anchor State หรือ Mapping ไม่ถูกต้อง / ขาด Required Field | Restore/Replay ปฏิเสธและเข้า RECOVERY_ERROR; ห้าม Activate Runtime |
| A3-09 | Replay/Rotation ซ้ำหลัง Anchor Full Close หรือ Activation | ไม่สร้าง Mapping ซ้ำ ไม่เปลี่ยน State ซ้ำ และไม่ข้าม Journal Sequence |

## 3. Assertions ที่ต้องมี

- Anchor State ก่อนและหลังทุก Persistence Boundary
- จำนวน Anchor Mapping และ Position Identifier
- Position Ticket และ Remaining Volume
- Reducer Recovery Status
- Snapshot Checkpoint, Last Sequence และ Next Sequence
- Active Manifest / Snapshot / Journal Generation
- Storage Files หลัง Cleanup
- Previous valid generation ยังอยู่เมื่อ Commit ไม่สำเร็จ

## 4. Regression

- Compile และ Run `test_grid_entry_mapping_snapshot.mq5`
- Compile และ Run `test_grid_entry_mapping_reducer.mq5` หากมีการแก้
- Compile/Run Latest no-trade Grid Regression suite ทั้งชุด
- แยกผล Demo Test EA ที่ส่ง Trade Request ออกจาก No-trade Regression; ไม่รวมใน WP นี้

## 5. Safety

- Test ใช้ Fake Records และ Storage Test Namespace เท่านั้น
- ไม่มี Account Position Scan
- ไม่มี Deal History Access
- ไม่มี Trade Request ทุกชนิด
- ห้าม Cleanup Storage ของ Instance จริงหรือ User Data

## 6. Evidence

ผู้ใช้รายงานผล Compile/Run จาก MetaEditor/MT5 แยกตามไฟล์และ Test ID; Freebuff รายงาน Compile 0 errors / 0 warnings แยกจาก Runtime Test Evidence
