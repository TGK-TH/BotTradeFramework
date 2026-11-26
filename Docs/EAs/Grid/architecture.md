# ภาพรวมสถาปัตยกรรม Grid

อัปเดตล่าสุด: 2026-11-26

## ขอบเขตของเอกสาร

เอกสารนี้อธิบาย Grid components ที่มีอยู่ใน Source Code ณ วันที่อัปเดต ไม่ใช่คำอธิบาย Grid Engine ที่เสร็จสมบูรณ์แล้ว ปัจจุบันมีโครงสร้างข้อมูล ระบบ Identity/Persistence, Lifecycle/Runtime Orchestration, Close Execution Adapter, Two-sided Level Engine/Coordinator, Persistent Entry Mapping/Reducer/Snapshot Rotation, Entry Execution Policy, Resolver/Caller, Entry CTrade Adapter และ WP-04 Pipeline component เสร็จแล้ว อย่างไรก็ตามยังไม่มี Production EA Event Handler หรือ End-to-End Grid V1

**สถานะ WP-05 ณ 2026-11-26:** WP-05A.1/.2/.3 และ WP-05B ปิดแล้ว; WP-05B Restore Canonical Reducer State เข้า Engine/Coordinator แบบ All-or-Nothing โดยไม่ทำ Live Position Scan และคง Entry/Candidate Gate ปิดหลัง Hydration จนกว่า WP-05C จะ Reconcile สำเร็จ. WP-05C Design/Scope Approved และเป็น Dependency ถัดไป แต่ Implementation ยังไม่ได้รับอนุญาต. WP-05C เป็นผู้ Acquire Complete/Stable Open Positions Snapshot และทำ Reconciliation เพื่อปลด Gate เมื่อสำเร็จ. ไม่มี Closing Deal History หรือ TP/NON_TP Classification สำหรับ Full Close; ใช้ Reason-free Full Close ตาม WP-05A.2. ดู SPEC/TEST_PLAN ใน `WorkPackages/WP-05A/Phase-1.3/`, `WorkPackages/WP-05B/` และ `WorkPackages/WP-05C/`.

**สถานะ Anchor State ใน Persistence (2026-11-23):** `CTGKGridEntryMappingReducer` มี Typed Anchor State จาก WP-05A.1 (ผู้ใช้รายงาน Compile/Test PASS และ CTO Review APPROVED). WP-05A.2 Implement แล้วโดย Freebuff เมื่อ 2026-11-23: Anchor State ถูก Serialize ใน Snapshot (Required Field), Anchor Mapping เปลี่ยน State เป็น ACTIVE, Partial Close คง ACTIVE, Full Close เป็น reason-free atomic transition, `WAIT_RETURN` normalize เป็น `READY` และ Idempotency อ้างอิง Mapping State. **Freebuff แก้ CR-01/CR-02/CR-03 ครบ; MetaEditor Compile ของ Adapter consumers ผ่าน 0 errors / 0 warnings และผู้ใช้รายงาน full no-trade Grid Regression PASS เมื่อ 2026-11-24. CTO Code Review APPROVED เมื่อ 2026-11-24; WP-05A.2 Done.** ดู [WP-05A Work Package](WorkPackages/WP-05A/README.md).

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
   |
   +--> CTGKGridEntryMappingReducer
   |       +--> Typed Payload validation และ deterministic Current-State reduction
   |       +--> Position Mapping / Level State transition authority
   |
   +--> CTGKGridEntryMappingSnapshotStorage
   |       +--> Snapshot + Journal generations + dual Manifest slots
   |       +--> Commit / Recovery / Rotation / Cleanup
   |
   +--> CTGKGridEntryExecutionPolicy
   |       +--> Pure Entry decision; no Trade API / no persistence dependency
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
| `Include/BotTrade/Grid/GridEntryMappingStorage.mqh` | Append-only Journal แยก Account/Server/Symbol/Instance ใน Terminal `MQL5/Files`; ตรวจ Schema/Sequence/Checksum และ Replay |
| `Include/BotTrade/Grid/GridEntryMappingReducer.mqh` | Typed Payload validation และ deterministic Current-State reduction; เป็น Authority สำหรับ Position Mapping, Normal Level State และ Typed Anchor State; WP-05A.2 implemented atomic Anchor/Level close transitions, Partial Close metadata, Snapshot Anchor State, replay normalization และ durable `ANCHOR_STATE` WAIT_ACTIVATION -> READY transition (Freebuff compile 0 errors / 0 warnings; user-reported full no-trade Grid Regression PASS 2026-11-24; CTO Review APPROVED) |
| `Include/BotTrade/Grid/GridEntryMappingSnapshotStorage.mqh` | Snapshot + Journal generation/Manifest rotation, validation, recovery และ cleanup |
| `Include/BotTrade/Grid/GridEntryExecutionPolicy.mqh` | Pure decision policy สำหรับ Candidate/Level/Execution Context; ไม่มี Trade API, I/O หรือ persistent state; ผู้ใช้รายงาน WP-01 Compile/Runtime PASS |
| `Include/BotTrade/Grid/GridEntryExecutionAdapter.mqh` | Entry Adapter ที่ Persist Intent ก่อนเรียก Port; Production `CTGKGridEntryCTradePort` เชื่อม Snapshot Storage กับ `CTrade`; accepted outcomes รอ Position Reconciliation |
| `Include/BotTrade/Grid/GridEntryExecutionPipeline.mqh` | WP-04 ประสาน Offered Candidate → Resolver/Policy → Adapter → Coordinator request state; accepted/uncertain requests คง unresolved; ไม่สร้าง Position Mapping หรือยืนยัน `ACTIVE` |
| `Include/BotTrade/Grid/GridStateMachine.mqh` | จัดการ Lifecycle transitions; ไม่ส่งคำสั่งซื้อขายและต้องรับจำนวน Position ที่ตรวจยืนยันแล้วจากผู้เรียก |
| `Include/BotTrade/Grid/GridLifecycle.mqh` | ประสาน State Machine กับ Persistence สำหรับ Instance ที่มี Identity แล้ว; ไม่ส่งคำสั่งซื้อขาย |
| `Include/BotTrade/Grid/GridPositionReconciler.mqh` | กรอง/นับ Position ของ Instance และประเมินผล close attempt จากสถานะบัญชีที่ตรวจใหม่; ไม่ส่งคำสั่งซื้อขาย |
| `Include/BotTrade/Grid/GridRuntimeOrchestrator.mqh` | ประสาน Lifecycle, Persistence และ Position Reconciler; แจ้งความต้องการ Close แต่ไม่ส่งคำสั่งซื้อขายเอง |
| `Include/BotTrade/Grid/GridOrderExecutionPolicy.mqh` | Pure policy สำหรับ ownership filtering, close batch และ retcode classification; ไม่มี trade request |
| `Include/BotTrade/Grid/GridOrderExecutionAdapter.mqh` | Live adapter สำหรับปิด Position แบบ ticket-specific เมื่อ Runtime แจ้ง CLOSE_REQUIRED |
| `Include/BotTrade/Testing/TestAssert.mqh` | ฟังก์ชัน Assertion พื้นฐาน |
| `Include/BotTrade/Testing/TestRunner.mqh` | จัดกลุ่ม Test นับผล และพิมพ์ PASS/FAIL |

## Entry Mapping และ Snapshot Rotation (อัปเดต 2026-11-17)

- `GridEntryMappingStorage.mqh` จัดการ Append-only Journal; `GridEntryMappingReducer.mqh` แปลง Typed Records เป็น Current State และตรวจ Mapping/State transitions
- `GridEntryMappingSnapshotStorage.mqh` จัดการ Snapshot, dual Manifest slots, Journal generation rotation, Commit/Recovery/Cleanup และ capacity limits
- Mapping ใช้ Position Identifier เป็น Logical Key; Order Comment ไม่ใช่ Mapping Key และ Accepted/PLACED ไม่ใช่หลักฐานว่า Position เปิดแล้ว
- ผู้ใช้รายงาน Compile/Runtime PASS ของ Snapshot/Reducer/Regression เมื่อ 2026-11-15; ดูรายละเอียดใน [Entry Adapter Round 1](Phases/phase-grid-entry-execution-adapter-round-1.md)

## Entry Execution Policy, Resolver และ Adapter

- Design/Contract และ Test Plan ได้รับอนุมัติ; Test EA มี 44 Test IDs / 6 Groups
- Static Acceptance Checks ผ่าน 2026-11-17; ผู้ใช้รายงาน Policy Test 44/44 และ Grid Regression 15/15 Compile/Runtime PASS
- `GridEntryExecutionPolicy.mqh` ถูกสร้างตาม Contract; ผู้ใช้รายงาน Policy Test 44/44 และ Grid Regression 15/15 Compile/Runtime PASS เมื่อ 2026-11-17
- WP-02 Resolver/Caller ใช้ Runtime Coordinator สำหรับ Level State และ Mapping Reducer สำหรับ Instance/Mode/Config Epoch/Position Mapping; Resolver ปฏิเสธ disagreement และ Caller ไม่เรียก Policy เมื่อ Resolve ล้มเหลว
- `GridEntryMappingReducer.mqh` เพิ่ม `MatchesContext()` และ `TryGetPositionMapping()` แบบ read-only; `GridLevelRuntimeCoordinator.mqh` เพิ่ม Mode match และ one-time `BindConfigEpoch()` เพื่อกัน stale runtime context
- `GridEntryExecutionResolver.mqh` รวม Resolver กับ Caller; Test EA มี 17 cases และผู้ใช้รายงาน Compile/Run PASS เมื่อ 2026-11-18
- Resolver provenance เป็นความรับผิดชอบของ Caller และต้องทดสอบ Integration แยก; Resolve failure ต้อง Fail Closed และห้ามเรียก Policy
- WP-03 `GridEntryExecutionAdapter.mqh` แยก intent/result orchestration ออกจาก Port; `ITGKGridEntryExecutionPort` เป็น seam สำหรับ Fake Unit Tests และ `CTGKGridEntryCTradePort` เป็น Production Port ที่ใช้ `GridEntryMappingSnapshotStorage.mqh`
- Adapter บันทึก Typed `ENTRY_INTENT` และนำเข้า Reducer ก่อนส่ง BUY/SELL; จากนั้นบันทึก `EXECUTION_RESULT`; `DONE`, `DONE_PARTIAL`, `PLACED` ยังคง unresolved และไม่สร้าง Position Mapping
- Entry Adapter Test EA มี 13 cases ใช้ Fake Port ไม่มี Trade Request หรือ File I/O; Static Review ผ่าน และผู้ใช้รายงาน Compile/Run ผ่านเมื่อ 2026-11-19
- ดู Contract เต็มใน [Entry Execution Policy](Phases/phase-grid-entry-execution-policy.md)

## Grid Level Engine — Design และ Round 1 Implementation

Design Specification: [Grid Level Engine](Phases/phase-grid-level-engine-design.md)

- Two-sided Grid Levels คำนวณจาก Fill Price (Anchor) และ Grid Step ทั้งสองด้าน; Bounds เป็น Hard Filter ไม่เลื่อนราคา Level
- Anchor เป็น Special/Re-entry Level แยกจาก Grid Levels ปกติ ไม่รวมใน `level_count`
- Initial State และ State transitions ใช้ Current Price (BUY=Ask, SELL=Bid) ไม่ใช้ตำแหน่งเทียบ Anchor เป็นเงื่อนไขเข้าเทรด
- BUY เลือก Candidate ราคาต่ำที่สุด; SELL เลือก Candidate ราคาสูงที่สุด; หนึ่ง Price Check เลือกได้ไม่เกินหนึ่ง Candidate
- Round 1 previously had legacy `WAIT_RETURN` and TP/Non-TP close handling; that behavior is superseded by the WP-05A.2 implementation below.
- **WP-05A.2 implemented and approved 2026-11-24 (CR-01/CR-02/CR-03 resolved; Freebuff Compile PASS and user-reported full no-trade Grid Regression PASS):** operational states are `READY`, `ACTIVE`, `WAIT_ACTIVATION`; legacy `WAIT_RETURN` normalizes to `READY` and is never emitted by new writes. Close handling is reason-free. The Anchor's `WAIT_ACTIVATION -> READY` activation is a validated, journaled `ANCHOR_STATE` record applied by the Reducer before the Engine/Coordinator treat the Anchor as READY.
- Level ที่ไม่ได้รับเลือกและถูกข้ามไปอยู่ผิดด้านของ Current Price เปลี่ยนเป็น `WAIT_ACTIVATION`; `ACTIVE` คงเดิม
- Full Close ทุกเหตุผลใช้ Current executable-side quote เดียวกันเพื่อเลือก `WAIT_ACTIVATION` หรือ `READY`; Partial Close คง `ACTIVE`
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
- Historical Round 1 behavior (2026-11-09): disappearance required an explicit TP/Non-TP Close Event. Superseded by WP-05A.2 (2026-11-24): Partial Close retains ACTIVE; Full Close is reason-free after authoritative Open Positions reconciliation.
- ผู้ใช้ยืนยันว่า Coordinator Test EA และ Grid Regression Tests เดิมทั้ง 11 ไฟล์ Compile/Run ผ่านใน MetaEditor/MT5 ครบ 12/12 เมื่อ 2026-11-09 (User-reported; Assistant did not independently run MT5)

- ผู้ใช้ยืนยันให้หนึ่ง Instance มี Unresolved Entry Request ได้สูงสุดหนึ่งรายการ และเก็บ Deferred Candidate ที่ดีที่สุดไว้ (BUY ราคาต่ำสุด / SELL ราคาสูงสุด)
- Position-to-Level Mapping ต้องระบุจาก Integration Layer ด้วย Anchor flag หรือ Level Index; Coordinator ไม่เดา Mapping จากราคา Fill
- ACTIVE จะเกิดขึ้นเมื่อ Reconciliation ยืนยัน Position ที่ตรงกับ Request และ Mapping เท่านั้น; Accepted/Placed ไม่ใช่หลักฐานว่าเปิด Position แล้ว
- Partial Close ที่ยังมี Volume เหลือต้องคง ACTIVE; Full Close เป็น Reason-free Durable Transition หลัง WP-05C ยืนยันการหายไปจาก Complete/Stable Open Positions Snapshot ตาม WP-05A.2; ไม่ต้อง Resolve Close Reason
- WP-03 ส่ง Entry ผ่าน CTrade Port ได้; WP-04 เพิ่ม Orchestration ระหว่าง Coordinator Candidate, Resolver/Policy, Adapter และ Coordinator request state โดยยังไม่มี Production EA Event Handler

## WP-05 Persistence / Runtime Restoration / Open Positions Reconciliation — Approved Design/Scope 2026-11-25

Product Owner อนุมัติ Design/Scope ของ WP-05A.3, WP-05B และ WP-05C เมื่อ 2026-11-25; WP-05A.3 และ WP-05B Implement, User Verify และ CTO Review APPROVED/ปิดแล้ว. Dependency ถัดไปคือ WP-05C ซึ่งยังต้องมี Fresh Baseline และ Explicit Product Owner Implementation Authorization.

- WP-05A.3 พิสูจน์ Anchor `READY` / `ACTIVE` / `WAIT_ACTIVATION` ผ่าน Canonical Reducer Snapshot, Journal Replay, Rotation และ Restart Recovery; ไม่เพิ่ม Persistence Authority.
- WP-05B Restore Canonical Reducer State เข้า Engine/Coordinator แบบ All-or-Nothing; หลัง Hydration ต้องคง `RESTORED_PENDING_RECONCILIATION` และปิด Entry/Candidate Gate.
- WP-05C เป็นเจ้าของ Complete/Stable Open Positions Snapshot และ Reconciliation โดยใช้ Position Identifier เป็น Canonical Identity และ Ticket เป็น Operational Handle; Snapshot ต้องถูก Consume ใน Serialized EA Event เดียวกัน.
- เมื่อ WP-05C ยืนยัน Full Close ให้ใช้ Reason-free Atomic Transition ตาม WP-05A.2 และ Current executable-side quote ณ เวลา Consume (BUY ใช้ Ask, SELL ใช้ Bid); ไม่อ่าน Closing Deal History หรือจำแนก TP/SL/Manual.
- WP-05C เปิด Reconciliation Gate ของ WP-05B ได้ต่อเมื่อ Snapshot และ Reconciliation สำเร็จเท่านั้น. Scan failure, incomplete/unstable snapshot, orphan หรือ conflicting evidence ต้อง Fail Closed.

## ขอบเขตที่ยังไม่เสร็จ

- Grid Runtime Orchestration Round 1 ผ่านตามผล Compile/Runtime ที่ผู้ใช้รายงานเมื่อ 2026-10-30
- Grid Order Execution Adapter Round 1 ผ่านตามผล Compile/Runtime ที่ผู้ใช้รายงานเมื่อ 2026-10-31 (Unit Test ใหม่ + Grid Regression 9 ไฟล์ รวม 10 Tests)
- Demo Integration Test EA แยกที่ `Experts/TGK/Tests/Grids/test_grid_order_execution_demo.mq5` ผ่านตามผลที่ผู้ใช้รายงานเมื่อ 2026-11-02: Compile ผ่าน, ปิด Owned Positions จริงผ่าน Adapter บน Demo, ยืนยัน Foreign Position ไม่ถูกแตะต้อง และปิด Foreign Position ผ่านขั้นตอน Cleanup ที่ผู้ใช้กดเอง
- ผล Demo นี้เสริม Unit/Regression Tests โดยยืนยัน Live Scan + ticket-specific close + Runtime reconciliation ใน Test Scenario ที่กำหนด; ไม่ได้หมายความว่า Grid V1 หรือ EA Event Handler Integration เสร็จสมบูรณ์
- Entry Mapping Storage, Typed Reducer และ Snapshot/Journal Rotation มี Source แล้ว และผู้ใช้รายงานผล Compile/Runtime/Regression PASS เมื่อ 2026-11-15; ดูรายละเอียดใน `phase-grid-entry-execution-adapter-round-1.md`
- Entry Execution Policy มี Design Baseline, Test-First Specification 44 Cases และ Policy Source แล้ว; ผู้ใช้รายงาน Policy Test 44/44 และ Grid Regression 15/15 ผ่าน Compile/Runtime
- CTrade Entry Adapter Source และ Fake Port Test EA 13 cases เพิ่มใน WP-03 แล้ว; Static PASS และผู้ใช้รายงาน Compile/Run ผ่านเมื่อ 2026-11-19
- Caller/Resolver Source และ Integration Test 17 cases เพิ่มใน WP-02 แล้ว; ผู้ใช้รายงาน Compile/Run PASS
- ยังไม่มี EA Event Handler adapter ที่เชื่อม Orchestrator/Execution จาก OnInit/OnTick/OnTimer/OnTradeTransaction แบบครบวงจร
- ยังไม่มีการจัดการคำสั่งซื้อขายหลาย Level ของ Grid แบบ End-to-end ที่ผ่าน Acceptance Tests ครบ
- ยังไม่มีการยืนยันว่าข้อกำหนดทุกข้อของ Grid V1 ถูกนำไปใช้และผ่าน MT5 validation แล้ว
- Lifecycle ที่ตกลงแล้ว: การเปิดกราฟใหม่ด้วยตนเองเป็น Grid Instance ใหม่และไม่ Adopt Position ของ Instance เดิม ส่วน Grid เดิมจะกลับมาทำงานเมื่อ Restore กราฟ/โปรไฟล์เดิมและกู้ Identity/Persistence ได้

## หลักการแยกความรับผิดชอบ

- Identity ระบุว่า Grid Instance นี้คือ Instance ใด และใช้ Magic Number ใด
- Persistence เก็บข้อมูลสถานะของ Instance ที่ระบุมาให้ แต่ไม่ได้เป็นผู้กำหนด Lifecycle ของ Instance
- Types ประกาศรูปแบบข้อมูลและ Enum โดยไม่ได้ดำเนินการซื้อขายเอง
- Test framework ตรวจเงื่อนไขและรายงานผล ไม่ได้เป็นหลักฐานแทนการทดสอบจริงใน MetaEditor/MT5
