# Grid Entry Execution Adapter — Round 1

สถานะ: **Implementation in progress — Persistent Journal foundation implemented and user-verified.**

อัปเดตล่าสุด: 2026-11-12

## เป้าหมาย

เพิ่มความสามารถในการส่ง Market Entry ของ Grid ผ่าน `CTrade` โดยเชื่อม Candidate จาก `CTGKGridLevelRuntimeCoordinator` กับ Persistent Mapping และยืนยัน Position จริงก่อน Level จะเปลี่ยนเป็น `ACTIVE`

Phase นี้เป็น Adapter/Mapping Round 1 ไม่ใช่ Production EA Event Handler Integration และไม่ใช่การเปิดใช้งาน Grid V1 ทั้งระบบ

## ข้อตกลงที่ยืนยันแล้ว

### 1. Persistent Mapping เป็น Source of Truth

- ใช้ Persistent Mapping เป็นแหล่งข้อมูลหลักเพียงแห่งเดียวสำหรับความสัมพันธ์ระหว่าง Entry Request, Order, Deal, Position และ Logical Grid Level
- ห้ามใช้ Order Comment เพื่อค้นหา Position, สร้าง/กู้คืน Mapping, ยืนยัน Fill หรือเปลี่ยน Level State
- Comment เป็น Human-readable metadata เท่านั้น ผู้ใช้ต้องมองเห็นได้ใน Trade/History UI ของ MT5
- Comment หาย ถูกตัดทอน หรือถูก Broker เปลี่ยน ต้องไม่ทำให้ Mapping ของระบบผิดพลาด

### 2. แยก Mapping Storage จาก Grid Snapshot เดิม

- คง `CTGKGridPersistence` และ Terminal Global Variables ไว้สำหรับ Grid Instance Snapshot และ Level State ตามหน้าที่เดิม
- เพิ่ม Storage component เฉพาะสำหรับ Entry Mapping ใช้ไฟล์ภายใน Terminal Data Folder ที่ `MQL5/Files` แยกไฟล์ต่อ Grid Instance
- ไม่ใช้ `FILE_COMMON` ใน Round 1 เพื่อไม่ให้คนละ MT5 Terminal แชร์ Mapping โดยไม่ตั้งใจ
- ชื่อไฟล์ต้องแยกด้วย Account/Instance identity และทำ Symbol/Instance ID ให้เป็นชื่อไฟล์ที่ปลอดภัย
- Identifier เช่น Order Ticket, Deal Ticket และ Position Identifier ต้อง serialize เป็น decimal String เพื่อรักษาค่าทุกหลัก ห้ามแปลง Identifier เป็น `double`
- File format ต้องมี Schema Version และ Record Sequence เพื่อรองรับการตรวจสอบ/กู้คืน

### 3. รูปแบบการบันทึก Mapping

ใช้ Append-only journal แบบ record ต่อบรรทัด เพื่อให้การบันทึกสถานะใหม่ไม่ต้องเขียนทับข้อมูลเดิมทั้งไฟล์

Record ขั้นต่ำที่ต้องรองรับ:
- Entry intent: Request ID, Instance ID, Symbol, Magic, Direction, Anchor/Level Index, Requested Volume, Comment metadata และสถานะเริ่มต้น
- Execution result: Request ID, request outcome, retcode, Order Ticket และ Deal Ticket เมื่อมี
- Deal association: Deal Ticket และ Position Identifier ที่ได้จากประวัติ Deal
- Position mapping: Position Identifier, Anchor flag หรือ Level Index, Symbol, Magic และ Volume ที่ยืนยันแล้ว
- Lifecycle update: partial/full close และสถานะล่าสุดของ Mapping

กติกาการเขียน:
- Persist Entry Intent ให้สำเร็จและ Flush ก่อนส่ง Trade Request จริง
- ถ้าเขียน Intent ไม่สำเร็จ ห้ามส่งคำสั่งซื้อขาย
- หลังส่ง Request ต้องบันทึกผลและ Identifier ที่ได้ ถ้าบันทึกผลไม่ได้ ให้คงสถานะ Recovery/Pending ที่ไม่อนุญาตให้ส่ง Request ซ้ำ และรายงานข้อผิดพลาดชัดเจน
- เมื่อเปิดใหม่ ให้ Replay Journal ตาม Sequence เพื่อสร้างสถานะล่าสุด
- Record สุดท้ายที่เขียนไม่ครบเพราะ Process หยุดกลางบรรทัด อาจถูกละเว้นได้ แต่ Record ที่สมบูรณ์แต่ผิดรูปแบบ/Sequence ซ้ำ/ขัดแย้งต้องทำให้ Restore ล้มเหลวอย่างปลอดภัย ไม่ข้ามเงียบ ๆ
- การเขียน Record ต้องตรวจผล FileWrite/FileFlush และ Error ทุกครั้ง

### 4. Mapping Semantics

- หนึ่ง Grid Instance มี Unresolved Entry Request ได้สูงสุดหนึ่งรายการ ตาม Coordinator Contract
- หนึ่ง Request ผูกกับ Logical Target ได้หนึ่งรายการ: Anchor (`is_anchor=true, level_index=-1`) หรือ Grid Level (`is_anchor=false, level_index>=0`)
- รองรับหลาย Deal ที่เกิดจาก Partial Fill ของ Order เดียวกันได้ แต่ต้องตรวจว่าทุก Deal ผูกกับ Position Identifier ที่สอดคล้องกัน
- ใช้ Position Identifier เป็นตัวระบุ Position เชิงตรรกะ; Position Ticket เป็นข้อมูลสำหรับการดำเนินการปัจจุบัน ไม่ใช่ Primary Mapping Key
- Position mapping จะถือว่ายืนยันได้เมื่อมีหลักฐานจาก Deal/Position ที่ตรวจสอบ Symbol + Magic + Position Identifier ได้ตรงกัน
- ห้ามอนุมาน Level จากราคา Fill โดยประมาณ
- หาก Request เดียวมี Position Identifier มากกว่าหนึ่งค่าที่ไม่สามารถอธิบายได้จาก Execution Model ที่รองรับ ให้เข้า Recovery Error แทนการเลือก Mapping เอง
- การเปลี่ยน Level เป็น `ACTIVE` ต้องรอ Position Reconciliation ที่ Coordinator ยอมรับ ไม่ใช่แค่ CTrade return true หรือ retcode `PLACED`

### 5. Order Comment

Comment สร้างจากข้อมูล Candidate ที่ระบบมีอยู่ก่อนส่ง Request เช่น:
- `TGK Grid | BUY | ANCHOR`
- `TGK Grid | BUY | L+3`
- `TGK Grid | SELL | L-2`

Comment:
- เป็นข้อความเพื่อให้มนุษย์ตรวจสอบใน MT5 เท่านั้น
- ไม่เก็บเป็น Mapping Key และห้าม Parse กลับมาเป็น Level Index
- ต้องคำนึงถึงข้อจำกัดความยาว Comment ของ Trade Server; หากต้องย่อ ให้ย่อเฉพาะ Comment โดยไม่กระทบ Persistent Mapping
- Test ต้องพิสูจน์ว่า Mapping ยังทำงานได้เมื่อ Comment ว่าง ถูกแก้ไข หรือไม่ตรงกับ Level จริง

## ขอบเขต Implementation Round 1

### In scope

1. Pure Entry Execution Policy สำหรับตรวจ Candidate, Identity, Direction, Volume และ duplicate/unresolved request
2. Persistent Entry Mapping Storage แยกจาก `GridPersistence.mqh`
3. Live Entry Execution Adapter ใช้ `CTrade` ส่ง Market BUY/SELL ด้วย Symbol และ Magic ของ Instance
4. Persist Intent ก่อนส่งคำสั่ง; บันทึก execution result และ Order/Deal identifiers หลังส่ง
5. สร้าง Human-readable Comment จาก Anchor/Level Candidate
6. เชื่อมผล Request กับ Coordinator โดย Accepted/Placed ไม่ถือเป็น Fill
7. Unit Tests ที่ไม่ส่งคำสั่งซื้อขายจริง
8. แยก Demo Integration Test EA สำหรับทดสอบ Live Entry หลัง Unit/Regression ผ่านและผู้ใช้อนุมัติให้ทดสอบ Demo

### Out of scope

- Production EA `OnInit/OnTick/OnTimer/OnTradeTransaction` Integration แบบสมบูรณ์
- การส่ง Entry จาก EA หลักที่เปิดใช้งานอัตโนมัติ
- การเปิดคำสั่งเงินจริงหรือ Demo โดย Unit Test
- การจัดการหลาย Position Identifier จาก Request เดียว หาก Execution Model ไม่รองรับ/ไม่สามารถ resolve ได้อย่างแน่นอน
- การเปลี่ยน Grid Level Engine หรือกฎเลือก Candidate
- การเปลี่ยน Grid Snapshot Schema เดิมโดยไม่จำเป็น
- การกู้คืน Deferred Candidate ของ Coordinator หลัง Restart นอกเหนือจากข้อมูล Entry Request/Mapping ที่จำเป็นใน Phase นี้

## Test Plan

ไฟล์ Unit Test:
- `Experts/TGK/Tests/Grids/test_grid_entry_mapping_storage.mq5` — Persistent Journal foundation
- `Experts/TGK/Tests/Grids/test_grid_entry_execution.mq5` — Entry Policy/Adapter (ยังไม่สร้าง)

### A. Entry Execution Policy

- ปฏิเสธ Candidate ที่ไม่ valid
- ปฏิเสธ Symbol/Magic/Instance identity ที่ไม่ตรงกัน
- ปฏิเสธ Direction ที่ไม่ตรงกับ Grid Mode
- ปฏิเสธ Volume ที่ไม่เป็นบวกหรือไม่ผ่าน Min/Max/Step validation
- ปฏิเสธ Request ซ้ำเมื่อมี Unresolved Request
- ยอมให้ Request ใหม่หลัง Request ก่อนหน้าถูกยืนยัน Failed หรือ Reconciled แล้วเท่านั้น
- Anchor และ Level Index ต้อง map ได้เพียงรูปแบบเดียวและถูกต้อง

### B. Persistent Mapping Storage

- Initialize แยกไฟล์ตาม Account/Instance
- Save Intent และ Restore หลังสร้าง Storage object ใหม่
- Identifier ที่มีค่ามากกว่า (2^{53}) ต้อง Round-trip ได้ครบทุกหลัก
- Append หลาย Event แล้ว Replay ได้ State ล่าสุดตาม Sequence
- รองรับหลาย Deal ต่อ Position Identifier เดียว
- Reject duplicate/conflicting Request ID, Sequence, Identity หรือ Logical Target
- ปฏิเสธไฟล์ที่ Schema ไม่รองรับหรือ Record สมบูรณ์แต่ผิดรูปแบบ
- จัดการ Journal ที่มีบรรทัดสุดท้ายไม่สมบูรณ์จากการหยุดกลางการเขียน
- Write/Flush failure ต้องไม่รายงานว่า Save สำเร็จ
- File ของ Instance หนึ่งต้องไม่ Restore เป็นของอีก Instance หรือ Account

### C. Comment independence

- สร้าง Comment สำหรับ BUY/SELL และ Anchor/Level
- Mapping Restore สำเร็จแม้ Comment ว่าง
- Mapping Restore สำเร็จแม้ Comment ถูกเปลี่ยนเป็นข้อความอื่น
- Comment ที่บอก Level ผิดต้องไม่ทำให้ระบบเปลี่ยน Mapping

### D. Entry Adapter Policy/Boundary

- Intent ต้องถูก Persist ก่อนเรียก Trade API (ตรวจด้วย Fake/Test seam หรือ policy contract)
- Persistence failure ต้องไม่ส่งคำสั่ง
- ตรวจผล CTrade boolean และ retcode แยกกัน
- DONE/DONE_PARTIAL/PLACED เป็นเพียง Request outcome ที่ต้อง Reconcile
- MARKET_CLOSED และผลล้มเหลวต้องไม่ทำให้ Level เป็น ACTIVE
- Result Order/Deal Ticket ต้องถูกเก็บเป็น String โดยไม่เสีย precision
- Execution result persistence failure ต้องล็อก Instance ไม่ให้ส่ง Request ซ้ำโดยไม่ตรวจ Recovery

### E. Regression

ก่อนแก้ Source Code ให้รัน Grid Regression Tests ชุดล่าสุด 12 ไฟล์ที่ผู้ใช้ยืนยัน PASS เมื่อ 2026-11-09 และรันซ้ำหลังแก้ Source Code:
1. `test_grid_level_runtime_coordinator.mq5`
2. `test_grid_level_engine.mq5`
3. `test_grid_order_execution.mq5`
4. `test_grid_runtime_orchestrator.mq5`
5. `test_grid_position_reconciler.mq5`
6. `test_grid_lifecycle.mq5`
7. `test_grid_state_machine.mq5`
8. `test_grid_types.mq5`
9. `test_grid_persistence.mq5`
10. `test_grid_identity.mq5`
11. `test_grid_identity_multichart.mq5`
12. `test_grid_restart_persistence.mq5`

Unit Tests ต้องไม่ส่ง Trade Request จริง การ Demo Integration Test จะเป็นขั้นตอนแยกและต้องได้รับการยืนยันจากผู้ใช้ก่อนเริ่ม

## ลำดับงานที่เสนอ

1. ตรวจ Test Baseline 12 ไฟล์ก่อนเริ่ม Source Change
2. สร้าง Test Contract สำหรับ Entry Policy และ Mapping Storage
3. Implement Persistent Mapping Journal + Unit Test
4. Implement Entry Execution Policy + Unit Test
5. Implement Entry Execution Adapter + Unit Test โดยแยก Trade API ผ่าน test seam
6. Review ผลรวม, Docs และ Regression
7. ขอผู้ใช้ Compile/Run Unit + Regression ใน MetaEditor/MT5
8. หลัง PASS จึงเสนอ Demo Integration แยกต่างหาก

## ความคืบหน้า Implementation — Persistent Journal Foundation (2026-11-09)

เพิ่ม Source/Test เบื้องต้นแล้ว แต่ยังไม่ถือว่า Storage หรือ Phase นี้เสร็จสมบูรณ์:

- `Include/BotTrade/Grid/GridEntryMappingStorage.mqh`
  - `CTGKGridEntryMappingStorage` จัดเก็บ Journal แยกตาม Account Login, Server, Symbol และ Instance ID ภายใต้ Terminal `MQL5/Files`; ไม่ใช้ `FILE_COMMON`
  - ใช้ Append-only Binary File ที่เก็บ Record เป็นบรรทัด ASCII; Payload เข้ารหัส UTF-8 เป็น Hex เพื่อไม่ให้ delimiter/newline ในข้อมูลทำให้ Record แตก
  - แต่ละ Record มี Schema Version, Sequence, Record Type และ Checksum
  - `Replay()` ตรวจ Schema, Sequence ต่อเนื่อง, Record Type, Checksum และ Payload encoding; Record สมบูรณ์ที่ผิดรูปแบบทำให้ Replay ล้มเหลว
  - ยอมละเว้นเฉพาะท้ายไฟล์ที่ไม่มี newline ปิด Record และ `Append()` จะตัด Incomplete Tail ก่อนเขียน Record ใหม่ โดยเขียนส่วนที่สมบูรณ์ลงไฟล์ชั่วคราว, Flush และแทนที่ Journal เดิม (ไม่ใช้ `FileResize()` ซึ่งไม่มีใน MQL5)
  - `Append()` ตรวจผล `FileWriteArray`, `GetLastError()` และ `FileFlush` ก่อนคืนค่า success
  - Storage รับ Payload เป็น Opaque String; Identifier ใน Payload ต้องเป็น Decimal String ตาม Contract และ Storage ไม่แปลงเป็นตัวเลข
  - Storage ไม่ Parse หรือใช้ Order Comment ใน Logic ใด ๆ
- `Experts/TGK/Tests/Grids/test_grid_entry_mapping_storage.mq5`
  - ทดสอบ Identity validation, Append/Replay, Sequence, Identifier ที่เกิน (2^{53}), Instance isolation, Comment independence, Incomplete Tail และ Malformed Complete Record
  - เป็น Test EA ที่ไม่มี Trade Request
- ขอบเขตที่ยังไม่ทำใน Foundation นี้: Typed Mapping Payload Codec/Reducer ที่ตรวจ Request/Deal/Position/Logical Target conflicts, Failure Injection สำหรับ Write/Flush, Entry Policy, CTrade Adapter และ Coordinator Integration
- **ผล Compile/Runtime (ผู้ใช้รายงาน 2026-11-12): PASS** — `GridEntryMappingStorage.mqh` Compile ผ่าน, `test_grid_entry_mapping_storage.mq5` ผ่าน และ Grid Regression Tests ทั้ง 12 ไฟล์ผ่านครบหลังการแก้ไข รวม 13 Test EAs ในรอบตรวจสอบนี้
- การยืนยันนี้ครอบคลุม Persistent Journal Foundation และ Regression Contract เท่านั้น; ยังไม่ครอบคลุม Typed Mapping Reducer, Entry Policy, CTrade Adapter หรือ Coordinator Integration

## Acceptance Criteria

- Mapping ใช้ Persistent Journal และ Identifier String; ไม่มีการใช้ Comment หรือ double เป็น Mapping Key
- Entry Intent ถูกบันทึกและ Flush ก่อนส่งคำสั่ง
- Request ที่ Accepted/Placed ยังไม่ทำให้ Level เป็น ACTIVE จนกว่าจะมี Position Reconciliation
- Symbol + Magic + Position Identifier ต้องตรงกันก่อนยืนยัน Mapping
- Restart แล้ว Restore Mapping ล่าสุดได้อย่าง deterministic
- Unit Tests ไม่ส่งคำสั่งซื้อขายจริง
- ผู้ใช้ยืนยัน Compile/Run Unit และ Regression ผ่านใน MetaEditor/MT5
- เอกสารระบุข้อจำกัดและผลทดสอบตามจริง
