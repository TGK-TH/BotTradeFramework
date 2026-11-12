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

### 5. Snapshot และ Journal Rotation — ข้อตกลงที่ยืนยันแล้ว (2026-11-12)

ใช้แนวทาง **Current-State Snapshot + Append-only Journal Rotation** เพื่อไม่ให้ Journal ไฟล์เดียวโตเกิน 16 MiB และเพื่อให้ Recovery ไม่ต้อง Replay ประวัติทั้งหมดตั้งแต่เริ่ม Instance

#### Snapshot เก็บอะไร

Snapshot เก็บเฉพาะข้อมูลปัจจุบันที่จำเป็นต่อการทำงานต่อ ได้แก่:

- Grid/Instance identity และ metadata ที่ใช้ตรวจว่า Snapshot เป็นของ Account, Server, Symbol และ Instance ที่ถูกต้อง
- Grid configuration ปัจจุบัน รวม Mode, GridStep, Bounds และ Anchor ตามที่มีผลอยู่
- Grid Level Index และ State ของทุก Level ที่ยังเป็นส่วนหนึ่งของ Grid configuration ปัจจุบัน แม้ Level นั้นไม่มี Position
- Position Mapping เฉพาะ Position ที่ยังเปิดอยู่และผ่าน Position Reconciliation แล้ว
- Entry Request ที่ยังไม่สิ้นสุด พร้อม Execution/Deal information ที่ยังจำเป็นต่อ Recovery
- Last applied Journal Sequence เพื่อให้ Replay ต่อจาก Checkpoint ได้อย่าง deterministic
- Schema Version และ integrity data เช่น Checksum

Snapshot เป็น **Current State Store ไม่ใช่ Trade History Store**: ไม่เก็บประวัติ Trades, Closed Positions หรือ Deal history ที่ไม่จำเป็นต่อ Recovery

#### Retention และเงื่อนไขลบข้อมูล

| สถานการณ์ | Snapshot policy |
|---|---|
| Position ปิดแล้วและ Reconciliation ยืนยันว่าไม่มี Volume เหลือ | ลบ Position Mapping ของ Position นั้น แต่เก็บ Grid Level Index/State |
| Level ไม่มี Position แต่ยังอยู่ใน Grid configuration ปัจจุบัน | เก็บ Level State ไว้ เช่น READY, WAIT_ACTIVATION หรือ WAIT_RETURN |
| GridStep เปลี่ยนและ Reset สำเร็จแล้ว | ลบ Level State เก่าที่ไม่อยู่ใน Grid configuration ใหม่ |
| GridMode เปลี่ยนและ Reset สำเร็จแล้ว | ลบ State ของ Mode เดิมหลังยืนยันว่าไม่มี Position เก่าเหลือ |
| มี Entry Intent/Request ที่ยังไม่สิ้นสุด | เก็บ Intent และข้อมูลที่จำเป็นต่อ Recovery; ห้ามลบข้อมูลที่เกี่ยวข้อง |
| Level อยู่นอก Bounds | ห้ามลบ State เพียงเพราะอยู่นอก Bounds; Bounds เป็น Eligibility Filter ไม่ใช่ Retention Rule |

Position/Deal/Request metadata ในอดีตลบออกจาก Snapshot ได้เมื่อไม่มีความจำเป็นต่อการ Reconcile หรือ Recovery อีกต่อไป โดยห้ามลบ unresolved request หรือ mapping ที่ยังมี Position อยู่

การ Prune Level State หลัง Mode/Step Reset ทำได้ต่อเมื่อ Reset ได้รับการยืนยันแล้ว, ไม่มี Position เก่าของ Instance เหลือ และไม่มี unresolved Entry Request ที่อ้างถึง Grid configuration เดิม

#### ขนาดและ Rotation

- Journal มี Safety Threshold 16 MiB ต่อ Active Journal Segment; เมื่อถึง Threshold ให้ทำ Checkpoint/Rotation ก่อน Append ถัดไป
- ข้อจำกัดใน Source ปัจจุบัน: `ReadJournal()` และ `TrimIncompleteTail()` ปฏิเสธไฟล์ที่เกิน 16 MiB ทำให้ Replay/Append ไม่ผ่านเมื่อเกินขนาดนี้; Rotation ยังไม่ Implement
- สร้าง Snapshot จาก Reduced Current State ณ Sequence N และตรวจสอบ Schema, Identity, Checksum และความสมบูรณ์ก่อนใช้
- Journal ใหม่ต้องเริ่มต่อจาก Sequence N+1; Replay ต้องไม่ Apply Record ที่ Snapshot ครอบคลุมแล้วซ้ำ
- ห้ามลบหรือเขียนทับ Journal เก่าจนกว่า Snapshot ใหม่และ Journal generation ใหม่จะถูก Flush, อ่านกลับ และตรวจสอบได้
- Recovery ต้องรองรับ Crash ทุกจุดระหว่าง Snapshot Write, Snapshot Commit, Journal Generation Switch และ Cleanup โดยต้องเลือกชุดข้อมูลที่สมบูรณ์ชุดหนึ่งได้เสมอ; ห้ามเกิดช่วงที่ทั้ง Snapshot และ Journal ที่จำเป็นต่อการกู้คืนหายไป
- Snapshot ต้องมี Size/Count Validation ของตัวเองด้วย เพราะขนาด Snapshot สัมพันธ์กับจำนวน Grid Levels, Active Positions และ unresolved Requests ไม่ใช่จำนวน Trades แต่ไม่ถือว่า Snapshot มีขนาดคงที่แบบไม่มีขีดจำกัด

รายละเอียดกลไก Commit/Generation Switch และ Crash Matrix จะถูกออกแบบและทดสอบใน Snapshot + Journal Rotation slice หลัง Typed Mapping Reducer ผ่านการทดสอบ
### 6. Order Comment

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

### E. Typed Mapping Payload & State Reducer — Test Contract

เพิ่ม Test EA แยกสำหรับ Typed Mapping Reducer โดยใช้ Record fixtures เท่านั้นและห้ามส่ง Trade Request จริง:

- Decode/Validate Payload ทุก Record Type และปฏิเสธ field ที่ขาด, type ผิด, enum ไม่รองรับ หรือ identifier ที่ไม่ใช่ Decimal String
- Replay Event ตาม Sequence แล้วได้ Current State ที่ deterministic และเทียบเท่ากันเมื่อสร้าง Reducer ใหม่
- Request ID ต้องไม่ซ้ำ; หนึ่ง Instance มี Unresolved Entry Request ได้ไม่เกินหนึ่งรายการ
- หนึ่ง Request ต้องอ้างถึง Logical Target ได้เพียงหนึ่งรายการ (Anchor หรือ Level) และห้ามมี Request/Mapping ขัดแย้งกัน
- Execution Accepted/Placed ต้องยังเป็น Pending/Reconciliation Required ไม่ใช่ Position Mapping ที่ยืนยันแล้ว
- รองรับหลาย Deal ต่อ Position Identifier เดียวจาก Partial Fill; ปฏิเสธ Deal/Request ที่ชี้ไปยัง Position Identifier ที่ขัดแย้งกัน
- Position Mapping ต้องตรวจ Instance, Symbol, Magic, Position Identifier และ Logical Target; ปฏิเสธ Position Identifier หรือ Active Logical Target ที่ถูกผูกซ้ำ
- Partial Close ปรับ Volume แต่ยังคง Active Mapping; Full Close จะถอด Position Mapping ได้เมื่อ Reconciliation ยืนยันว่าไม่มี Volume เหลือและ Lifecycle outcome ถูก Resolve แล้ว
- เมื่อถอด Position Mapping แล้ว ต้องคง Grid Level Index/State ตาม Retention Policy
- Comment ว่าง, เปลี่ยน หรือบอก Level ผิด ต้องไม่เปลี่ยนผล Reducer
- Identifier ที่มากกว่า 2^53 ต้อง Round-trip เป็น Decimal String ได้ครบทุกหลัก
- Invalid transition, duplicate event, out-of-order/conflicting association หรือ corrupted typed payload ต้องทำให้ Restore ล้มเหลวอย่างปลอดภัย ไม่ข้ามเงียบ ๆ
- Test ทุกกรณีเป็น Pure Unit Test และไม่มี CTrade/OrderSend/PositionClose

### F. Snapshot & Journal Rotation — Test Contract (ทำหลัง Reducer ผ่าน)

- Snapshot เก็บเฉพาะ Current State: Grid configuration/Level States, Active Position Mappings, unresolved Request และ Last applied Sequence
- Closed Position ที่ Reconciliation ยืนยันแล้วถูกถอดจาก Snapshot; Level State ยังคงอยู่
- Level ที่ไม่มี Position แต่ยังอยู่ใน Grid configuration ต้องคงอยู่ รวมถึง WAIT_RETURN
- Mode/Step Reset ที่ยังไม่ Confirmed ต้องไม่ Prune Level State เดิม; Prune ได้เมื่อ Reset สำเร็จ, ไม่มี Position เก่า และไม่มี unresolved Request ที่อ้างถึง config เดิม
- Level อยู่นอก Bounds ต้องไม่ถูก Prune ด้วยเหตุผลด้าน Bounds เพียงอย่างเดียว
- Snapshot ที่ Identity, Schema, Checksum, Sequence หรือ State ไม่ถูกต้องต้องถูกปฏิเสธ
- Rotation เมื่อ Journal ถึง 16 MiB ต้องรักษา Sequence ต่อเนื่องและไม่ Apply Event ซ้ำหรือทำ Event สูญหาย
- Failure/Crash Injection ทุกจุดระหว่าง Snapshot temp write, flush, validation, commit, journal generation switch และ old journal cleanup ต้อง Recover เป็น State ที่สมบูรณ์ได้
- Snapshot และ Journal generation ใหม่ต้องตรวจอ่านกลับได้ก่อนลบข้อมูล generation เก่า
- Snapshot Size/Count Limit ต้องปฏิเสธข้อมูลเกินขอบเขตอย่างปลอดภัย โดยไม่ทำลาย Snapshot/Journal generation ที่ใช้งานได้
- Restart หลัง Rotation ต้องได้ Current State เท่ากับ State ก่อน Restart

### G. Regression

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

1. **Typed Mapping Contract** — กำหนด Typed Payload Schema, legal state transitions และ Reducer output โดยไม่ผูกกับ Trade API
2. **Reducer Unit Tests ก่อน Source** — เพิ่ม `test_grid_entry_mapping_reducer.mq5` ด้วย Record fixtures ครอบคลุม normal flow, partial fill/close, duplicate และ conflict cases
3. **Typed Mapping Reducer** — Implement Payload validation และ deterministic Current-State reduction; ทดสอบร่วมกับ Storage โดยไม่ส่ง Trade Request
4. **Snapshot Serialization + Journal Rotation Design/Test** — กำหนด Snapshot schema, generation/commit protocol และ Crash Recovery Matrix จาก Reducer State
5. **Snapshot + Rotation Implementation** — เพิ่ม Snapshot/Rotation และ Failure/Crash Injection Tests; รักษา Journal 16 MiB เป็น Threshold ต่อ Active Segment
6. **Entry Execution Policy + Tests**
7. **CTrade Adapter + no-live-trade seam tests** — Intent ต้อง Persist/Flush ก่อนเรียก Trade API
8. **Coordinator Integration, Docs และ Regression** — ทบทวนผลรวมและให้ผู้ใช้ Compile/Run ใน MetaEditor/MT5
9. Demo Integration เป็นงานแยก ต้องได้รับอนุมัติจากผู้ใช้ก่อน

ก่อนแก้ Source Code ในแต่ละ Slice ให้รัน Grid Regression Tests 12 ไฟล์ตามรายการด้านล่างก่อน และรันซ้ำหลังแก้ Source Code

## Acceptance Criteria

- Mapping ใช้ Persistent Journal และ Identifier String; ไม่มีการใช้ Comment หรือ double เป็น Mapping Key
- Entry Intent ถูกบันทึกและ Flush ก่อนส่งคำสั่ง
- Request ที่ Accepted/Placed ยังไม่ทำให้ Level เป็น ACTIVE จนกว่าจะมี Position Reconciliation
- Symbol + Magic + Position Identifier ต้องตรงกันก่อนยืนยัน Mapping
- Restart แล้ว Restore Mapping ล่าสุดได้อย่าง deterministic
- Unit Tests ไม่ส่งคำสั่งซื้อขายจริง
- ผู้ใช้ยืนยัน Compile/Run Unit และ Regression ผ่านใน MetaEditor/MT5
- เอกสารระบุข้อจำกัดและผลทดสอบตามจริง
