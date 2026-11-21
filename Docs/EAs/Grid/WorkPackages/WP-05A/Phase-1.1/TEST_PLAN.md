# WP-05A.1 — Anchor State Model Test Plan

สถานะ: TEST PLAN อนุมัติแล้ว — รอผู้ใช้รายงาน Pre-change Grid Regression Baseline ก่อนเริ่ม Test/Implementation
Parent: WP-05A — Persistence Foundation
Implementation Card: WP-05A.1 — Anchor State Model

## 1. ความปลอดภัยของ Test

- ใช้ Unit Tests เท่านั้น
- ใช้ Reducer Instance และ In-memory `STGKGridMappingJournalRecord` Fixtures
- ห้ามใช้ `CTrade`, `OrderSend`, Trade Adapter, Live Account Scan, Demo Trade หรือ Live Trade
- ห้ามรัน Demo Integration Test เป็นส่วนหนึ่งของ Card นี้

## 2. Preconditions

- ผู้ใช้ต้องรันและรายงาน Pre-change Grid Regression Baseline ก่อน Freebuff เริ่ม Implementation
- ใช้ `Experts/TGK/Tests/Grids/test_grid_entry_mapping_reducer.mq5` เป็น Test Harness และอ้างอิง Fixture Style
- Test Cases เดิมต้องคงอยู่ เว้นแต่มีเหตุผลจำเป็นโดยตรงจาก Contract ที่อนุมัติ

## 3. Test Cases

| ID | Scenario / Preconditions | Action | Expected Result |
|---|---|---|---|
| A01 | Reducer Object ใหม่ ก่อน Initialize | เรียก `TryGetAnchorState()` | คืน false; Output มีค่าแน่นอนแต่ห้ามนำไปใช้ |
| A02 | Initialize Reducer ด้วย Symbol/Magic/Instance ที่ถูกต้อง แต่ยังไม่มี `RESET_COMMITTED` | เรียก Getter | คืน false; ยังไม่เปิดเผย Configured Anchor |
| A03 | Reducer Initialized และ Healthy จากนั้น Replay `RESET_COMMITTED` Fixture ที่ถูกต้อง | เรียก Getter | คืน true และได้ `TGK_GRID_LEVEL_READY` |
| A04 | Configured Healthy Reducer หลัง Reset สำเร็จ | เรียก Getter ซ้ำหลายครั้ง | คืน READY เหมือนเดิม; Query ไม่เปลี่ยน Sequence, Mapping หรือ Normal Level States |
| A05 | Configured Reducer ได้รับ Invalid `RESET_COMMITTED` Fixture | Replay/Apply Record ผ่าน Test Path เดิม | Record ถูก Reject และ Reducer เข้าสู่ Failure/Recovery Behavior เดิม; Getter คืน false |
| A06 | Reducer อยู่ใน Failed/Recovery Error จาก Failure Fixture ที่รองรับอยู่แล้ว | เรียก Getter | คืน false |
| A07 | ตรวจ Normal Level States หลัง `RESET_COMMITTED` | Query Anchor และ Normal Level State | Anchor เป็น READY; Expected Results ของ Normal Levels เดิมไม่เปลี่ยน |
| A08 | มี `RESET_COMMITTED` รอบที่สองที่ถูกต้อง หลังผ่าน Reset Preconditions เดิม | เรียก Getter | Anchor State กลับเป็น READY สำหรับ Configuration Epoch ใหม่ |
| A09 | รัน Reducer Existing Suite: Mapping, Partial Volume, Full Close, Unresolved Requests, Sequence, Strict Validation และ Context Queries | รัน Existing Tests ทั้งหมด | ไม่มี Regression; Expected Results เดิมยังถูกต้อง |

## 4. แนวทางการเพิ่ม Tests

- เพิ่ม Test Cases ใน `Experts/TGK/Tests/Grids/test_grid_entry_mapping_reducer.mq5` ไม่ต้องสร้าง Test EA ใหม่สำหรับ Model Change ขนาดเล็กนี้
- ใช้ Test Helpers และ Journal Record Fixture Patterns ที่มีอยู่
- ห้ามแก้ Private Member โดยตรงเพื่อบังคับ Invalid State ให้ทดสอบผ่าน Public/Replay Failure Paths ที่มีอยู่
- หากไม่สามารถสร้าง Failure State ผ่าน Public Test Path ที่รองรับได้ ให้บันทึกข้อจำกัดใน Implementation Report แทนการลด Encapsulation หรือเพิ่ม Test-only Production API
- ตรวจ Getter Output Handling ให้สอดคล้องกับ Query Conventions ของ Reducer
- ทดสอบว่า Getter ไม่เปลี่ยน `LastSequence()`, Mapping Counts หรือ Normal Level State Values เมื่อมี Query APIs ที่เกี่ยวข้อง

## 5. Regression Set

อย่างน้อยผู้ใช้ต้อง Compile/Run:

- `Experts/TGK/Tests/Grids/test_grid_entry_mapping_reducer.mq5`
- `Experts/TGK/Tests/Grids/test_grid_entry_mapping_storage.mq5`
- `Experts/TGK/Tests/Grids/test_grid_entry_mapping_snapshot.mq5`
- Grid Regression Suite ล่าสุดทั้งหมดตาม Inventory ใน `Docs/EAs/Grid/Testing/testing.md`

ต้องตรวจสอบ Test Inventory จริงอีกครั้งเมื่อเริ่ม Implementation ห้ามอ้างจำนวน Test จากเอกสารเก่าโดยไม่ตรวจสอบ

## 6. เกณฑ์ผ่าน

- A01–A09 ผ่านทั้งหมด
- Reducer / Journal / Snapshot Tests เดิม Compile และ Run โดยไม่มี Regression
- ไม่มีการส่ง Real Trade Request
- ผู้ใช้รายงานผล MetaEditor Compile และ Test อย่างชัดเจน
- ChatGPT เริ่ม Formal Code Review ได้หลังผู้ใช้รายงาน PASS เท่านั้น
