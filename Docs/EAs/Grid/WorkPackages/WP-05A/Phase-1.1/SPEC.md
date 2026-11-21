# WP-05A.1 — Anchor State Model

สถานะ: SPEC อนุมัติแล้ว — ยังไม่เริ่ม Implementation จนกว่าผู้ใช้จะรายงาน Pre-change Grid Regression Baseline
Parent: WP-05A — Persistence Foundation
Phase: WP-05A Phase 1 — Reducer Anchor State Model
ผู้ Implement: Freebuff
ผู้รับผิดชอบ Technical Design / Review: ChatGPT (CTO)
Product Owner / QA: ผู้ใช้

## 1. วัตถุประสงค์

เพิ่ม Anchor State แบบมีชนิดข้อมูล (typed state) เข้าไปใน `CTGKGridEntryMappingReducer` เพื่อให้ Reducer Current State สามารถเก็บ Grid Level State ของ Anchor แยกจาก Normal Level States ได้อย่างชัดเจน

Card นี้เป็นเพียง Model Foundation เท่านั้น ยังไม่ทำการเปลี่ยน Anchor State เมื่อมี Anchor Position Mapping หรือเมื่อ Anchor Position ถูกปิด การเปลี่ยน State เหล่านั้นอยู่ใน Card ถัดไป WP-05A.2

## 2. Design ที่อนุมัติแล้ว

- ใช้ `ENUM_TGK_GRID_LEVEL_STATE` ที่มีอยู่ ห้ามสร้าง Enum สำหรับ Anchor แยกต่างหาก
- ผู้รับผิดชอบ Canonical Trading State ยังคงเป็น `CTGKGridEntryMappingReducer` และ Durable Persistence Path คือ `CTGKGridEntryMappingSnapshotStorage`
- Canonical Trading State ประกอบด้วย Entry Request/Deal Associations, Position Mappings, Normal Level States และ Anchor State
- การเปลี่ยน Anchor State และ Position Mapping ที่เกิดจาก Close Event เดียวกัน ต้องเป็น Durable Logical Transition เดียวกัน
- Schema/Payload Version คงเป็น V1 โดย Official V1 Shape ฉบับปรับปรุงจะต้องมี Anchor State เป็น Required Field เมื่อทำ Snapshot ใน Card ภายหลัง
- ไม่ต้องรองรับ Migration หรือ Backward Compatibility สำหรับ V1 รูปแบบเก่าที่ไม่มี Anchor State
- หาก Snapshot ในอนาคตไม่มี Anchor State ที่จำเป็น หรือมี State ไม่ถูกต้อง ต้อง Fail Closed / Recovery Required
- State Transition Semantics ของ `GridLevelEngine` ยังคงเป็นแหล่งอ้างอิง ห้ามสร้างกฎ Transition ใหม่ใน Persistence/Reducer

## 3. ขอบเขตงาน

แก้ไขได้เฉพาะไฟล์ต่อไปนี้:

1. `Include/BotTrade/Grid/GridEntryMappingReducer.mqh`
2. `Experts/TGK/Tests/Grids/test_grid_entry_mapping_reducer.mq5`

พฤติกรรมที่ต้องทำ:

1. เพิ่ม Private Member `ENUM_TGK_GRID_LEVEL_STATE m_anchor_state` ใน Reducer
2. กำหนดค่าเริ่มต้นที่แน่นอนและปลอดภัย (`TGK_GRID_LEVEL_READY`) เมื่อ Initialize หรือ Reset In-memory Object
3. ถือว่า Anchor State พร้อมใช้งานต่อเมื่อมี `RESET_COMMITTED` ที่ถูกต้องและทำให้ Grid มี Configuration แล้วเท่านั้น (`m_config_epoch > 0)) ก่อนหน้านั้นห้ามให้ Caller เข้าใจว่าค่า Default เป็น Anchor State ของ Grid ที่ Configured แล้ว
4. เพิ่ม Public Read-only Query ตาม Contract นี้:
   `bool TryGetAnchorState(ENUM_TGK_GRID_LEVEL_STATE &state)`
   - คืน `false` หาก Reducer ยังไม่ Initialized, อยู่ในสถานะ Failed, เป็น Recovery Error หรือยังไม่มี Committed Configuration/Anchor Context
   - คืน `true` และส่ง Typed State กลับเมื่อเงื่อนไขทั้งหมดถูกต้อง
   - เมื่อคืน `false` ให้กำหนด Output เป็นค่า Default ที่แน่นอน หากสอดคล้องกับ Convention ของ Query API เดิม แต่ Caller ต้องไม่ใช้ Output เมื่อผลเป็น false
5. ตรวจสอบว่า Anchor State ที่ Reducer ถืออยู่เป็นค่าที่ถูกต้องของ `ENUM_TGK_GRID_LEVEL_STATE` เท่านั้น
6. เมื่อ `ApplyResetCommitted()` Commit Configuration Epoch ใหม่สำเร็จและสร้าง Normal Level States เสร็จแล้ว ให้กำหนด Anchor State เป็น `TGK_GRID_LEVEL_READY` ห้ามเปิดเผย Configured State ใหม่ก่อน Validation และ Allocation ที่จำเป็นผ่านครบ
7. รักษาพฤติกรรมเดิมของ Normal Level States และ Public Reducer APIs อื่นทั้งหมด

## 4. สิ่งที่อยู่นอก Scope

- ไม่เปลี่ยน Anchor State เป็น ACTIVE เมื่อเพิ่ม Anchor Position Mapping งานนี้อยู่ใน WP-05A.2
- ไม่เปลี่ยน Transition Behavior ของ `ApplyPositionMapping()`, `ApplyPositionVolume()` หรือ `ApplyPositionClosed()` ใน Card นี้
- ไม่ทำ Anchor TP/NON_TP Close Transition
- ไม่แก้ Journal Event/Record Schema, Journal Serialization, Replay Format, Checksum, Sequence หรือ Payload Version การรองรับ Journal อยู่ใน Card ถัดไป
- ไม่แก้ Snapshot Export/Restore Serialization หรือ Snapshot Payload Layout การ Persist Anchor State ใน Snapshot อยู่ใน Card ถัดไป
- ไม่แก้ `GridPersistence.mqh`, `GridEntryMappingStorage.mqh`, `GridEntryMappingSnapshotStorage.mqh`, `GridLevelEngine.mqh`, `GridLevelRuntimeCoordinator.mqh` หรือ Production EA
- ไม่ทำ Runtime State Restoration (WP-05B), Deal/Position Reconciliation (WP-05C) หรือ Production Event Integration (WP-05D)
- ไม่ทำ Migration Framework หรือ Backward Compatibility
- ไม่มี Demo/Live Trade Request, CTrade, OrderSend หรือ Account Position Interaction
- ไม่ทำ Refactor หรือ Formatting Change ที่ไม่เกี่ยวข้อง

## 5. Technical Contract

### 5.1 เงื่อนไขการอ่าน Anchor State

| สถานะ Reducer | ผลจาก TryGetAnchorState |
|---|---|
| ยังไม่ Initialized | false |
| Initialized แล้ว แต่ยังไม่มี RESET_COMMITTED | false |
| Configured, Healthy, Anchor State เป็น READY | true / READY |
| Failed หรือ Recovery Error | false |
| Configured, Healthy และเป็น Enum State ที่ถูกต้องค่าใด ๆ | true / State ที่เก็บอยู่ |

### 5.2 Initialization และ Reset

- Fresh `Initialize()` ต้องไม่ทำให้เข้าใจว่ามี Configured Anchor อยู่แล้ว
- Internal Member อาจเก็บ READY เป็น Default เพื่อให้มีค่าแน่นอน แต่ Getter ต้องยังไม่พร้อมใช้งานจนกว่า Configuration Epoch ที่ถูกต้องจะ Commit
- `RESET_COMMITTED` ที่สำเร็จจะกำหนด Anchor State เป็น READY
- Reset ที่ Invalid หรือถูก Reject ต้องไม่เปิดเผย Anchor State ที่เปลี่ยนไปเพียงบางส่วน
- Reset รอบถัดไปที่สำเร็จต้องกำหนด Anchor State กลับเป็น READY สำหรับ Configuration Epoch ใหม่ โดยต้องผ่าน Reset Preconditions เดิม

### 5.3 Enum ที่ยอมรับ

ใช้เฉพาะค่าที่มีอยู่แล้ว:

- `TGK_GRID_LEVEL_READY`
- `TGK_GRID_LEVEL_ACTIVE`
- `TGK_GRID_LEVEL_WAIT_RETURN`
- `TGK_GRID_LEVEL_WAIT_ACTIVATION`

ห้ามเพิ่ม Enum หรือเปลี่ยน Numeric Value

### 5.4 Compatibility ภายใน Card นี้

- คง `TGK_GRID_MAPPING_PAYLOAD_VERSION` เดิม
- คง Journal และ Snapshot Serialization Format เดิมใน Card นี้
- ห้ามกล่าวอ้างว่า Anchor State Durable ข้าม Restart ได้หลัง Card นี้ เพราะ Journal/Snapshot Support จะทำใน Card ภายหลัง
- ห้ามทำให้ Normal Level State Getters, Mapping Queries, Replay หรือ Snapshot Tests เดิม Regression

## 6. Dependencies

- WP-05A Contract และ Test Plan ที่ได้รับอนุมัติ
- WP-05A Implementation Plan ที่ได้รับอนุมัติ
- Phase 1 Design ที่ได้รับอนุมัติและแบ่งเป็น:
  - WP-05A.1 Anchor State Model (Card นี้)
  - WP-05A.2 Anchor State Transitions (Card ถัดไป)
- Reducer ปัจจุบันและ Grid Level State Definitions
- ต้องมีผล Pre-change Grid Regression Baseline ที่ผู้ใช้รายงานก่อน Freebuff เริ่ม Implementation

## 7. Acceptance Criteria

- AC-01: Reducer มี Typed Anchor State Member อย่างชัดเจน
- AC-02: Fresh Initialize ยังไม่เปิดเผย Configured Anchor State
- AC-03: RESET_COMMITTED ที่สำเร็จทำให้ Getter คืน Anchor State เป็น READY
- AC-04: Reducer ที่ Failed / Invalid / ยังไม่ Configured ต้องไม่คืน Anchor State ว่าใช้งานได้
- AC-05: Getter เป็น Read-only และคืน Typed Enum
- AC-06: ยอมรับเฉพาะค่าที่ถูกต้องของ Grid Level State Enum เดิม
- AC-07: Normal Level State และ Reducer Behavior เดิมไม่ Regression
- AC-08: Journal และ Snapshot Wire Format/Version ไม่เปลี่ยนใน Card นี้
- AC-09: Unit Tests ใช้ In-memory/Fake Records เท่านั้น ไม่มี Trade Request
- AC-10: ผู้ใช้รายงานผล MetaEditor Compile และ Test ก่อนเริ่ม Formal CTO Code Review

## 8. คำสั่งสำหรับ Developer

- อ่าน `AGENTS.md` ก่อน จากนั้นอ่าน `SPEC.md` และ `TEST_PLAN.md` ของ Card นี้
- ทำงานกับไฟล์ใน Repository โดยตรง ไม่จำเป็นต้องติดตั้งหรือใช้ Serena MCP
- Implement เฉพาะ Scope ของ Card นี้ หากพบว่าจำเป็นต้องแก้ไฟล์นอก Scope หรือเปลี่ยน Contract ให้หยุดและรายงาน Dependency ก่อน ห้ามขยาย Scope เอง
- ห้าม Commit หรือ Push
- บันทึกไฟล์ที่แก้, สรุป Implementation, Tests ที่รัน/ไม่ได้รัน, ผลลัพธ์จริง และปัญหาคงค้างใน `IMPLEMENTATION_REPORT.md`
- ห้ามย้าย Card ไป Code Review เมื่อ Implement เสร็จให้ย้ายไป `MT5 Testing` ซึ่งเป็น User Verification Stage ที่ตกลงใช้บน Board นี้ แล้วรอผล Compile/Test จากผู้ใช้
- ChatGPT จะเริ่ม Formal Code Review หลังผู้ใช้รายงาน Compile/Test PASS เท่านั้น

## 9. สิ่งที่ต้องส่งมอบเมื่อเสร็จ

- รายชื่อไฟล์ที่เปลี่ยนทั้งหมด
- สรุป Anchor State Member, Initialization/Reset Semantics และ Getter Behavior
- Test IDs ที่เพิ่ม/แก้และผลทดสอบที่แน่นอน
- ยืนยันชัดเจนว่าไม่ได้แก้ Journal/Snapshot Serialization และ Trade Execution
- รายงาน Deviation หรือ Blocker (ถ้ามี)
