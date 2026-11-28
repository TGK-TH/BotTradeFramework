# WP-05A.1 — Anchor State Model Implementation Report

สถานะ: User Verification PASS และ CTO Code Review APPROVED (2026-11-21)
Parent: WP-05A — Persistence Foundation
Implementation Card: WP-05A.1 — Anchor State Model
ผู้ Implement: Freebuff
วันที่ Implement: 2026-11-21

## 1. Changed Files

1. `Include/BotTrade/Grid/GridEntryMappingReducer.mqh`
2. `Experts/TGK/Tests/Grids/test_grid_entry_mapping_reducer.mq5`

ไม่มีไฟล์อื่นถูกแก้ไข ไม่มี Commit/Push

## 2. Implementation Summary

### 2.1 Anchor State Member

- เพิ่ม Private Member `ENUM_TGK_GRID_LEVEL_STATE m_anchor_state` ใน `CTGKGridEntryMappingReducer`
- ใช้ `ENUM_TGK_GRID_LEVEL_STATE` เดิม ไม่สร้าง Enum ใหม่ และไม่เปลี่ยน Numeric Value
- เพิ่ม Private Helper `IsValidGridLevelStateValue(ENUM_TGK_GRID_LEVEL_STATE)` ตรวจช่วงค่า `TGK_GRID_LEVEL_READY` ถึง `TGK_GRID_LEVEL_WAIT_ACTIVATION`

### 2.2 Initialization และ Reset Semantics

- Constructor กำหนด `m_anchor_state = TGK_GRID_LEVEL_READY` เพื่อให้มีค่าเริ่มต้นที่แน่นอน
- `Initialize()` ที่ถูกต้องกำหนด `m_anchor_state = TGK_GRID_LEVEL_READY` (ค่า Internal Default เท่านั้น ยังไม่ถือว่า Configured)
- `ApplyResetCommitted()` กำหนด `m_anchor_state = TGK_GRID_LEVEL_READY` หลัง Validation ทั้งหมดผ่าน และสร้าง Normal Level States ครบแล้วเท่านั้น (หลัง Loop สร้าง `m_levels`)
- Reset ที่ Invalid/ถูก Reject จะ Return `false` ก่อนถึงบรรทัดกำหนด Anchor State ทำให้ไม่เกิดการเปิดเผย State ที่เปลี่ยนไปเพียงบางส่วน
- Reset ครั้งถัดไปที่สำเร็จจะกำหนด Anchor State กลับเป็น `READY` สำหรับ Configuration Epoch ใหม่

### 2.3 Public Read-only Query

`bool TryGetAnchorState(ENUM_TGK_GRID_LEVEL_STATE &state)`

- กำหนด Output เป็น `TGK_GRID_LEVEL_READY` ก่อนทุกกรณี (Deterministic Default ตาม Convention ของ `TryGetPositionMapping`)
- คืน `false` เมื่อ: ยังไม่ `Initialize()`, `m_failed == true`, `m_recovery_status != TGK_GRID_MAPPING_STATUS_NORMAL`, `m_config_epoch <= 0` (ยังไม่มี Committed Configuration/Anchor Context) หรือค่า `m_anchor_state` ไม่ใช่ค่าที่ถูกต้องของ Enum
- คืน `true` พร้อม Typed State ที่เก็บอยู่เมื่อเงื่อนไขทั้งหมดถูกต้อง
- เป็น Query แบบ Read-only ไม่เปลี่ยน Sequence, Mapping หรือ Normal Level States

### 2.4 สิ่งที่ไม่ได้แก้ (ยืนยัน)

- ไม่แก้ `ExportSnapshot()`, `RestoreSnapshotInternal()`, `RestoreSnapshot()` หรือ Snapshot Payload Layout ใด ๆ — `TGK_GRID_MAPPING_PAYLOAD_VERSION` คงเป็น `v1` และ Wire Format เดิมทุกประการ
- ไม่แก้ Journal Record Schema, Journal Serialization, Replay Format, Checksum, Sequence หรือ Payload Version
- ไม่แก้ Transition Behavior ของ `ApplyPositionMapping()`, `ApplyPositionVolume()`, `ApplyPositionClosed()`, `ApplyLevelState()`
- ไม่แตะ `GridPersistence.mqh`, `GridEntryMappingStorage.mqh`, `GridEntryMappingSnapshotStorage.mqh`, `GridLevelEngine.mqh`, `GridLevelRuntimeCoordinator.mqh` หรือ Production EA
- ไม่มีการส่ง Trade Request, ไม่ใช้ `CTrade`, `OrderSend`, Trade Adapter หรือ Account Position Interaction

### 2.5 ข้อสังเกตด้าน Behavior ที่ยังไม่ Durability

หลัง Card นี้ Anchor State ยังไม่ถูก Persist ลง Snapshot หรือ Replay จาก Journal (Snapshot/Journal Support อยู่ใน Card ถัดไป) ค่า `READY` ที่ Getter คืนหลัง Restore Snapshot มาจาก Internal Default + Committed Configuration Epoch ใน Snapshot เดิม ไม่ใช่ Anchor State ที่ Persist มา — ต้องไม่กล่าวอ้างว่า Anchor State Durable ข้าม Restart ใน Card นี้

## 3. Tests Added (ตาม TEST_PLAN.md)

เพิ่ม Test Cases ใน `Experts/TGK/Tests/Grids/test_grid_entry_mapping_reducer.mq5` (Test Harness เดิม ไม่สร้าง Test EA ใหม่) รวม 4 Test Blocks:

| Test ID | Test Block | Assertions หลัก |
|---|---|---|
| A01 | `Anchor State is not exposed before a committed configuration` | Reducer ที่ยังไม่ Initialize คืน `false`; Output ถูก Reset เป็น Default `READY` (ทดสอบด้วย Poison Value `WAIT_ACTIVATION`) |
| A02 | Test Block เดียวกับ A01 | Initialize สำเร็จแต่ยังไม่มี `RESET_COMMITTED` → คืน `false`; Output เป็น Default `READY` |
| A03 | `Committed Reset exposes a READY Anchor State without changing Normal Level States` | Replay `RESET_COMMITTED` ที่ถูกต้อง → คืน `true` และได้ `TGK_GRID_LEVEL_READY` |
| A04 | Test Block เดียวกับ A03 | เรียก Getter ซ้ำ 3 ครั้ง ยังได้ `READY`; `LastSequence()`, `LevelCount()`, `PositionCount()`, `LevelStateAt(1)` ไม่เปลี่ยน |
| A05 | `Anchor State fails closed when the Reducer is invalid or unhealthy` | `RESET_COMMITTED` ที่ Level Count ไม่ตรงสูตรถูก Reject, `RecoveryStatus()` เป็น `TGK_GRID_MAPPING_STATUS_RECOVERY_ERROR`, Getter คืน `false` และ Output เป็น Default |
| A06 | Test Block เดียวกับ A05 | (1) Sequence Gap หลัง Reset ที่ Commit แล้ว → Getter คืน `false` (2) `RestoreSnapshot()` ที่ Malformed → Getter คืน `false` แม้ Configuration Epoch จะถูก Commit ก่อนหน้า |
| A07 | Test Block เดียวกับ A03 | หลัง `RESET_COMMITTED`: Anchor เป็น `READY`; Normal Level ที่ถูก Map เป็น `ACTIVE`; Level ที่ไม่ถูก Map ยังเป็น `READY`; การมี Anchor Position Mapping (ANCHOR) ไม่เปลี่ยน Anchor State (WP-05A.2) |
| A08 | `Second committed Reset re-establishes a READY Anchor State` | `RESET_COMMITTED` Epoch 2 ที่ถูกต้อง → Anchor กลับเป็น `READY`; Normal Level States ถูกสร้างใหม่ `READY`; `LevelCount()` = 200 |
| A09 | Existing Suite ทั้งหมด | ไม่แก้ Test Case เดิมแม้แต่รายการเดียว รันรวมใน Suite เดียวกัน |

หมายเหตุ: ไม่มีการแก้ Private Member โดยตรงเพื่อบังคับ Invalid State — Failure Path ทั้งหมดสร้างผ่าน Public/Replay/RestoreSnapshot Path ที่มีอยู่จริง

## 4. Tests Run / Not Run

### Run โดย Freebuff (Static เท่านั้น)

- `git diff --check` → ผ่าน (Exit Code 0, ไม่มี Whitespace Error)
- ตรวจ Diff ด้วยตาเปล่าเทียบกับ `SPEC.md` / `TEST_PLAN.md` → Scope ตรง ไม่มีไฟล์นอก Scope
- ตรวจว่า Test Inventory ยังอ้าง Test Harness เดิม `Experts/TGK/Tests/Grids/test_grid_entry_mapping_reducer.mq5`

### Not Run (ต้องให้ผู้ใช้ดำเนินการ)

- **MetaEditor Compile: ไม่ได้รัน** — ไม่มี Headless MetaEditor/Compiler Environment ที่ตรวจสอบได้บนเครื่องนี้ และตาม Working Agreement ผู้ใช้เป็นผู้รัน Compile
- **MT5 Test Execution: ไม่ได้รัน** — Test EA ต้องรันผ่าน MetaTrader 5 Terminal
- **Grid Regression Suite อื่น: ไม่ได้รัน** — `test_grid_entry_mapping_storage.mq5`, `test_grid_entry_mapping_snapshot.mq5` และ Suite อื่นตาม Inventory ใน `Docs/EAs/Grid/Testing/testing.md`

จึงยังไม่มีหลักฐาน Compile/Runtime PASS จาก Card นี้ ผลลัพธ์จริงจะถูกบันทึกหลังผู้ใช้รายงาน

## 5. Known Issues / Limitations

1. Anchor State ยังไม่ Durable ข้าม Restart (Snapshot Export/Restore ยังไม่มี Anchor State Field) — เป็น Scope ของ Card ถัดไปตามที่ SPEC กำหนด
2. Anchor State ยังไม่เปลี่ยนเป็น `ACTIVE` เมื่อมี Anchor Position Mapping และยังไม่มี Anchor Close Transition — Scope ของ WP-05A.2
3. `RestoreSnapshotInternal()` ไม่ได้กำหนด `m_anchor_state` ใหม่ เพราะ Snapshot Payload ยังไม่มี Anchor State (ห้ามแก้ Wire Format ใน Card นี้) ค่าที่ Getter เห็นหลัง Restore จึงเป็น Internal Default `READY` ที่ Gate ด้วย Committed Configuration Epoch
4. ไม่มีการทดสอบ Invalid Internal Enum Value ผ่าน Public Path ได้จริง เนื่องจากไม่มี Public API ที่เขียน Anchor State เป็นค่าอื่นได้ใน Card นี้ — Helper Validation ถูกเรียกใน Getter แล้ว แต่ Path นี้จะถูกครอบด้วย Test จริงเมื่อ WP-05A.2 เพิ่ม Transition

## 6. User Verification และ CTO Review

- ผู้ใช้รายงานเมื่อ 2026-11-21 ว่า MetaEditor Compile และรัน Tests ผ่านทั้งหมด หลังแก้ไข A06 ตาม Section 7
- CTO ตรวจ Source Diff เทียบกับ SPEC, TEST_PLAN และ WP-05A Architecture แล้วให้ผล **APPROVED**
- รายละเอียด Findings, Scope Boundary และ Review Checks อยู่ใน [CODE_REVIEW.md](CODE_REVIEW.md)
- ผู้ใช้ยืนยันปิด Card เมื่อ 2026-11-21; Trello Card ถูกย้ายไป Done และ Mark Complete แล้ว ไม่มี Commit/Push

## 7. แก้ไขหลังรอบ MT5 Testing ครั้งแรก (2026-11-21)

- ผลรอบแรก: Compile ผ่าน, รัน Test แล้ว Fail 1 รายการ — `FAIL: replay committed configuration before failed Snapshot | actual=false` (A06 ข้อ 2)
- สาเหตุ: เป็น Defect ของ Test Harness ไม่ใช่ Behavior ของ Reducer — Test เรียก `Replay(failed_anchor_records, ArraySize(failed_anchor_records) - 1)` แต่ `Replay()` ตาม Contract ปฏิเสธ `record_count` ที่ไม่เท่ากับ `ArraySize(records)` (Guard: `record_count != ArraySize(records)`) จึงคืน `false` ทุกครั้ง
- การแก้: สร้าง Array `committed_anchor_records[]` ที่มีเฉพาะ Base Configuration (2 Records, ไม่มี Record ที่ทำให้เกิด Sequence Gap) แล้วเรียก `Replay(committed_anchor_records, ArraySize(committed_anchor_records))` — ไม่แก้ Reducer และไม่แตะ Product Code
- ผลรันหลังแก้ไข: ผู้ใช้รายงานว่า A06 และ Tests ทั้งหมดผ่าน; ผลที่คาดไว้ได้รับการยืนยันจากการรันจริงของผู้ใช้
- ผู้ใช้รายงานเมื่อ 2026-11-21 ว่า Compile และ Run Tests หลังแก้ไขผ่านทั้งหมด (ผล User Verification รอบแก้ไข)
