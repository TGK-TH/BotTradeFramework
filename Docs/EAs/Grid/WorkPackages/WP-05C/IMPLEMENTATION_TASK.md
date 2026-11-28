# WP-05C — Implementation Task / Handoff

**สถานะ:** CTO Preparation Complete — พร้อมให้ Product Owner พิจารณาอนุมัติ Implementation  
**Product Scope:** อนุมัติแล้ว 2026-11-25 (ไม่เปิด Product Design ใหม่)  
**Implementation:** NOT AUTHORIZED  
**Dependencies:** WP-05A.3 และ WP-05B ปิดแล้ว  
**เอกสารอ้างอิงหลัก:** `SPEC.md`, `TEST_PLAN.md` และ Technical Contract Addendum ในเอกสารทั้งสอง

## 1. เป้าหมายของ Implementer

Implement Authoritative Open Positions Reconciliation สำหรับ Grid Runtime ที่ผ่าน WP-05B Hydration แล้ว โดยใช้ Complete/Stable Live Position Snapshot เพื่อ reconcile Durable Position Mapping, Position Ticket, Volume และ Full Close facts จาก Position Identifier

ห้ามเปลี่ยน Grid Trading Behavior, Entry Selection, Grid Geometry, Product Scope หรือ WP-05A.2 Close State Rule

## 2. Source of Truth และไฟล์ที่เกี่ยวข้อง

### Existing Source — อ่านและแก้เฉพาะเมื่อจำเป็นต่อ Contract

- `Include/BotTrade/Grid/GridPositionReconciler.mqh`
  - ปัจจุบันเป็น Reset/Close-confirmation component
  - **ห้ามเปลี่ยน semantics เดิม** ของ close-attempt/reset flow
  - Reuse ได้เฉพาะ Ownership Predicate หรือ utility ที่ไม่ทำให้ Behavior เดิมเปลี่ยน
- `Include/BotTrade/Grid/GridEntryMappingReducer.mqh`
  - Canonical Mapping State และ Lifecycle Reducer
  - เพิ่ม Read-only Deal Association Projection / Batch Lifecycle Handling ตาม Contract
- `Include/BotTrade/Grid/GridEntryMappingSnapshotStorage.mqh`
  - Durable Journal/Snapshot Backend; Append ต้องผ่าน Sequence/Flush Contract เดิม
- `Include/BotTrade/Grid/GridLevelRuntimeCoordinator.mqh`
  - WP-05B Hydration และ Reconciliation Gate
  - เพิ่ม Explicit Gate-release API; ห้ามเปิด Gate โดยการเรียก `Reconcile()` แบบ Implicit
- `Include/BotTrade/Grid/GridEntryExecutionAdapter.mqh`
  - ใช้เป็น Reference ของ Append-then-Apply Pattern เท่านั้น
  - **ห้าม include/reuse `CTGKGridEntryCTradePort` หรือ `CTrade` ใน WP-05C no-trade path**

### New Source Files (ชื่อเสนอ; Implementer ปรับชื่อได้หากรักษา Responsibility/Contract)

1. `Include/BotTrade/Grid/GridOpenPositionSnapshot.mqh`
   - Snapshot DTO, Acquisition Port, Production MT5 Read-only Port และ Two-scan Stable Snapshot Acquisition
2. `Include/BotTrade/Grid/GridOpenPositionReconciliation.mqh`
   - Pure Reconciliation Diff/Policy, Durable Batch Coordination และ Coordinator Hydration/Gate Release
3. Test files:
   - `Experts/TGK/Tests/Grids/test_grid_open_position_snapshot.mq5`
   - `Experts/TGK/Tests/Grids/test_grid_open_position_reconciliation.mq5`
   - Extend Reducer, Snapshot Storage และ Runtime Restoration/Coordinator tests ที่ได้รับผลกระทบ

ห้ามสร้าง Production EA หรือเชื่อม `OnTradeTransaction`; งานดังกล่าวเป็น WP-05D

## 3. Required Data Contracts

### 3.1 Full Account Position Snapshot

แต่ละ Record ต้องเก็บ:

- `position_identifier` — Canonical Identity; แปลงเป็น Decimal String ที่ Persistence Boundary
- `ticket` — Current Operational Ticket (`ulong`)
- `symbol`
- `magic_number`
- `volume`

Snapshot Envelope ต้องเก็บเพิ่ม:

- Validity/Status (Complete, Unstable/Retry, Invalid/Error)
- จำนวน Account Positions ที่พบในแต่ละ Scan
- Acquisition Generation/Token ที่เพิ่มขึ้นทุกครั้ง
- Reducer `LastSequence()` ณ จุดเริ่ม Acquisition (`base_sequence`)

Acquisition Port ต้อง Inject ได้ Production Implementation อ่าน Account Positions เท่านั้น ส่วน Fake ต้องจำลอง Enumeration, Ticket Selection, Property Read Failure และการเปลี่ยนข้อมูลระหว่างสอง Scan ได้

### 3.2 Acquisition Contract

- ทำ Full Account Scan สองรอบภายใน Serialized EA Event เดียวกัน
- ทุก Index ต้องได้ Ticket ที่ไม่เป็นศูนย์, Select Ticket สำเร็จ และอ่าน Required Properties ได้ครบ
- Capture Account Positions ทั้งหมดก่อน จากนั้นจึง Filter ด้วย `symbol == expected_symbol && magic_number == expected_magic`
- เปรียบเทียบ Owned Position Set โดยไม่ขึ้นกับลำดับ Enumeration; Identifier, Ticket, Symbol, Magic และ Volume ต้องตรงกัน และห้ามมี Duplicate Ticket หรือ Position Identifier
- หาก Account Total เปลี่ยน, Scan ใดล้มเหลว, Property Read ล้มเหลว หรือ Relevant Set ไม่ตรงกัน ให้ปฏิเสธ Snapshot ทั้งชุด อนุญาต Retry เฉพาะตาม Bounded Policy ที่กำหนดชัดเจน
- Empty Snapshot ยอมรับได้เฉพาะเมื่อ Full Scan ทั้งสองรอบสำเร็จและทั้งคู่พบ Position Total เป็นศูนย์
- ห้ามแปลง Scan Failure, Incomplete Scan, Invalid Ticket หรือ Unstable Observation ให้เป็น Empty Snapshot
- ห้าม Queue Accepted Snapshot; Acquisition และ Consume ต้องทำต่อเนื่องใน Serialized EA Event เดียวกัน
- `Consume()` ต้องปฏิเสธ Token ที่ถูกใช้แล้ว, ไม่ใช่ Latest Accepted Generation หรือมี `base_sequence` ไม่ตรงกับ Reducer ปัจจุบัน

### 3.3 Mapping Reconciliation Rules

สร้าง Diff เทียบกับ Canonical Reducer Projection โดย Match ด้วย Position Identifier เท่านั้น:

- Identifier เดิม + Live Volume ลดลงแต่ยังมากกว่า 0: สร้าง `POSITION_METADATA` Lifecycle Update หนึ่งรายการที่บรรจุทั้ง Volume และ Ticket ปัจจุบัน; Mapping และ ACTIVE คงอยู่
- Identifier เดิม + Volume เท่าเดิม: ไม่เขียน Record เว้นแต่ Ticket เปลี่ยน; หาก Ticket เปลี่ยนให้ Update Metadata
- Identifier เดิม + Volume เพิ่มขึ้น: Conflicting Evidence; ปฏิเสธ Reconciliation Batch ทั้งชุดและ Fail Closed
- Identifier ที่มี Mapping หายจาก Accepted Snapshot: สร้าง Reason-free `POSITION_CLOSED` Lifecycle Event หนึ่งรายการ พร้อม Post-close State ที่คำนวณ ณ Consume Time จาก Executable-side Quote ปัจจุบัน (BUY=Ask, SELL=Bid)
- ห้ามอนุมาน Target จาก Price, Ticket, Order Comment, Array Order หรือ Approximate Level
- Owned Live Position ที่ไม่มี Mapping จะไม่ถูก Adopt โดย WP-05C; อนุญาตให้คงเป็น Unresolved Evidence ได้เฉพาะเมื่อเชื่อม Position Identifier กับ Durable Entry Deal Association ของ Single Valid Unresolved Entry Request ได้ หากพิสูจน์ไม่ได้ให้ Fail Closed เป็น Orphan
- Foreign Symbol/Magic Positions ถูก Ignore ได้หลังจาก Complete Account Snapshot ผ่านการตรวจสอบแล้วเท่านั้น
- Entry Deal Association ใช้สำหรับ Entry Fill Correlation เท่านั้น ห้ามอ่าน Closing Deal History

### 3.4 Durable Batch Atomicity

Accepted Snapshot หนึ่งชุดอาจทำให้เกิด Metadata/Close Updates หลายรายการ ทั้งหมดต้องเป็น Logical Durable Transaction เดียว:

- Validate Diff ทั้งหมดก่อนเขียนข้อมูล
- Persist Diff ทั้งชุดเป็น Journal Record เดียวชนิด `TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE` โดยใช้ Versioned Reconciliation Batch Payload; ห้าม Append แยกหนึ่ง Record ต่อหนึ่ง Position
- Reducer ต้อง Validate/Apply Batch แบบ Transactional; Sub-event ที่ Malformed/Conflicting เพียงรายการเดียวต้องทำให้ทั้ง Batch ไม่เปลี่ยน In-memory State
- Append/Flush Failure ต้องไม่เปลี่ยน Reducer หรือ Coordinator; หาก Append สำเร็จแต่ In-memory Apply หลัง Append ล้มเหลวโดยไม่คาดคิด ให้เข้า Recovery Required และคง Runtime Gate ปิดไว้ Recovery ใช้ Restart/Replay เท่านั้น
- No-op Diff ต้องไม่ Append และไม่เพิ่ม Sequence
- การประมวลผล Snapshot ซ้ำต้อง Idempotent และไม่สร้าง Full Close Record ซ้ำ; Token เดิม Consume ซ้ำไม่ได้
- รักษา Journal Sequence Continuity และ Snapshot Rotation Behavior เดิม ห้าม Bypass `CTGKGridEntryMappingSnapshotStorage`

รูปแบบ Batch Payload ที่เสนอ (Implementer ปรับ Encoding ได้ หากยังคง One-record Atomicity และ Replay Compatibility):

```text
v1|RECONCILIATION_BATCH|<event_count>|<encoded_event_1>|...|<encoded_event_N>
```

Sub-event แต่ละรายการใช้ Canonical Lifecycle Operation เช่น `POSITION_METADATA|<identifier>|<volume>|<ticket>` หรือ `POSITION_CLOSED|<identifier>|<READY_OR_WAIT_ACTIVATION>` และต้องคง Legacy Lifecycle Payload Replay Compatibility

### 3.5 Runtime Coordinator Integration

- หลัง Append Durable Batch และ Reducer Apply สำเร็จ ให้สร้าง Complete Canonical Hydration Projection จาก Reducer (Config, Anchor/Level States, Mapped Positions และ Unresolved Request)
- Hydrate/Rebuild Coordinator จาก Canonical Projection นี้เท่านั้น ห้ามสร้าง Mapping/State Machine ซ้ำใน Reconciliation Adapter
- เพิ่ม Explicit Gate-release API ซึ่งรับ Proof ของ Latest Accepted Snapshot และตรวจ Coordinator Projection ให้ตรงกันก่อน Clear `m_reconciliation_pending`
- Gate Release ต้อง Fail Closed หาก Identity, Symbol, Magic, Config Epoch, Mapping Identifier/Target, Ticket/Volume, Unresolved-request Evidence, Quote, Snapshot Generation หรือ Base Sequence ไม่สอดคล้อง
- Gate Release ต้อง Refresh Current/Previous Quote Baseline และห้าม Emit Candidate ในขั้นตอน Release; การเรียก `UpdatePrice()` กลับมาทำงานได้หลัง Gate เปิดเท่านั้น
- หาก Coordinator Hydration หรือ Gate Release ล้มเหลวหลัง Durable Commit ให้ Runtime คง Unusable/Gated และ Recovery จาก Canonical Reducer เท่านั้น ห้าม Rollback หรือสร้าง Compensating State เอง

## 4. Port Boundaries

ใช้ Interface ขนาดเล็กเพื่อให้ Unit Tests ทำงานแบบ Deterministic:

- Position Snapshot Port: Total Count, Ticket at Index, Select Ticket และ Read Selected Position Properties
- Mapping Journal Port: Read Next Sequence และ Append One Record; Production Adapter ครอบ `CTGKGridEntryMappingSnapshotStorage`, Fake เก็บ Record ใน Memory และ Inject Append Failure ได้
- Current Quote ส่งเป็น Input ที่ Consume Time หรือผ่าน Fakeable Quote Port; ห้ามใช้ Quote ที่ Capture ระหว่าง Scan แรก
- Acquisition/Policy Tests ต้องไม่พึ่ง MT5 Account API
- Production MT5 Adapter ใช้ได้เฉพาะ Read-only `PositionsTotal`, `PositionGetTicket`, `PositionSelectByTicket` และ Position Property Getters ที่จำเป็น

## 5. Safety / Prohibited Behavior

- ห้ามใช้ `CTrade`, `OrderSend`, `PositionClose`, Buy/Sell หรือ Trade Request ทุกชนิด
- ห้ามแก้ไข Demo/Live Account
- ห้าม Production `OnTradeTransaction` Integration (WP-05D)
- ห้าม Closing Deal History, TP/NON_TP, SL/Manual Classification, Close Price หรือ Close Reason
- ห้าม Adopt Orphan Position และห้ามเดา Level/Anchor Mapping
- ห้ามเปลี่ยน Reset/Close-confirmation Semantics เดิม
- ห้าม Commit หรือ Push
- รักษา Staged, Unstaged และ Untracked User Changes ทั้งหมด

## 6. Implementation Sequence

1. ตรวจ Branch/Worktree ปัจจุบันและรักษาการเปลี่ยนแปลงเดิม ยืนยัน Source/Test ล่าสุดของ WP-05B
2. Implement Fakeable Full-snapshot Port, Production Read-only MT5 Adapter และ Stable Two-scan Acquirer
3. Implement Snapshot Validation, Order-independent Comparison, Generation/Sequence Freshness และ Consumed-token Protection
4. เพิ่ม Read-only Deal Association Projection ใน Reducer เพื่อใช้ตรวจ Unresolved Entry Evidence
5. เพิ่ม Versioned One-record Reconciliation Batch และ Transactional Reducer Apply/Replay
6. เพิ่ม Mapping Journal Port ที่ใช้ `CTGKGridEntryMappingSnapshotStorage`; ห้ามพึ่ง CTrade Execution Port
7. เพิ่ม Coordinator Projection Hydration และ Explicit Proof-based Reconciliation Gate Release
8. เพิ่ม Test EA ใหม่ 2 ไฟล์ และขยาย Reducer/Storage/Coordinator/Restoration Tests ที่เกี่ยวข้อง
9. Compile MQL5 Consumers ทุกตัวที่ได้รับผลกระทบ แก้ Error และ Warning จนเป็น 0 errors, 0 warnings
10. รายงาน Changed Files, API Contracts, Test Inventory, Compile Evidence และ Issues ที่ยังเหลือ ห้ามรัน MT5 Tests; Product Owner เป็นผู้รัน

Implementation ทำทีละ Card เท่านั้น ห้ามรวมงาน WP-05D

## 7. Test and Compile Gates

ใช้ `TEST_PLAN.md` เป็น Acceptance Matrix ต้องครอบคลุม C-01 ถึง C-17 และ Expanded Subcases ใน Technical Test Addendum

Implementer ต้อง Compile ทุก Direct/Transitive Consumer ของ Header ที่เปลี่ยน รวม Grid Test EA ทุกตัวที่ได้รับผลกระทบ ให้ได้ 0 errors, 0 warnings ผู้ใช้เป็นผู้รัน MetaEditor/MT5 Tests และรายงานผล Static Review/Compile ไม่ใช่ Runtime Evidence

## 8. Handoff Checklist

- [ ] Product Owner อนุมัติ WP-05C Implementation อย่างชัดเจน
- [ ] Product Owner รัน Latest no-trade Grid Regression Baseline บน Source ก่อนแก้ไข และรายงาน PASS
- [ ] Product Owner เลือก Implementer (Codex หรือ Freebuff)
- [ ] Implementer อ่าน `AGENTS.md`, ไฟล์นี้, `SPEC.md`, `TEST_PLAN.md` และ WP-05B Implementation/Report/Review ที่เกี่ยวข้อง
- [ ] ไม่เขียนทับ Worktree Changes ที่ไม่เกี่ยวข้อง
- [ ] ไม่มี Trade Request, Demo/Live Test หรือ WP-05D Work ถูกนำเข้ามา
