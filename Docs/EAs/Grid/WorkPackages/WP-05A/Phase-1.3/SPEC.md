# WP-05A.3 — Anchor State Persistence Integration & Hardening

**สถานะ: DRAFT — CTO Planning / Contract Design เท่านั้น**  
**Implementation: NOT AUTHORIZED**  
**Parent:** WP-05A — Persistence Foundation  
**Dependencies:** WP-05A.1 และ WP-05A.2 (Done)

## 1. วัตถุประสงค์

พิสูจน์ว่า Anchor State ที่ไม่ใช่ค่าเริ่มต้นสามารถผ่าน Canonical Persistence Path ได้ครบวงจร โดยไม่สูญหายหรือขัดแย้งกับ Anchor Position Mapping เมื่อมี Snapshot Serialization, Journal Append/Replay, Snapshot Rotation และ Restart Recovery

งานนี้เป็น Persistence Verification/Hardening เท่านั้น ไม่เพิ่ม Trading Behavior หรือ MT5 Account Integration

## 2. ขอบเขต

### In Scope

- เพิ่ม No-trade integration coverage ใน `test_grid_entry_mapping_snapshot.mq5` สำหรับ Anchor State:
  - `READY` โดยไม่มี Anchor Position Mapping
  - `ACTIVE` พร้อม Anchor Position Mapping ที่ถูกต้อง
  - `WAIT_ACTIVATION` หลัง Reason-free Full Close และไม่มี Mapping
- พิสูจน์เส้นทาง Reducer `ExportSnapshot()` → Snapshot Storage `Bootstrap()/Append()/Rotate()` → Storage restart `Initialize()/Replay()` → Reducer `RestoreSnapshot()/Replay()`
- ตรวจ Anchor State และ Mapping invariants ก่อน/หลัง Rotation และ Restart
- ตรวจ Journal checkpoint และ sequence continuity สำหรับ Anchor lifecycle records
- ตรวจ Pre-commit และ Post-commit failure/recovery ที่เกี่ยวข้องกับ Snapshot ซึ่งมี Anchor State
- แก้ Source เฉพาะเมื่อ Test ใหม่แสดง Defect ที่ทำซ้ำได้ภายใน Persistence Contract นี้

### Out of Scope

- เปลี่ยน State Transition Contract ที่อนุมัติใน WP-05A.2
- MT5 Open Positions scanning หรือ Reconciliation Adapter
- Closing Deal History, TP/NON_TP classification หรือ Close Reason
- Runtime State Restoration (WP-05B)
- `OnTradeTransaction` หรือ Production EA Event Handler
- Order Execution, Demo/Live Trading หรือ Trade Request

## 3. Technical Contract

1. `CTGKGridEntryMappingReducer` ยังคงเป็น Canonical Trading State Authority
2. `CTGKGridEntryMappingSnapshotStorage` เป็นเจ้าของ Snapshot/Journal/Manifest persistence และ Rotation เท่านั้น
3. ห้ามเพิ่ม Anchor State persistence authority อีกชุดใน `CTGKGridPersistence`
4. `ACTIVE` ต้องมี Anchor Position Mapping ที่ถูกต้องหนึ่งรายการ; `READY` และ `WAIT_ACTIVATION` ต้องไม่มี Anchor Mapping
5. Full Close ยังคงเป็น Reason-free Atomic Transition ตาม WP-05A.2
6. Snapshot ที่ไม่มี Required Anchor State หรือมี State/Mapping inconsistency ต้อง Fail Closed
7. Rotation ต้องไม่ผสม Snapshot/Journal คนละ Generation และต้องรักษา Commit Point เดิม
8. Schema ยังคง V1; ไม่เพิ่ม Migration หรือ Backward Compatibility สำหรับ Snapshot V1 รูปแบบเก่าที่ไม่มี Anchor State

## 4. ไฟล์ที่คาดว่าจะเกี่ยวข้อง

- `Experts/TGK/Tests/Grids/test_grid_entry_mapping_snapshot.mq5`
- `Experts/TGK/Tests/Grids/test_grid_entry_mapping_reducer.mq5` (เฉพาะเมื่อจำเป็น)
- `Include/BotTrade/Grid/GridEntryMappingReducer.mqh` (แก้เฉพาะเมื่อพบ Defect)
- `Include/BotTrade/Grid/GridEntryMappingSnapshotStorage.mqh` (แก้เฉพาะเมื่อพบ Defect)
- เอกสาร WP-05A ที่เกี่ยวข้อง

รายการ Allowed Files ขั้นสุดท้ายจะระบุใน Implementation Task หลัง SPEC/TEST_PLAN ได้รับอนุมัติ

## 5. Acceptance Criteria

- [ ] Anchor `READY`, `ACTIVE`, `WAIT_ACTIVATION` ผ่าน Snapshot Serialization และ Restore ได้ตรงเดิม
- [ ] Anchor Mapping และ `ACTIVE` คง Atomicity หลัง Snapshot/Rotation/Restart
- [ ] Reason-free Full Close คง `WAIT_ACTIVATION` หรือ State ที่คำนวณไว้หลัง Journal Replay/Rotation
- [ ] Journal Record หลัง Checkpoint ถูก Replay ต่อจาก N+1 โดยไม่มี Sequence ซ้ำ/หาย
- [ ] Pre-commit Failure ใช้ Generation เดิม; Post-commit Failure ใช้ Generation ใหม่และ Cleanup ซ้ำได้
- [ ] ไม่มี Snapshot/Journal generation ผสมกัน และไม่มี Partial State Mutation
- [ ] Existing no-trade Grid Regression ยังคงผ่าน
- [ ] ไม่มี Test ใดส่ง Trade Request

## 6. Implementation Gate

เอกสารนี้เป็น Draft เพื่อให้ Product Owner ตรวจ Scope/Contract เท่านั้น การ Implement ต้องรอ:
1. Product Owner อนุมัติ SPEC และ TEST_PLAN ฉบับ Final
2. ผู้ใช้รัน Latest no-trade Grid Regression Tests และรายงาน Pre-change Baseline
3. ผู้ใช้อนุมัติ WP-05A.3 Implementation อย่างชัดเจน

การ์ด Trello ที่อยู่ In Progress ในช่วงนี้หมายถึง CTO Planning เท่านั้น ไม่ใช่ Implementation Authorization
