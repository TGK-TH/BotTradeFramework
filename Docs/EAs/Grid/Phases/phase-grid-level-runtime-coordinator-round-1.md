# Grid Level Runtime Coordinator — Round 1

อัปเดตล่าสุด: 2026-11-07

**สถานะ: Implementation Round 1 เพิ่ม Source และ Test EA แล้ว — รอผู้ใช้ Compile/Run Test ใหม่และ Regression Tests ใน MetaEditor/MT5**

ผู้ใช้ยืนยันแนวทางเมื่อ 2026-11-07:
1. หนึ่ง Grid Instance มี Entry Request ที่ยัง unresolved ได้สูงสุดหนึ่งรายการ และเก็บ Deferred Candidate ที่ดีที่สุดไว้
2. Position-to-Level Mapping ต้องมาจาก Integration Layer อย่างชัดเจน โดยระบุ Anchor หรือ Level Index; Coordinator จะไม่เดา Mapping จากราคา Fill

## 1. เป้าหมาย

เชื่อม Pure CTGKGridLevelEngine เข้ากับ Runtime orchestration เพื่อจัดการ Candidate, Entry Request lifecycle และ Position-to-Level reconciliation โดยยังไม่ส่งคำสั่งซื้อขายจริง

## 2. Scope

### In scope
- รับ Bid/Ask และส่ง Price Update ให้ Grid Level Engine
- เก็บ Previous Bid/Ask
- เก็บ Candidate ปัจจุบันและ Deferred Candidate ที่ดีที่สุด
- จำกัด Unresolved Entry Request ไว้หนึ่งรายการต่อ Instance
- รับผล Entry Request และผล Reconciliation แยกจากกัน
- เปลี่ยน Level เป็น ACTIVE เฉพาะเมื่อ Reconciliation ยืนยัน Position ที่ Mapping ถูกต้อง
- รองรับ Position Snapshot ที่ระบุ Anchor/Level Index, Ticket และ Volume
- รักษา ACTIVE เมื่อ Partial Close และยังมี Volume เหลือ
- เรียก RecordPositionClosed เฉพาะเมื่อ Position ของ Logical Level หมดจริงและมี Close Reason ที่ยืนยันได้
- เพิ่ม Unit Tests และ Regression coverage

### Out of scope
- ส่งคำสั่ง Buy/Sell ผ่าน CTrade
- Live Entry Adapter หรือ Pending Order API
- Production EA OnInit/OnTick/OnTimer integration
- Restart persistence ของ pending entry request/deferred candidate
- การค้นหา Level จากราคา Fill โดยประมาณ

## 3. Component Boundary

CTGKGridLevelRuntimeCoordinator เป็น coordination layer:
- ใช้ CTGKGridLevelEngine สำหรับ Price Crossing และ Level State transitions
- ไม่เรียก Trade API หรืออ่าน Account โดยตรง
- รับ Entry Request outcomes และ Position snapshots จาก Caller
- ไม่แทนที่ CTGKGridRuntimeOrchestrator ซึ่งยังรับผิดชอบ Lifecycle/Reset
- ไม่ขยายความสามารถของ Close Execution Adapter ให้เปิด Position ใน Phase นี้

## 4. Integration Contract

### 4.1 Price Update และ Candidate

Caller ส่ง Bid/Ask ปัจจุบันเข้ามา Coordinator เก็บ Previous Bid/Ask หลังจาก Quote ผ่าน validation แล้วจึงเรียก Engine

ผลการประมวลผลที่เปิดเผยให้ Caller:
- NO_CANDIDATE: ไม่มี Candidate ใหม่
- CANDIDATE_READY: มี Candidate พร้อมให้ Execution Layer รับไปพิจารณาส่งคำสั่ง
- REQUEST_UNRESOLVED: มี Request ก่อนหน้าที่ยังไม่ resolve; Candidate ใหม่จะถูกเก็บเป็น Deferred Candidate
- ERROR: Input หรือ Coordinator state ไม่ถูกต้อง

Candidate record ต้องมี is_anchor, level_index (Anchor ใช้ -1), level_price และสถานะการจัดการภายใน

BUY เลือก Deferred Candidate ที่ราคาต่ำที่สุด; SELL เลือก Candidate ที่ราคาสูงที่สุด หาก Candidate ราคาเท่ากันให้ถือว่าเป็น Logical Candidate เดียวกัน ไม่สร้างรายการซ้ำ

Coordinator ต้องไม่ส่ง Candidate เดิมซ้ำให้ Caller ในทุก Price Update ขณะ Candidate นั้นกำลังรอให้ Execution Layer รับไปดำเนินการ หรือขณะ Request unresolved

### 4.2 Entry Request Serialization

หนึ่ง Instance มี Entry Request ที่ยัง unresolved ได้สูงสุดหนึ่งรายการ

วงจร Request:
1. Coordinator เปิดเผย Candidate ให้ Caller
2. Caller แจ้งว่า Candidate ถูกส่งเป็น Request แล้ว พร้อมผล Request
3. Rejected/Failed แบบ terminal ที่ยืนยันชัดเจน: Resolve เป็น Failed และเรียก Engine RecordEntryFailed()
4. Accepted/Placed: เก็บ Request เป็น unresolved; ห้ามส่ง Candidate เดิมซ้ำ และห้ามตั้ง Level เป็น ACTIVE
5. Coordinator รับ Reconciliation outcome ที่ระบุได้ว่า Request ยัง pending, มี Position ที่ Fill แล้ว, หรือ terminal โดยไม่มี Position/ไม่มี Order ค้างอยู่
6. เมื่อพบ Position ที่ Mapping ตรงกับ Request: Resolve Request และเรียก RecordEntryConfirmed()
7. เมื่อยืนยัน terminal no-position/no-order: Resolve เป็น Failed และเรียก RecordEntryFailed()
8. เมื่อ Request แรก Resolve แล้ว จึงเปิดเผย Deferred Candidate ที่ดีที่สุดให้ Caller พิจารณา

การไม่พบ Position ใน Snapshot เพียงอย่างเดียวไม่ใช่หลักฐานว่า Request ล้มเหลว ต้องได้รับสถานะจาก Execution/Reconciliation ที่ยืนยันว่าไม่มี Order ค้างอยู่ด้วย ห้ามใช้ Timeout เพียงอย่างเดียวเพื่อตัดสิน Request เป็น Failed

### 4.3 Deferred Candidate

ขณะ Request unresolved:
- ยังคงประมวลผล Price Update เพื่อให้ Engine อัปเดต Activation/Level states
- เก็บ Candidate ใหม่ที่ Engine คืนมา
- BUY แทนที่ Deferred Candidate เมื่อ Candidate ใหม่มีราคาต่ำกว่า
- SELL แทนที่เมื่อ Candidate ใหม่มีราคาสูงกว่า
- Candidate ที่แย่กว่าหรือซ้ำราคาเดิมไม่แทนที่ Candidate ที่เก็บไว้
- เมื่อ Request ปัจจุบัน Resolve แล้ว Deferred Candidate ต้องถูกตรวจสอบกับ Level State ล่าสุดอีกครั้งก่อนเปิดเผย เพราะ Level อาจเปลี่ยน State ระหว่างรอ
- ถ้า Candidate ไม่ eligible อีกต่อไป ให้ทิ้งและรอ Price Update ใหม่ ห้ามบังคับใช้ State กลับไป READY

### 4.4 Position-to-Level Mapping

Integration Layer ส่ง Position Snapshot ที่มีข้อมูลอย่างน้อย:

    struct STGKGridLevelPositionRecord
    {
      ulong ticket;
      string symbol;
      long magic_number;
      bool is_anchor;
      int level_index;
      double volume;
    };

กติกา:
- Symbol และ Magic Number ต้องตรงกับ Instance
- Anchor ใช้ is_anchor=true และ level_index=-1
- Grid Level ใช้ is_anchor=false และ Level Index ที่อยู่ในช่วง Engine
- Volume ต้องมากกว่าศูนย์
- ห้ามมี Ticket ซ้ำ, Mapping ซ้ำ หรือ Logical Level เดียวกันถูกผูกกับหลาย Logical Positions
- Position ที่เป็นของ Instance แต่ Mapping ไม่ถูกต้อง/ไม่รู้จัก ต้องเข้าสู่ Error/Recovery path; ห้ามเดาจากราคา Fill
- Snapshot ต้องเป็นภาพรวมที่ครบถ้วนของ Positions ที่เป็นของ Instance ไม่ใช่ partial list

### 4.5 Partial Close และ Full Close

- Position ที่ยังมี Volume เหลือหลัง Partial Close ต้องคง Level เป็น ACTIVE
- เมื่อ Snapshot ยืนยันว่า Logical Level ไม่มี Position เหลือแล้วเท่านั้น จึงพิจารณาเปลี่ยน State
- Integration Layer ต้องส่ง Close Reason ที่ resolve แล้ว: TP หรือ Non-TP
- หาก Close Reason ยังไม่ทราบ/ขัดแย้งกัน ห้ามเดา State ใหม่; ให้ Coordinator รายงานสถานะที่ต้อง Recovery/รอข้อมูลเพิ่ม
- เมื่อยืนยันแล้ว เรียก Engine RecordPositionClosed() ด้วย Current Bid/Ask ล่าสุดและ Close Reason

### 4.6 Position Mapping กับ Request Mapping

Position ที่ Reconciliation ใช้ยืนยัน Entry ต้องตรงกับ Candidate ที่ Request นั้นแทนอยู่ (Anchor หรือ Level Index) และ Symbol/Magic ของ Instance หากพบ Position ใหม่ที่ mapping ไปยัง Level อื่นโดยไม่สัมพันธ์กับ Request ปัจจุบัน ให้ถือเป็น inconsistency และไม่ resolve Request ด้วย Position นั้น

## 5. Test Design

เพิ่ม Experts/TGK/Tests/Grids/test_grid_level_runtime_coordinator.mq5

### Initialization / Quote
1. Initialize ด้วย Mode/Anchor/Step/Bounds/Level Count และ Quote ที่ถูกต้อง
2. ปฏิเสธ Input ไม่ถูกต้อง
3. Anchor เริ่ม ACTIVE ตาม Engine contract
4. Previous Quote ถูกเก็บเมื่อ Update สำเร็จ
5. Quote ไม่ถูกต้องไม่ทำให้ Previous Quote หรือ Level State เสียหาย
6. Stationary quote ไม่สร้าง Candidate ซ้ำ

### Candidate Management
7. ส่ง Candidate จาก Engine พร้อม Anchor/Level Index/Price ถูกต้อง
8. ไม่มี Candidate ส่ง NO_CANDIDATE
9. Candidate ที่ยังรอ Execution acknowledgement ไม่ถูกเปิดเผยซ้ำ
10. BUY เก็บ Candidate ที่ราคาต่ำที่สุด
11. SELL เก็บ Candidate ที่ราคาสูงที่สุด
12. Candidate ราคาเท่ากันไม่สร้าง Deferred ซ้ำ
13. Deferred Candidate ถูกตรวจ State ล่าสุดก่อนนำกลับมาใช้
14. Candidate ที่ไม่ eligible แล้วถูกทิ้ง

### Request Lifecycle
15. ปฏิเสธ/Failed terminal เรียก RecordEntryFailed และปลด Request
16. Accepted/Placed กลายเป็น unresolved แต่ Level ยังไม่ ACTIVE
17. Snapshot ไม่พบ Position แต่ Order ยัง pending ต้องคง unresolved
18. Terminal no-position/no-order จึง Resolve เป็น Failed
19. Position ที่ตรงกับ Request และ Mapping ถูกต้องจึง RecordEntryConfirmed
20. Position ที่ Mapping ไม่ตรง Request ห้ามยืนยัน Request
21. ระหว่าง unresolved ห้ามมี Request ที่สอง
22. หลัง Resolve จึงส่ง Deferred Candidate ที่ดีที่สุดได้
23. Invalid/duplicate Request acknowledgement ต้องไม่ทำให้ State เสียหาย

### Position Mapping / Reconciliation
24. Anchor mapping ใช้ index -1 และ Anchor flag
25. Grid Level mapping ต้องอยู่ในช่วง index
26. ปฏิเสธ Symbol/Magic mismatch
27. ปฏิเสธ Ticket ซ้ำและ Logical Level mapping ซ้ำ
28. ปฏิเสธ volume <= 0
29. Position ของ Instance ที่ mapping ไม่ได้ทำให้เกิด Error/Recovery
30. Position snapshot ที่ครบถ้วนและถูกต้อง reconcile ได้
31. Partial Close/Volume ลดลงแต่ยังมากกว่าศูนย์คง ACTIVE
32. Full Close จึงเปลี่ยน State
33. TP และ Non-TP ใช้ State transition ตาม Engine contract
34. Close Reason ไม่ทราบ/ขัดแย้งกันไม่เปลี่ยน State โดยการเดา
35. การเปลี่ยน State ของ Level หนึ่งไม่กระทบ Level อื่น

### Regression
36. Existing Grid Level Engine tests remain passing
37. Existing Runtime, Position Reconciler, Lifecycle, Identity, Persistence and Type tests remain passing

## 6. Expected Files

- เพิ่ม Include/BotTrade/Grid/GridLevelRuntimeCoordinator.mqh
- เพิ่ม Experts/TGK/Tests/Grids/test_grid_level_runtime_coordinator.mq5
- แก้ไฟล์เดิมเฉพาะเมื่อ Test/Contract พิสูจน์ว่าจำเป็น
- อัปเดต Architecture, Testing, README, PROJECT_STATUS และ Serena current-phase memory

## 7. Implementation Round 1 — Source Added (2026-11-07)

เพิ่มไฟล์:
- `Include/BotTrade/Grid/GridLevelRuntimeCoordinator.mqh`
- `Experts/TGK/Tests/Grids/test_grid_level_runtime_coordinator.mq5`

Implementation ปัจจุบัน:
- Initialize Engine พร้อม Symbol/Magic identity และเก็บ Previous/Current Bid/Ask
- Public `UpdatePrice()` รับ 4 Parameters เท่านั้น: `current_bid, current_ask, result, candidate`; Previous Quote เป็น State ภายใน Coordinator และส่งให้ Engine เอง
- รองรับ `RegisterInitialAnchorPosition()` เพื่อให้ Integration Layer ลงทะเบียน Position แรกที่เปิดจาก Initial Fill ด้วย Anchor mapping (`is_anchor=true, level_index=-1`)
- ส่ง Candidate จาก Engine เพียงครั้งเดียวต่อการเสนอ; ระหว่างรอ acknowledgement จะไม่ส่ง Candidate เดิมซ้ำ
- จำกัด unresolved Entry Request หนึ่งรายการ และเก็บ Deferred Candidate ที่ดีที่สุดตาม Mode
- Accepted Request จะยังไม่เปลี่ยน Level เป็น ACTIVE; ต้องรอ Position Snapshot ที่ Symbol/Magic และ Anchor/Level mapping ตรงกัน
- Terminal no-position/no-order เท่านั้นจึงเรียก RecordEntryFailed สำหรับ Request ที่ Accepted
- ตรวจ Position Snapshot: Ticket ซ้ำ, Mapping ซ้ำ, Symbol/Magic mismatch, invalid Anchor/Level index และ Volume <= 0
- Full Close ต้องมี Close Event ที่ mapping ตรงกับ Position เดิมและระบุ TP/Non-TP; Unknown หรือ missing reason ทำให้คืน ERROR
- Partial Close ที่ยังมี Position mapping เดิมและ Volume > 0 คง ACTIVE
- ไม่มี CTrade, Position scan หรือ Account API ใน Coordinator

ข้อจำกัด/ข้อควรตรวจใน Compile/Run:
- Snapshot ต้องเป็นรายการ Position ของ Instance ที่ครบถ้วน และ Close Events ต้องส่งโดย Integration Layer เมื่อ Logical Position หายไปจาก Snapshot
- Restart persistence ของ unresolved request/deferred candidate ยังอยู่นอก Scope
- Source/LSP inspection ไม่ใช่ผล MetaEditor compile

## 8. Implementation Gate

ผู้ใช้ยืนยันว่า Regression Baseline เดิมทั้ง 11 Tests ผ่านทั้งหมดเมื่อ 2026-11-07 ก่อน Source implementation

ขั้นต่อไปผู้ใช้ต้อง Compile/Run:
1. `test_grid_level_runtime_coordinator.mq5`
2. Grid Regression Tests เดิมทั้ง 11 ไฟล์

หากพบ Compile/Runtime Fail ให้หยุดและแก้ไขก่อนเริ่ม Phase ถัดไป

Assistant ไม่ได้รัน MetaEditor/MT5 เอง; Compile/Runtime acceptance ต้องมาจากผลที่ผู้ใช้รายงาน

## 9. Completion Criteria

- Coordinator และ Unit Tests compile ผ่าน
- Test ใหม่และ Regression Tests ทั้งหมดผ่านตามรายการที่ตกลง
- ไม่มี CTrade/Account API ใน Coordinator
- ไม่มีการเปิดซ้ำขณะ Request unresolved
- ACTIVE เกิดจาก Position reconciliation เท่านั้น
- Mapping/Partial Close/Full Close/Close Reason ปฏิบัติตาม Contract
- Docs และ Serena current-phase memory อัปเดตตามผลจริง
