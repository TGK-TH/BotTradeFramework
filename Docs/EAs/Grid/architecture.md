# ภาพรวมสถาปัตยกรรม Grid

อัปเดตล่าสุด: 2026-11-09

## ขอบเขตของเอกสาร

เอกสารนี้อธิบาย Grid components ที่มีอยู่ใน Source Code ณ วันที่อัปเดต ไม่ใช่คำอธิบาย Grid Engine ที่เสร็จสมบูรณ์แล้ว ปัจจุบันมีโครงสร้างข้อมูล ระบบ Identity ระบบ Persistence, Lifecycle/Runtime Orchestration และ Order Execution Adapter รอบแรกที่รองรับการปิด Position ระหว่าง Reset เท่านั้น ยังไม่ครอบคลุมข้อกำหนด Grid V1 ทั้งหมด

## ส่วนประกอบปัจจุบัน

```text
EA / Test EA
   |
   +--> CTGKGridIdentity
   |       +--> Hidden chart marker
   |       +--> Terminal Global Variables สำหรับ Magic registry/sequence/lock
   |
   +--> STGKGridInstanceData (ประกาศใน GridTypes.mqh)
   |
   +--> CTGKGridLifecycle
   |       +--> Coordinates State Machine + Persistence
   |       +--> Safe recovery errors (no order execution)
   |
   +--> CTGKGridRuntimeOrchestrator
   |       +--> Coordinates Lifecycle + Position Reconciler
   |       +--> Reports close-required / wait / active / error status
   |       +--> No order execution
   |
   +--> CTGKGridPositionReconciler
   |       +--> Read-only position scan filtered by Symbol + Magic
   |       +--> Close-attempt/reconciliation policy
   |
   +--> CTGKGridLevelEngine
   |       +--> Pure Two-sided Level calculation and Candidate selection
   |
   +--> CTGKGridLevelRuntimeCoordinator
   |       +--> Entry Request serialization and Deferred Candidate
   |       +--> Explicit Position-to-Level reconciliation
   |       +--> No Trade/Account API
   |
   +--> CTGKGridOrderExecutionAdapter
   |       +--> Live scan and ticket-specific batch close
   |       +--> Reports aggregate result to Runtime
   |
   +--> CTGKGridOrderExecutionPolicy
   |       +--> Pure ownership filtering and retcode classification
   |       +--> No trade requests; Unit-Testable
   |
   +--> CTGKGridStateMachine
   |       +--> Lifecycle transitions only (no order execution)
   |
   +--> CTGKGridEntryMappingStorage
   |       +--> Append-only Journal ใน Terminal MQL5/Files
   |       +--> Version / Sequence / Checksum / strict Replay
   |       +--> Opaque payload; no Trade API / no Comment parsing
   |
   +--> CTGKGridPersistence
           +--> Terminal Global Variables สำหรับ Snapshot
           +--> Terminal Global Variables สำหรับสถานะของแต่ละ Level

MQL5 Test EAs
   |
   +--> CTGKTestRunner
           +--> CTGKTestAssert
```

## ไฟล์หลัก

| ไฟล์ | หน้าที่ปัจจุบัน |
|---|---|
| `Include/BotTrade/Grid/GridTypes.mqh` | ประกาศ Enum และโครงสร้างข้อมูลที่ใช้แทนสถานะของ Grid |
| `Include/BotTrade/Grid/GridLevelEngine.mqh` | Pure Two-sided Level calculation, Anchor/Level State และ Entry Candidate selection; ไม่เรียก Trade API |
| `Include/BotTrade/Grid/GridLevelRuntimeCoordinator.mqh` | ประสาน Price Update, Candidate, serialized Entry Request, Deferred Candidate และ explicit Position-to-Level reconciliation; ไม่เรียก Trade/Account API |
| `Include/BotTrade/Grid/GridIdentity.mqh` | สร้าง/กู้คืน Instance ID จากวัตถุที่ซ่อนบนกราฟ และจัดสรร Magic Number |
| `Include/BotTrade/Grid/GridPersistence.mqh` | บันทึกและกู้คืน Snapshot และสถานะราย Level ด้วย Terminal Global Variables |
| `Include/BotTrade/Grid/GridEntryMappingStorage.mqh` | Append-only Journal แยก Account/Server/Symbol/Instance ใน Terminal `MQL5/Files`; ตรวจ Schema/Sequence/Checksum และ Replay; Payload ยังเป็น Opaque String ไม่ได้ทำ Mapping Reducer หรือ Trade Execution |
| `Include/BotTrade/Grid/GridStateMachine.mqh` | จัดการ Lifecycle transitions; ไม่ส่งคำสั่งซื้อขายและต้องรับจำนวน Position ที่ตรวจยืนยันแล้วจากผู้เรียก |
| `Include/BotTrade/Grid/GridLifecycle.mqh` | ประสาน State Machine กับ Persistence สำหรับ Instance ที่มี Identity แล้ว; ไม่ส่งคำสั่งซื้อขาย |
| `Include/BotTrade/Grid/GridPositionReconciler.mqh` | กรอง/นับ Position ของ Instance และประเมินผล close attempt จากสถานะบัญชีที่ตรวจใหม่; ไม่ส่งคำสั่งซื้อขาย |
| `Include/BotTrade/Grid/GridRuntimeOrchestrator.mqh` | ประสาน Lifecycle, Persistence และ Position Reconciler; แจ้งความต้องการ Close แต่ไม่ส่งคำสั่งซื้อขายเอง |
| `Include/BotTrade/Grid/GridOrderExecutionPolicy.mqh` | Pure policy สำหรับ ownership filtering, close batch และ retcode classification; ไม่มี trade request |
| `Include/BotTrade/Grid/GridOrderExecutionAdapter.mqh` | Live adapter สำหรับปิด Position แบบ ticket-specific เมื่อ Runtime แจ้ง CLOSE_REQUIRED |
| `Include/BotTrade/Testing/TestAssert.mqh` | ฟังก์ชัน Assertion พื้นฐาน |
| `Include/BotTrade/Testing/TestRunner.mqh` | จัดกลุ่ม Test นับผล และพิมพ์ PASS/FAIL |

## Grid Level Engine — Design และ Round 1 Implementation

Design Specification: [Grid Level Engine](Phases/phase-grid-level-engine-design.md)

- Two-sided Grid Levels คำนวณจาก Fill Price (Anchor) และ Grid Step ทั้งสองด้าน; Bounds เป็น Hard Filter ไม่เลื่อนราคา Level
- Anchor เป็น Special/Re-entry Level แยกจาก Grid Levels ปกติ ไม่รวมใน `level_count`
- Initial State และ State transitions ใช้ Current Price (BUY=Ask, SELL=Bid) ไม่ใช้ตำแหน่งเทียบ Anchor เป็นเงื่อนไขเข้าเทรด
- BUY เลือก Candidate ราคาต่ำที่สุด; SELL เลือก Candidate ราคาสูงที่สุด; หนึ่ง Price Check เลือกได้ไม่เกินหนึ่ง Candidate
- `WAIT_ACTIVATION`, `READY`, `ACTIVE`, `WAIT_RETURN` มี State transitions ตาม Design Specification และ Implementation Notes
- Level ที่ไม่ได้รับเลือกและถูกข้ามไปอยู่ผิดด้านของ Current Price เปลี่ยนเป็น `WAIT_ACTIVATION`; `ACTIVE` คงเดิม
- ปิด Position: ใช้ Current Price ก่อน; ถ้า Level อยู่ผิดด้าน -> `WAIT_ACTIVATION`, ถ้ายังอยู่ด้าน Re-entry -> TP=`WAIT_RETURN`, Non-TP=`READY`
- Runtime/Execution รับผิดชอบ Order request และ Position Reconciliation; Pure Engine ไม่เรียก Trade API

**สถานะ Source/Validation:** Grid Level Engine Round 1 ปรับ `GridLevelEngine.mqh`, `GridTypes.mqh` และ enum validation ใน `GridPersistence.mqh` ตาม Design แล้ว และผู้ใช้ยืนยันว่า Compile และ Grid Regression Tests ครบ 11/11 ผ่านใน MetaEditor/MT5 เมื่อ 2026-11-04 ผลนี้ครอบคลุม Pure Engine และ Test contracts เท่านั้น ไม่ใช่ Production EA Integration

## Grid Level Runtime Coordinator — Round 1 (Completed — User Verified 12/12 PASS, 2026-11-09)

Design Contract and implementation notes: [Grid Level Runtime Coordinator — Round 1](Phases/phase-grid-level-runtime-coordinator-round-1.md)

- Source: `GridLevelRuntimeCoordinator.mqh`; Test EA: `test_grid_level_runtime_coordinator.mq5`
- One offered Candidate at a time, one unresolved Entry Request maximum, and one best Deferred Candidate retained while waiting
- BUY deferred selection prefers lower price; SELL prefers higher price
- Accepted Request is not a fill; only a matching Position Snapshot confirms the Candidate and sets ACTIVE
- Position Snapshot uses explicit Anchor/Level mapping and exact Symbol + Magic identity
- Initial Anchor Position must be registered through `RegisterInitialAnchorPosition()` before the first snapshot reconciliation
- Partial close retains ACTIVE; disappearance requires an explicit TP/Non-TP Close Event
- ผู้ใช้ยืนยันว่า Coordinator Test EA และ Grid Regression Tests เดิมทั้ง 11 ไฟล์ Compile/Run ผ่านใน MetaEditor/MT5 ครบ 12/12 เมื่อ 2026-11-09 (User-reported; Assistant did not independently run MT5)

- ผู้ใช้ยืนยันให้หนึ่ง Instance มี Unresolved Entry Request ได้สูงสุดหนึ่งรายการ และเก็บ Deferred Candidate ที่ดีที่สุดไว้ (BUY ราคาต่ำสุด / SELL ราคาสูงสุด)
- Position-to-Level Mapping ต้องระบุจาก Integration Layer ด้วย Anchor flag หรือ Level Index; Coordinator ไม่เดา Mapping จากราคา Fill
- ACTIVE จะเกิดขึ้นเมื่อ Reconciliation ยืนยัน Position ที่ตรงกับ Request และ Mapping เท่านั้น; Accepted/Placed ไม่ใช่หลักฐานว่าเปิด Position แล้ว
- Partial Close ที่ยังมี Volume เหลือต้องคง ACTIVE; Full Close ต้องมี Close Reason ที่ resolve แล้วก่อนเรียก Engine
- Phase นี้ยังไม่ส่ง Entry ผ่าน CTrade และไม่เชื่อม Production EA Event Handler

## ขอบเขตที่ยังไม่เสร็จ

- Grid Runtime Orchestration Round 1 ผ่านตามผล Compile/Runtime ที่ผู้ใช้รายงานเมื่อ 2026-10-30
- Grid Order Execution Adapter Round 1 ผ่านตามผล Compile/Runtime ที่ผู้ใช้รายงานเมื่อ 2026-10-31 (Unit Test ใหม่ + Grid Regression 9 ไฟล์ รวม 10 Tests)
- Demo Integration Test EA แยกที่ `Experts/TGK/Tests/Grids/test_grid_order_execution_demo.mq5` ผ่านตามผลที่ผู้ใช้รายงานเมื่อ 2026-11-02: Compile ผ่าน, ปิด Owned Positions จริงผ่าน Adapter บน Demo, ยืนยัน Foreign Position ไม่ถูกแตะต้อง และปิด Foreign Position ผ่านขั้นตอน Cleanup ที่ผู้ใช้กดเอง
- ผล Demo นี้เสริม Unit/Regression Tests โดยยืนยัน Live Scan + ticket-specific close + Runtime reconciliation ใน Test Scenario ที่กำหนด; ไม่ได้หมายความว่า Grid V1 หรือ EA Event Handler Integration เสร็จสมบูรณ์
- ยังไม่มี EA Event Handler adapter ที่เรียก Orchestrator/Execution จาก OnInit/OnTick/OnTimer
- ยังไม่มีการจัดการคำสั่งซื้อขายหลาย Level ของ Grid ที่สมบูรณ์
- ยังไม่มีการยืนยันจากเอกสารนี้ว่าข้อกำหนดทุกข้อของ Grid V1 ถูกนำไปใช้ในโค้ดแล้ว
- Lifecycle ที่ตกลงแล้ว: การเปิดกราฟใหม่ด้วยตนเองเป็น Grid Instance ใหม่และไม่ Adopt Position ของ Instance เดิม ส่วน Grid เดิมจะกลับมาทำงานเมื่อ Restore กราฟ/โปรไฟล์เดิมและกู้ Identity/Persistence ได้

## หลักการแยกความรับผิดชอบ

- Identity ระบุว่า Grid Instance นี้คือ Instance ใด และใช้ Magic Number ใด
- Persistence เก็บข้อมูลสถานะของ Instance ที่ระบุมาให้ แต่ไม่ได้เป็นผู้กำหนด Lifecycle ของ Instance
- Types ประกาศรูปแบบข้อมูลและ Enum โดยไม่ได้ดำเนินการซื้อขายเอง
- Test framework ตรวจเงื่อนไขและรายงานผล ไม่ได้เป็นหลักฐานแทนการทดสอบจริงใน MetaEditor/MT5
