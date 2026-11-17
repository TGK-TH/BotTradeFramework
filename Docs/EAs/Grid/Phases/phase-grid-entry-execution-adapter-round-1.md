# Grid Entry Execution Adapter — Round 1

สถานะ: **Persistence/Mapping foundation ผ่านตามผลผู้ใช้รายงาน 2026-11-15; Entry Execution Policy Phase 1 Design และ Phase 2 Test-First Specification (44 Cases) Finalized เมื่อ 2026-11-17; Policy Implementation (Phase 3) และ CTrade Entry Adapter ยังไม่เริ่ม.**

อัปเดตล่าสุด: 2026-11-17

สำหรับรายละเอียด Policy ที่เป็น Authority ให้ใช้ [Grid Entry Execution Policy — Design Baseline และ Test Plan](phase-grid-entry-execution-policy.md) ซึ่งเป็นเอกสารใหม่กว่าและ supersede รายการ Policy Test เบื้องต้นในเอกสารนี้

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
- Entry intent: Request ID, Instance ID, Symbol, Magic, Direction, Anchor/Level Index, Requested Volume และสถานะเริ่มต้น; Order Comment สร้าง/จัดการแยกจาก Typed Mapping Payload
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

#### Generation, Manifest และ Commit Protocol — ข้อตกลงเพิ่มเติม (2026-11-14)

Retention หลัง Rotation และ Cleanup สำเร็จต้องมีขอบเขตชัดเจน:

- มี Committed Snapshot ปัจจุบัน 1 ไฟล์
- มี Active Journal ปัจจุบัน 1 ไฟล์
- ไม่มี Journal Generation เก่าหรือ Temporary Data File ค้างหลัง Cleanup สำเร็จ
- มี Manifest Slot คงที่ 2 ไฟล์ คือ manifest_A.dat และ manifest_B.dat; ทั้งสองไฟล์เป็น metadata slot ที่เขียนทับสลับกัน ไม่ใช่ประวัติสะสม
- ระหว่าง Rotation อนุญาตให้ Generation เก่าและใหม่อยู่ร่วมกันชั่วคราว เพื่อรักษาความสามารถในการกู้คืน

รูปแบบชื่อไฟล์เชิงแนวคิด:
- snapshot_<generation>.dat
- journal_<generation>.log
- manifest_A.dat
- manifest_B.dat

Manifest ต้องระบุอย่างน้อย Schema Version, Storage Identity, Commit Epoch, Snapshot Generation, Journal Generation, Snapshot Checkpoint Sequence และ Integrity Checksum โดยต้องตรวจ Identity ให้ตรงกับ Account/Server/Symbol/Instance ก่อนใช้

ลำดับ Rotation:
1. หยุด Append ชั่วคราวและใช้ Reducer Current State ณ Sequence N เป็น Checkpoint
2. Serialize Snapshot generation ใหม่ลง Temporary File; Flush, ปิดไฟล์, อ่านกลับ และตรวจ Schema/Identity/Sequence/Checksum/State
3. สร้าง Journal generation ใหม่ที่เริ่มรับ Record ถัดไปจาก Sequence N+1; Flush, ปิดไฟล์, อ่านกลับ และตรวจ Header/Base Sequence/Identity/Integrity
4. เลือก Manifest Slot ที่ไม่ใช่ Slot ของ Manifest ปัจจุบัน แล้วเขียน Commit Metadata ชุดใหม่ลง Slot นั้น
5. Flush, ปิดไฟล์ และอ่าน Manifest กลับมาตรวจทุก Field และ Checksum อีกครั้ง; เมื่อ Manifest ใหม่สมบูรณ์และชี้ไปยัง Snapshot/Journal ที่ตรวจผ่านแล้ว ถือว่า Commit สำเร็จ
6. หลัง Commit เท่านั้น จึงลบ Snapshot/Journal generation เก่าที่ไม่ถูกอ้างถึงโดย Current Manifest
7. ตรวจ Directory อีกครั้ง; เมื่อ Cleanup สำเร็จต้องเหลือ Snapshot/Journal ปัจจุบันอย่างละหนึ่งไฟล์ และไม่มี Temporary/Old Generation Data File

Manifest Slot ที่ไม่ได้ Active อาจยังมี Metadata ของ Generation ก่อนหน้าได้ แม้ Data File ของ Generation นั้นถูก Cleanup แล้ว; ตอนเลือก Manifest ต้องตรวจว่า Data Files ที่ถูกอ้างถึงมีอยู่และผ่าน Validation ด้วย การมี Manifest เก่าเพียงอย่างเดียวไม่ใช่เหตุให้เก็บ Old Generation Data Files ไว้ตลอดไป

Commit Point คือการที่ Manifest Slot ใหม่ถูกเขียน, Flush และอ่านกลับแล้วผ่าน Validation ไม่ใช่เพียงการสร้าง Snapshot หรือ Journal ใหม่เสร็จ หาก Manifest ใหม่ไม่ผ่าน Validation ให้ใช้ Generation เดิมและห้าม Cleanup ข้อมูลเดิม

Recovery หลัง Restart:
- ตรวจ Manifest ทั้งสอง Slot แล้ว Validate Schema, Identity, Checksum และ Data Files ที่แต่ละ Slot อ้างถึง
- เลือก Manifest ที่ Valid และมี Commit Epoch สูงสุด
- ตรวจ Snapshot และ Journal Generation ที่ Manifest นั้นอ้างถึง แล้ว Restore Snapshot ณ Sequence N และ Replay Journal ต่อจาก N+1
- หาก Manifest ใหม่ยังไม่ Commit หรือไม่สมบูรณ์ ให้ใช้ Manifest เก่าที่ยัง Valid
- หาก Manifest ใหม่ Commit แล้ว แต่เกิด Crash ระหว่าง Cleanup ให้ใช้ Generation ใหม่และทำ Cleanup ซ้ำ
- หากไม่มี Manifest/Data Set ที่ Valid ให้เข้า Recovery Error และห้ามส่ง Trade Request; ห้ามเดาหรือประกอบ State จากไฟล์คนละ Generation

#### Crash Recovery Matrix

| จุดที่เกิด Crash | สิ่งที่อาจเหลืออยู่ | Recovery ที่คาดหวัง |
|---|---|---|
| ระหว่างเขียน Snapshot Temporary | Old Generation + Snapshot temp บางส่วน | ใช้ Old Manifest/Generation; ละทิ้ง temp |
| Snapshot Flush/Read-back ก่อนผ่าน Validation | Old Generation + Snapshot temp | ใช้ Old Generation; ห้าม Commit |
| หลัง Snapshot ผ่าน แต่ก่อน Journal ใหม่ผ่าน Validation | Old Generation + New Snapshot/Journal บางส่วน | ใช้ Old Generation |
| หลัง Data Files ใหม่ผ่าน Validation แต่ก่อนเขียน Manifest | Old Generation + New Data Files | ใช้ Old Generation; New Files เป็น Orphan ที่ Cleanup ได้ภายหลัง |
| ระหว่างเขียน Manifest Slot ใหม่ | Old Manifest ที่ Active + Manifest Slot ใหม่อาจไม่สมบูรณ์ | ใช้ Old Manifest; ห้ามลบ Old Data |
| Manifest ใหม่เขียน/Flush/Read-back ผ่านแล้ว แต่ยังไม่ Cleanup | Old + New Generations และ Manifest ใหม่ | ใช้ New Generation; ทำ Cleanup ต่อ |
| ระหว่างลบ Old Generation | New Generation สมบูรณ์ + Old Files บางส่วน | ใช้ New Generation; ทำ Cleanup ซ้ำ |
| หลัง Cleanup สำเร็จ | New Snapshot + New Journal + Manifest Slots 2 ไฟล์ | ใช้ New Generation ตามปกติ |

ข้อกำหนดเพิ่มเติม:
- การเขียน Manifest ใหม่ต้องไม่ทำลาย Manifest Slot ที่กำลัง Active; หาก Slot ใหม่เขียนไม่สมบูรณ์ Slot Active เดิมต้องยังอ่านได้
- Generation ที่ Manifest ปัจจุบันอ้างถึงต้องเป็น Immutable สำหรับ Snapshot; Journal เป็น Append-only
- การ Append หลัง Commit ต้องเริ่มที่ Sequence N+1 เท่านั้น
- การ Cleanup ต้องไม่ลบ Data File ที่ Current Manifest อ้างถึง
- Orphan/Temporary Files ลบได้เมื่อยืนยันแล้วว่า Current Manifest และ Data Set ปัจจุบันผ่าน Validation
- หาก Cleanup ล้มเหลว ให้แจ้ง Recovery/Maintenance Error; ห้ามลบไฟล์อื่นเพื่อพยายามบังคับให้เหลือจำนวนไฟล์ตาม Policy

#### Capacity Limits และ Overflow Policy — ข้อตกลงที่ยืนยันแล้ว (2026-11-14)

| รายการ | Hard Limit | ขอบเขต |
|---|---:|---|
| Grid Levels | 1,000 | ต่อ Grid Instance; คำนวณจำนวนจริงจาก Bounds, Grid Step และ Anchor โดยนับ Anchor เป็นหนึ่ง Level และรวมทั้งสองฝั่ง |
| Position Mappings | 1,000 | ต่อ Grid Instance; หนึ่ง Logical Grid Level มี Position Mapping ได้ไม่เกินหนึ่งรายการ |
| Deal Associations | 100 | ต่อ Request; รองรับ Partial Fills หลาย Deals |
| Unresolved Requests | 1 | ต่อ Grid Instance |
| Snapshot File | 16 MiB | ขนาดไฟล์สูงสุด |
| Active Journal Segment | 16 MiB | ขนาดไฟล์สูงสุดต่อ Segment |
| Serialized Record | 64 KiB | ขนาดหลัง Serialize รวม Metadata, Checksum และ Record Delimiter; ใช้กับ Journal และ Snapshot |
| String Field | 4 KiB | ความยาวสูงสุดต่อ String Field หลัง Encode ตามรูปแบบ Serialization |
| Serialization Buffer | 16 MiB | Buffer สูงสุดสำหรับการ Serialize |

กติกาเพิ่มเติม:
- Grid Level Capacity คำนวณจาก Geometry จริง ห้ามตัด Level ให้เหลือเท่าที่ Capacity รองรับ; หากจำนวนที่ต้องใช้เกิน 1,000 ให้ปฏิเสธการสร้างหรือ Reset Grid
- เมื่อ `POSITION_MAPPING` ผ่าน Validation แล้ว ให้ Prune Deal Associations ที่ไม่จำเป็นต่อ Recovery ออกจาก Current State
- ขนาด Record ให้นับ Byte หลัง Serialize ไม่ใช่จำนวนตัวอักษร; String Field ให้วัดตาม Byte ที่ใช้ใน Encoding ของ Storage
- หาก Field, Record, Buffer, Snapshot, Journal หรือ State Count เกิน Limit ให้ปฏิเสธการดำเนินการที่ทำให้เกินขอบเขต ห้าม Truncate หรือ Prune ข้อมูลที่ยังจำเป็นต่อ Recovery
- Snapshot/Rotation ที่เกิน Limit ต้องไม่ Commit Generation ใหม่ และต้องคง Generation เดิมที่ Valid ไว้
- หากไม่สามารถรักษา State ภายในขอบเขตได้อย่างปลอดภัย ให้เข้า Recovery/Maintenance Error และห้ามส่ง Entry Request ใหม่

Boundary Tests ต้องครอบคลุมค่าต่ำกว่า/เท่ากับ/เกิน Limit, ขนาด Record และ String ที่ตรงขอบเขตและเกินหนึ่ง Byte, จำนวน Level/Mapping/Deal Association สูงสุด, Snapshot/Buffer เต็ม และการยืนยันว่า Rotation ที่เกิน Limit ไม่ทำลาย Generation เดิม

#### Overflow, Journal Full และ Recovery Status — ข้อตกลงที่ยืนยันแล้ว (2026-11-14)

**กติกาเมื่อ Capacity เต็ม**
- Grid Levels เกิน 1,000: ปฏิเสธ Grid Initialization/Reset; ห้ามตัดจำนวน Level ให้เหลือ 1,000
- Position Mappings ครบ 1,000: ปฏิเสธ `POSITION_MAPPING` รายการใหม่, เข้า `RECOVERY_ERROR` และบล็อก Entry ใหม่; เก็บ Mapping เดิมทั้งหมดไว้
- Deal Associations ครบ 100 ต่อ Request: ปฏิเสธ Association ใหม่, เข้า `RECOVERY_ERROR` และบล็อก Entry ใหม่; ห้ามเดาหรือเลือก Position Identifier เอง
- Snapshot เกิน 16 MiB: ยกเลิก Rotation ก่อน Commit และคง Generation เดิมที่ Valid
- Serialization Buffer เกิน 16 MiB: ยกเลิก Serialization ก่อนเขียนไฟล์
- Serialized Record เกิน 64 KiB หรือ String Field เกิน 4 KiB: ปฏิเสธ Record โดยไม่ Truncate
- ทุกกรณีต้องรักษาข้อมูลที่จำเป็นต่อ Recovery; ห้ามลบ Position Mapping ที่ยังมี Position เปิดอยู่หรือ Unresolved Request เพื่อให้ผ่าน Capacity

**Active Journal เต็ม**
- ก่อน Append ต้องตรวจขนาด Record และขนาด Journal รวมหลัง Append
- หาก Append ถัดไปทำให้ Journal เกิน 16 MiB ให้ Pause Append และทำ Snapshot + Rotation ก่อน
- หลัง Rotation Commit สำเร็จ จึง Append Record ลง Journal Generation ใหม่
- หาก Rotation ไม่สำเร็จ ให้เข้า `MAINTENANCE_ERROR`, บล็อก Entry Request ใหม่ และคง Generation เดิมไว้; ห้ามลบ Journal เดิมเพื่อเปิดพื้นที่

**Recovery Status**
| Status | ความหมายและพฤติกรรม |
|---|---|
| `NORMAL` | State และ Storage ผ่าน Validation; ทำงานและอนุญาต Entry ใหม่ตามปกติ |
| `MAINTENANCE_ERROR` | Storage, Rotation หรือ Cleanup มีปัญหา แต่ Current State ที่ Commit แล้วยังตรวจสอบได้; บล็อก Entry ใหม่ แต่ยังอนุญาต Inspection และ Reconciliation ของ Position เดิม |
| `RECOVERY_ERROR` | ไม่สามารถยืนยัน Current State/Mapping ได้ เช่น Mapping หรือ Deal Association Capacity เต็ม; บล็อก Entry ใหม่และต้องตรวจสอบก่อน Resume |

การบล็อก Entry ใหม่ไม่ใช่การละทิ้ง Position ที่เปิดอยู่: การตรวจสอบและ Reconciliation/การดูแล Position เดิมต้องแยกจาก Permission ในการเปิด Position ใหม่ และห้าม Error Status ทำให้ระบบลืม Position เดิม

Boundary/Failure Tests ต้องตรวจทั้ง Status Transition, การบล็อก Entry ใหม่, ความสามารถในการ Inspection/Reconciliation ของ Position เดิม, การคงข้อมูลเดิม และ Recovery หลัง Restart

กลไกนี้เป็น Design Contract ที่ตกลงแล้ว ส่วนการพิสูจน์พฤติกรรม File API/การ Replace/การลบไฟล์และ Failure Injection จะอยู่ใน Implementation/Test slice

#### Snapshot + Journal Rotation — Implementation Draft (2026-11-14)

เพิ่ม Source:
- `Include/BotTrade/Grid/GridEntryMappingSnapshotStorage.mqh` — dual Manifest slots, immutable Snapshot/Journal generations, Checksum/Identity/Sequence validation, Flush + Read-back, Commit Point, restart Recovery, repeatable Cleanup และ Journal tail repair
- `Include/BotTrade/Grid/GridEntryMappingReducer.mqh` — เพิ่ม `ExportSnapshot()` / `RestoreSnapshot()` เพื่อ serialize Current State ของ Config, ทุก non-anchor Level State, Active Position Mappings และ Unresolved Request/Deal Associations ที่ยังจำเป็น
- `Experts/TGK/Tests/Grids/test_grid_entry_mapping_snapshot.mq5` — no-trading tests สำหรับ Snapshot/Rotation/Recovery/Capacity/Failure Injection

กติกาใน Reducer ที่เพิ่มให้ตรงกับ Capacity Contract:
- คำนวณจำนวน Level จาก `floor((UpperBound-Anchor)/GridStep) + floor((Anchor-LowerBound)/GridStep) + 1`; Anchor รวมอยู่ในจำนวน 1,000 Levels
- `level_index=-1` สงวนให้ Anchor; Grid Level ใช้ Index ตั้งแต่ 0 ถึง `level_count-2`
- เมื่อ `RESET_COMMITTED` สำเร็จ Reducer สร้าง READY State ให้ทุก non-anchor Level; Snapshot จึงเก็บ State ของทุก Level แม้ไม่มี Position
- Position Mapping จำกัด 1,000; Deal Associations จำกัด 100 ต่อ Unresolved Request; หลัง Position Mapping สำเร็จให้ Prune Deal Associations ที่ไม่จำเป็นแล้ว
- Snapshot Restore ตรวจ Identity, Checkpoint, Geometry/Level Count, Record Counts, Mapping Relationships และ Capacity ก่อนรับ State

Coverage ที่เพิ่มใน Snapshot Test:
- Current-State Snapshot round-trip ทั้ง Active Position, Level States และ Unresolved Request ที่มีหลาย Deal Associations
- Snapshot Checkpoint N + Journal Replay เริ่ม N+1; Position Ticket refresh หลัง Restore
- Rotation สลับ Manifest A/B, ลบ Old Generation และ Temporary Files หลัง Commit
- Crash ก่อน Commit ใน Snapshot/Journal/Manifest Write และ Read-back; Crash หลัง Manifest Commit; Crash ระหว่าง Cleanup
- Recovery เลือก Older Valid Generation เมื่อ Data Set ใหม่เสียหาย และเข้า `RECOVERY_ERROR` เมื่อไม่มี Valid Data Set
- Incomplete Journal Tail ถูกละเว้นตอน Replay และซ่อมก่อน Append ครั้งถัดไป
- Journal 16 MiB Rotation, Snapshot เกิน 16 MiB ต้องไม่ทำลาย Generation เดิม, Record 64 KiB, String Field 4 KiB, Position 1,000/1,001 และ Deal 100/101
- `MAINTENANCE_ERROR` บล็อก Entry Intent ใหม่ แต่ยังรับ Lifecycle/Management Record ของ State เดิมได้เมื่อ Journal ยังเขียนได้

**สถานะการตรวจสอบ:** Assistant ตรวจ `git diff --check`, final newline, delimiter balance และ feature/failure-matrix coverage แบบ Static เท่านั้น ยังไม่ได้ Compile หรือ Run MetaEditor/MT5 และยังไม่ได้พิสูจน์ File API บน Terminal จริง ผู้ใช้ต้อง Compile/Run `test_grid_entry_mapping_snapshot.mq5`, `test_grid_entry_mapping_reducer.mq5` (Reducer source เปลี่ยนเพิ่ม) และ Grid Regression Tests ทั้งหมดก่อนถือว่า Slice นี้ผ่าน ไม่มี CTrade/OrderSend หรือ Trade Request ใน Test ใหม่นี้

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
- `Experts/TGK/Tests/Grids/test_grid_entry_mapping_storage.mq5` — Persistent Journal foundation (ผู้ใช้ยืนยัน PASS)
- `Experts/TGK/Tests/Grids/test_grid_entry_mapping_reducer.mq5` — Typed Mapping Reducer (ผู้ใช้ยืนยัน Compile/Run และ Regression ผ่าน 2026-11-14)
- `Experts/TGK/Tests/Grids/test_grid_entry_mapping_snapshot.mq5` — Snapshot Serialization/Rotation (ผู้ใช้ยืนยัน PASS 2026-11-14)
- `Experts/TGK/Tests/Grids/test_grid_entry_execution_policy.mq5` — Pure Entry Execution Policy Test-First Specification (44 Cases; Phase 2 Finalized; ยังไม่ได้ Compile/Run ใน MT5)
- `Experts/TGK/Tests/Grids/test_grid_entry_execution.mq5` — CTrade Entry Adapter/Integration tests (ยังไม่สร้าง)

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

#### Typed Payload Schema v1 (Reducer Round 1)

Reducer consumes `STGKGridMappingJournalRecord` and requires exact field count/order. Payload values are pipe-delimited; identifiers remain decimal Strings and are never converted to numeric types. Unknown fields, empty fields, unsupported versions, invalid enums, or malformed numeric tokens reject Replay.

| Journal Record Type | Payload fields (after `v1`) |
|---|---|
| `ENTRY_INTENT` | `request_id, symbol, magic, mode, target_kind, level_index, requested_volume, config_epoch, instance_id` |
| `EXECUTION_RESULT` | `request_id, outcome, order_ticket, deal_ticket` |
| `DEAL_ASSOCIATION` | `request_id, deal_ticket, position_identifier, deal_volume` |
| `POSITION_MAPPING` | `request_id, symbol, magic, target_kind, level_index, position_identifier, position_ticket, reconciled_volume, config_epoch, instance_id` |
| `LIFECYCLE_UPDATE / RESET_COMMITTED` | `config_epoch, mode, grid_step, lower_bound, upper_bound, anchor_price, level_count` |
| `LIFECYCLE_UPDATE / LEVEL_STATE` | `config_epoch, level_index, level_state` |
| `LIFECYCLE_UPDATE / POSITION_VOLUME` | `position_identifier, remaining_volume` |
| `LIFECYCLE_UPDATE / POSITION_TICKET` | `position_identifier, current_position_ticket` |
| `LIFECYCLE_UPDATE / POSITION_CLOSED` | `position_identifier, close_reason, next_level_state` (`NONE` for Anchor) |

Reducer rules:
- `RESET_COMMITTED` establishes a new configuration epoch and may prune old Level State only when there are no active Positions or unresolved Requests.
- `ENTRY_INTENT` is accepted only for the active configuration and a valid logical target; one unresolved Request is allowed.
- `PLACED`, `DONE`, `DONE_PARTIAL` and `ACCEPTED` remain unresolved until validated Position Mapping; `FAILED`, `REJECTED` and `MARKET_CLOSED` resolve the Request without creating a Position.
- Deal Associations for one Request may contain multiple Deal Tickets, but all must share one Position Identifier and total associated volume cannot exceed requested volume.
- `POSITION_MAPPING` requires an accepted execution result and at least one consistent Deal Association, validates Instance ID + Symbol + Magic + Position Identifier + Position Ticket + Logical Target, and changes a Level to `ACTIVE` only after this reconciliation event.
- Partial close reduces remaining volume while preserving Position Mapping and `ACTIVE`; `POSITION_TICKET` may refresh the execution handle while preserving Position Identifier; `POSITION_CLOSED` represents confirmed zero-volume reconciliation, removes Position/Deal/Request mapping data, and retains the Level State supplied by the lifecycle outcome.
- Order Comment is not a Typed Payload field and is not read by Reducer. It remains separate human-readable metadata.
- Any invalid transition or conflict makes the Reducer Replay fail; it does not skip invalid complete records.

เพิ่ม Test EA แยกสำหรับ Typed Mapping Reducer โดยใช้ Record fixtures เท่านั้นและห้ามส่ง Trade Request จริง:

- Decode/Validate Payload ทุก Record Type และปฏิเสธ field ที่ขาด, type ผิด, enum ไม่รองรับ หรือ identifier ที่ไม่ใช่ Decimal String
- Replay Event ตาม Sequence แล้วได้ Current State ที่ deterministic และเทียบเท่ากันเมื่อสร้าง Reducer ใหม่
- Request ID ต้อง unique ต่อ Instance โดย Adapter ต้องสร้าง ID แบบ monotonic/unique เพื่อไม่ต้องเก็บประวัติ Request ที่จบแล้วไว้ตลอดไป; Reducer ปฏิเสธ ID ที่ซ้ำใน Current State และหนึ่ง Instance มี Unresolved Entry Request ได้ไม่เกินหนึ่งรายการ
- หนึ่ง Request ต้องอ้างถึง Logical Target ได้เพียงหนึ่งรายการ (Anchor หรือ Level) และห้ามมี Request/Mapping ขัดแย้งกัน
- Execution Accepted/Placed ต้องยังเป็น Pending/Reconciliation Required ไม่ใช่ Position Mapping ที่ยืนยันแล้ว
- รองรับหลาย Deal ต่อ Position Identifier เดียวจาก Partial Fill; ปฏิเสธ Deal/Request ที่ชี้ไปยัง Position Identifier ที่ขัดแย้งกัน
- Position Mapping ต้องตรวจ Instance ID, Symbol, Magic, Position Identifier, Position Ticket และ Logical Target; ปฏิเสธ Position Identifier, Position Ticket หรือ Active Logical Target ที่ถูกผูกซ้ำ
- Partial Close ปรับ Volume แต่ยังคง Active Mapping; Full Close จะถอด Position Mapping ได้เมื่อ Reconciliation ยืนยันว่าไม่มี Volume เหลือและ Lifecycle outcome ถูก Resolve แล้ว
- เมื่อถอด Position Mapping แล้ว ต้องคง Grid Level Index/State ตาม Retention Policy
- Order Comment ไม่ใช่ Typed Payload field; Reducer ไม่มี input/API สำหรับ Comment และห้ามใช้ Comment ในการสร้าง Mapping
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
- Failure/Crash Injection ทุกจุดระหว่าง Snapshot temp write, flush, validation, Journal generation creation, Manifest Slot write/flush/read-back/commit และ Old Generation cleanup ต้อง Recover เป็น State ที่สมบูรณ์ได้
- Manifest สอง Slot ต้องสลับ Commit ได้ โดยการเขียน Slot ที่ไม่ Active ล้มเหลวแล้ว Slot Active เดิมยังใช้ Restore ได้
- Manifest ที่ Schema/Identity/Checksum ผิด, อ้างถึง Data File ที่หาย หรืออ้างถึง Generation ที่ Validation ไม่ผ่าน ต้องไม่ถูกเลือกเป็น Current
- เลือก Manifest ที่ Valid และมี Commit Epoch สูงสุด; ห้ามนำ Snapshot จาก Generation หนึ่งไป Replay กับ Journal อีก Generation
- Crash ก่อน Manifest Commit ต้อง Restore Old Generation; Crash หลัง Manifest Commit ต้อง Restore New Generation
- Crash ระหว่าง Cleanup ต้อง Restore New Generation และ Cleanup ซ้ำได้โดยไม่ทำลาย Active Data
- หลัง Cleanup สำเร็จต้องเหลือ Snapshot 1 ไฟล์ + Active Journal 1 ไฟล์ + Manifest 2 Slots และไม่มี Old/Temporary Data Files
- Orphan/Temporary Files ลบได้เฉพาะเมื่อ Current Manifest/Data Set ผ่าน Validation แล้ว
- Journal ของ Generation ใหม่ต้องเริ่ม Sequence N+1 ต่อจาก Snapshot checkpoint N และต้องไม่ Replay Event ซ้ำหรือข้าม Sequence
- Snapshot Size/Count Limit ต้องปฏิเสธข้อมูลเกินขอบเขตอย่างปลอดภัย โดยไม่ทำลาย Snapshot/Journal generation ที่ใช้งานได้
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

## Implementation Progress — 2026-11-12

### Completed and user-verified

- `Include/BotTrade/Grid/GridEntryMappingReducer.mqh` adds a pure typed Current-State Reducer for payload schema `v1`.
- `Experts/TGK/Tests/Grids/test_grid_entry_mapping_reducer.mq5` adds fixture-only tests; it does not call CTrade, OrderSend, PositionClose or send any Trade Request.
- Reducer validates exact payload field count/version, Instance ID + Symbol + Magic, Request/Logical Target uniqueness, one unresolved Request, accepted-vs-failed execution outcomes, multiple Deal Tickets sharing one Position Identifier, decimal-string identifiers, reconciled Position Mapping, partial/full close transitions, configuration reset and continuous Journal Sequence.
- Position Mapping is created only after accepted execution result plus consistent Deal Association; `PLACED` alone remains unresolved and does not activate a Level.
- Partial close updates remaining volume and retains ACTIVE Mapping. Confirmed `POSITION_CLOSED` removes Position/Deal/Request mapping data while preserving the Level State. A completed `RESET_COMMITTED` prunes old Level States only when no active Position or unresolved Request remains.
- Typed payload excludes Order Comment; Comment remains separate human-readable metadata.
- User reported on 2026-11-14 that `test_grid_entry_mapping_reducer.mq5` compiled and ran successfully and all historical/Grid Regression Tests passed. This is user-reported validation; Assistant did not independently run MetaEditor/MT5.

## ลำดับงานที่เสนอ

1. **Typed Mapping Contract** — Completed.
2. **Reducer Unit Tests ก่อน Source** — Completed; Test EA อยู่ที่ `test_grid_entry_mapping_reducer.mq5`.
3. **Typed Mapping Reducer** — Implemented และผู้ใช้รายงาน Compile/Run + Regression PASS เมื่อ 2026-11-14.
4. **Snapshot Serialization + Journal Rotation Design/Test** — Design, bounded retention, dual Manifest Slots, generation/commit protocol และ Crash Recovery Matrix เสร็จแล้ว.
5. **Snapshot + Rotation Implementation** — Implemented; ผู้ใช้รายงาน Snapshot Test, corrected Reducer Test และ Grid Regression Tests ผ่านเมื่อ 2026-11-15. Capacity Limits/Failure semantics ดู Contract ในส่วนก่อนหน้าและ Testing Guide.
6. **Entry Execution Policy + Tests** — Phase 1 Design และ Phase 2 Test-First Specification (44 Cases) Finalized 2026-11-17; Production Policy ยังไม่ Implement. รายละเอียดล่าสุดอยู่ใน `phase-grid-entry-execution-policy.md`.
7. **CTrade Entry Adapter + no-live-trade seam tests** — ยังไม่เริ่ม; Intent ต้อง Persist + Flush ก่อนเรียก Trade API.
8. **Caller/Resolver + Coordinator Integration, Runtime/EA Event Handler Integration, Docs และ Regression** — ยังไม่ครบ; ต้องพิสูจน์ fresh target-level context, fail-closed resolver และ end-to-end reconciliation.
9. Demo Entry Integration เป็นงานแยก ต้องได้รับอนุมัติจากผู้ใช้ก่อนส่ง Trade Request จริง.

ก่อนแก้ Source Code ในแต่ละ Slice ให้ตรวจและรัน Grid Regression Tests ล่าสุดตาม `Docs/EAs/Grid/Testing/testing.md` ก่อนและหลัง Source changes; อย่า hard-code จำนวน Test Files จากบันทึกเก่า

## Acceptance Criteria

- Mapping ใช้ Persistent Journal และ Identifier String; ไม่มีการใช้ Comment หรือ double เป็น Mapping Key
- Entry Intent ถูกบันทึกและ Flush ก่อนส่งคำสั่ง
- Request ที่ Accepted/Placed ยังไม่ทำให้ Level เป็น ACTIVE จนกว่าจะมี Position Reconciliation
- Symbol + Magic + Position Identifier ต้องตรงกันก่อนยืนยัน Mapping
- Restart แล้ว Restore Mapping ล่าสุดได้อย่าง deterministic
- Unit Tests ไม่ส่งคำสั่งซื้อขายจริง
- ผู้ใช้ยืนยัน Compile/Run Unit และ Regression ผ่านใน MetaEditor/MT5
- เอกสารระบุข้อจำกัดและผลทดสอบตามจริง
