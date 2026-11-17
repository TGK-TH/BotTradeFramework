# Grid Entry Execution Policy — Design Baseline และ Test Plan

สถานะ: **Design และ Test Plan อนุมัติแล้ว; Phase 2 Test-First Implementation รออนุมัติแยกต่างหาก**

อัปเดตล่าสุด: 2026-11-17

## 1. เป้าหมายและขอบเขต

สร้าง Stateless Pure Decision Component เพื่อประเมินว่า Entry Candidate ของ Grid สามารถผ่าน Gate ไปยังขั้นตอน Execution ถัดไปได้หรือไม่ โดยไม่ส่งคำสั่งซื้อขายและไม่เปลี่ยน State ของระบบ

ไฟล์ที่วางแผนไว้:

- Policy: `Include/BotTrade/Grid/GridEntryExecutionPolicy.mqh`
- Dedicated Test EA: `Experts/TGK/Tests/Grids/test_grid_entry_execution_policy.mq5`

งานนี้ครอบคลุมเฉพาะ Policy Decision และ Unit Tests ไม่รวม CTrade Adapter, OrderSend, Production EA Event Handler หรือการส่ง Trade Request จริง

## 2. Architecture และ Dependency Boundary

- Policy เป็น Stateless Pure Decision Component
- ไม่มี Internal State และไม่มีการ Mutation Input
- ไม่มี Trade API, `CTrade`, `OrderSend`, File I/O หรือ Persistent Storage dependency
- Policy ไม่ Include หรือเรียกใช้ Mapping Reducer
- ผู้เรียกส่ง Context ปัจจุบันเข้ามาให้ Policy ประเมิน
- Mapping Reducer ยังคงเป็น Authority สำหรับการตรวจสอบและ Apply Position Mapping จริง
- Policy ตรวจ Mapping เฉพาะ Target Level ของ Candidate ภายใน Instance ปัจจุบัน

Policy ไม่ทำ Automatic Recovery หาก Context ไม่พร้อมหรือข้อมูลไม่ถูกต้องให้ Reject แบบ Fail Closed

## 3. Input Contract

Input แบ่งเป็น 3 กลุ่มตามที่ผู้ใช้อนุมัติ

### 3.1 Candidate

Candidate ประกอบด้วย:

- Instance ID
- Symbol
- Magic Number
- Grid Mode
- Config Epoch
- Target Level
- Entry Price

Target Level ใช้รูปแบบเดียวกันทั้ง Anchor และ Grid Level:

| Target | `is_anchor` | `level_index` |
|---|---:|---:|
| Anchor | `true` | `-1` |
| Normal Level | `false` | `>= 0` |

Entry Price ต้องเป็น Finite Number และมีค่ามากกว่า 0 โดยใช้การตรวจลักษณะ Finite ของตัวเลขและเงื่อนไข `> 0` ไม่เพิ่ม Tick Size หรือ Digits validation

Candidate ที่มี Identity/Config/Mode/Target ไม่ถูกต้อง หรือ Entry Price ไม่ถูกต้อง ต้องถูกปฏิเสธ

### 3.2 Level Context

ประกอบด้วยข้อมูลของ Target Level ที่ Candidate อ้างถึง:

- Level Exists
- Level State
- Has Position Mapping

Policy สนใจเฉพาะ Target Level ของ Candidate ไม่ตรวจ Mapping ของ Level อื่น

Eligible Level States มีเพียง:

- `READY`
- `WAIT_RETURN`

State อื่น เช่น `ACTIVE`, `WAIT_ACTIVATION` หรือค่า State ที่ไม่รู้จัก ต้องไม่ผ่าน Eligibility Gate

### 3.3 Execution Context

ประกอบด้วย:

- Has Unresolved Request
- Identity Valid
- Execution State

Execution State ที่รู้จัก:

- `NORMAL`
- `MAINTENANCE_ERROR`
- `RECOVERY_ERROR`

ให้ใช้ Lightweight Enum ภายใน Policy เพื่อหลีกเลี่ยง Dependency ไปยัง Storage/Reducer โดยตรง ค่า Unknown/Invalid ต้องถือว่า Blocked (Fail Closed)

## 4. Output Contract

Output มี:

- Decision: `ALLOW` หรือ `REJECT`
- Reason Code เพียงหนึ่งค่า
- Target Level ที่ Copy มาจาก Candidate

ห้ามส่งหลาย Reason Codes ในผลลัพธ์เดียว เหตุผลที่คืนต้องเป็น Gate แรกที่ไม่ผ่านตาม Validation Order

Reason Code ที่อนุมัติ:

- `INVALID_CANDIDATE`
- `IDENTITY_MISMATCH`
- `EXECUTION_BLOCKED`
- `UNRESOLVED_REQUEST`
- `LEVEL_NOT_FOUND`
- `LEVEL_NOT_ELIGIBLE`
- `ALREADY_MAPPED`
- `ELIGIBLE`

## 5. Validation Order — ข้อตกลงที่ล็อกแล้ว

ต้องประเมินตามลำดับนี้และหยุดที่ Failure แรก:

1. **INVALID_CANDIDATE** — Candidate field, Target Level representation หรือ Entry Price ไม่ถูกต้อง
2. **IDENTITY_MISMATCH** — Identity ของ Execution Context ไม่ตรง/ไม่ Valid
3. **EXECUTION_BLOCKED** — Execution State ไม่ใช่ `NORMAL` รวมถึง Unknown/Invalid State
4. **UNRESOLVED_REQUEST** — มี Unresolved Request อยู่แล้ว
5. **LEVEL_NOT_FOUND** — ไม่พบ Target Level
6. **LEVEL_NOT_ELIGIBLE** — Target Level ไม่อยู่ใน `READY` หรือ `WAIT_RETURN`
7. **ALREADY_MAPPED** — Target Level มี Position Mapping อยู่แล้ว
8. **ELIGIBLE** — ผ่านทุก Gate; คืน `ALLOW`

ลำดับนี้เป็น Contract ของ Decision ไม่ใช่เพียงลำดับข้อความ Log และต้องมี Precedence Tests ยืนยัน

## 6. กติกา Fail-Closed และ Fresh Context

- Candidate ไม่ถูกต้อง: Reject
- Identity mismatch: Reject
- Execution State เป็น Maintenance/Recovery Error หรือ Unknown: Reject
- มี Unresolved Request: Reject
- Level ไม่มีอยู่: Reject
- Level State ไม่ Eligible: Reject
- Target Level มี Mapping อยู่แล้ว: Reject
- Policy ไม่แก้ไข Level State, Mapping, Request หรือ Execution State
- Policy ไม่เก็บผลจากการประเมินครั้งก่อน
- การประเมินทุกครั้งใช้ Input Context ที่ส่งเข้ามาในครั้งนั้น
- หาก Context เปลี่ยนจาก Blocked เป็น Normal สามารถประเมินใหม่ด้วย Context ใหม่ได้ทันที

## 7. Test Plan — 40 Cases / 6 Groups

Test EA ใช้ Fixtures และ Test Framework เท่านั้น ไม่มี Trade Request, CTrade หรือ File I/O

### Group A — Valid Candidate (4)

| ID | กรณี | Expected |
|---|---|---|
| A01 | Candidate ถูกต้อง, Level READY, BUY | ALLOW / ELIGIBLE |
| A02 | Candidate ถูกต้อง, Level WAIT_RETURN | ALLOW / ELIGIBLE |
| A03 | Candidate ถูกต้อง, Grid Mode BUY | ALLOW / ELIGIBLE |
| A04 | Candidate ถูกต้อง, Grid Mode SELL | ALLOW / ELIGIBLE |

### Group B — Candidate Validation (9)

| ID | กรณี | Expected |
|---|---|---|
| B01 | Instance ID ไม่ถูกต้อง | REJECT / INVALID_CANDIDATE |
| B02 | Symbol ว่าง | REJECT / INVALID_CANDIDATE |
| B03 | Magic Number ไม่ถูกต้อง | REJECT / INVALID_CANDIDATE |
| B04 | Grid Mode ไม่ถูกต้อง | REJECT / INVALID_CANDIDATE |
| B05 | Config Epoch ไม่ถูกต้อง | REJECT / INVALID_CANDIDATE |
| B06 | Target Level representation ไม่ถูกต้อง | REJECT / INVALID_CANDIDATE |
| B07 | Entry Price = 0 | REJECT / INVALID_CANDIDATE |
| B08 | Entry Price ติดลบ | REJECT / INVALID_CANDIDATE |
| B09 | Entry Price เป็น NaN/Infinity (ตรวจทั้งสองค่าในกรณีทดสอบนี้) | REJECT / INVALID_CANDIDATE |

### Group C — Identity & Execution State (6)

| ID | กรณี | Expected |
|---|---|---|
| C01 | Identity mismatch | REJECT / IDENTITY_MISMATCH |
| C02 | Execution State = NORMAL | ผ่าน Execution Gate |
| C03 | Execution State = MAINTENANCE_ERROR | REJECT / EXECUTION_BLOCKED |
| C04 | Execution State = RECOVERY_ERROR | REJECT / EXECUTION_BLOCKED |
| C05 | Execution State เป็น Unknown/Invalid | REJECT / EXECUTION_BLOCKED |
| C06 | Identity mismatch พร้อม Execution Blocked | REJECT / IDENTITY_MISMATCH (ยืนยัน Precedence) |

### Group D — Request & Level Eligibility (9)

| ID | กรณี | Expected |
|---|---|---|
| D01 | มี Unresolved Request | REJECT / UNRESOLVED_REQUEST |
| D02 | Target Level ไม่มีอยู่ | REJECT / LEVEL_NOT_FOUND |
| D03 | Target Level = ACTIVE | REJECT / LEVEL_NOT_ELIGIBLE |
| D04 | Target Level = WAIT_ACTIVATION | REJECT / LEVEL_NOT_ELIGIBLE |
| D05 | Target Level เป็น Unknown State | REJECT / LEVEL_NOT_ELIGIBLE |
| D06 | Target Level = READY และไม่มี Mapping | ALLOW / ELIGIBLE |
| D07 | Target Level = WAIT_RETURN และไม่มี Mapping | ALLOW / ELIGIBLE |
| D08 | Target Level มี Position Mapping | REJECT / ALREADY_MAPPED |
| D09 | Level ไม่พบพร้อมกับ Mapping Flag = true | REJECT / LEVEL_NOT_FOUND |

### Group E — Decision Precedence (6)

แต่ละกรณีเปิดเงื่อนไข Failure สองข้อพร้อมกัน เพื่อยืนยันว่า Policy คืน Reason Code ของ Gate ที่มาก่อนเสมอ

| ID | เงื่อนไขที่เกิดพร้อมกัน | Expected Reason |
|---|---|---|
| E01 | Invalid Candidate + Identity mismatch | INVALID_CANDIDATE |
| E02 | Identity mismatch + Execution blocked | IDENTITY_MISMATCH |
| E03 | Execution blocked + Unresolved Request | EXECUTION_BLOCKED |
| E04 | Unresolved Request + Level not found | UNRESOLVED_REQUEST |
| E05 | Level not found + Level not eligible | LEVEL_NOT_FOUND |
| E06 | Level not eligible + Already mapped | LEVEL_NOT_ELIGIBLE |

### Group F — Stateless & Deterministic (6)

| ID | กรณี | Expected |
|---|---|---|
| F01 | Evaluate Input เดิมซ้ำ | Decision และ Reason Code เหมือนเดิม |
| F02 | Evaluate Candidate แยกกัน | Candidate หนึ่งไม่กระทบอีก Candidate |
| F03 | Repeated rejection | ไม่มี State เปลี่ยนใน Policy |
| F04 | ตรวจ Input ก่อน/หลัง Evaluate | Input ไม่ถูก Mutation |
| F05 | เปลี่ยน Execution Context จาก NORMAL เป็น Blocked | การ Evaluate ครั้งใหม่ Reject |
| F06 | เปลี่ยน Execution Context จาก Blocked เป็น NORMAL | การ Evaluate ครั้งใหม่ประเมินจาก Context ใหม่และ Allow ได้เมื่อ Gate อื่นผ่าน |

**รวม 40 กรณี** (4 + 9 + 6 + 9 + 6 + 6)

### Test EA Interface Names — Provisional, Pending Review

เพื่อให้ Test-First Test EA อ้างอิง Contract ได้ ไฟล์ทดสอบกำหนดชื่อ MQL5 identifiers เบื้องต้นดังนี้:

- Policy class: `CTGKGridEntryExecutionPolicy`
- Candidate: `STGKGridEntryExecutionCandidate`
- Target: `STGKGridEntryTargetLevel`
- Level Context: `STGKGridEntryExecutionLevelContext`
- Execution Context: `STGKGridEntryExecutionContext`
- Result: `STGKGridEntryExecutionResult`
- Decision enum: `ENUM_TGK_GRID_ENTRY_DECISION`
- Reason enum: `ENUM_TGK_GRID_ENTRY_REASON`
- Execution State enum: `ENUM_TGK_GRID_ENTRY_EXECUTION_STATE`
- Method: `Evaluate(candidate, level_context, execution_context, result)`
- Result fields: `decision`, `reason_code`, `target_level`

ชื่อเหล่านี้เป็น **ข้อเสนอระดับ Source API จาก Test EA เท่านั้น ยังไม่ใช่ Design Baseline ที่ผู้ใช้อนุมัติ**. ก่อน Phase 3 จะ Implement Policy ต้อง Review/ยืนยันชื่อและ Field Contract เหล่านี้ก่อน โดยห้ามเปลี่ยน Validation Order หรือ Semantics ที่อนุมัติแล้วโดยไม่มีการตกลงใหม่

## 8. Acceptance Criteria

- Test ทั้ง 40 กรณีผ่านใน Dedicated Test EA
- Validation Order ตรงตาม Section 5
- Output มี Reason Code เพียงหนึ่งค่า
- READY และ WAIT_RETURN เป็น Eligible States เพียงสองค่า
- Target Level Mapping Check จำกัดอยู่ที่ Candidate Target ภายใน Instance ปัจจุบัน
- Invalid/Unknown State ต้อง Fail Closed
- Statelessness, Determinism, Input Immutability และ Fresh Context Reevaluation มี Test ครอบคลุม
- Policy ไม่มี Trade API, Storage หรือ File I/O dependency
- ผู้ใช้ยืนยัน MetaEditor Compile/Runtime และ Grid Regression Tests ที่เกี่ยวข้องผ่านก่อนถือว่า Phase Implementation เสร็จ

## 9. Phase Gate และสถานะ

| Phase | ขอบเขต | สถานะ |
|---|---|---|
| Phase 1 | ตรวจสอบ Design, Contract, Architecture และ Test Plan | Complete; ผู้ใช้อนุมัติ |
| Precondition | Latest Grid Regression Tests | PASS ตามที่ผู้ใช้รายงาน 2026-11-17 |
| Phase 2 | สร้าง Dedicated Test EA แบบ Test-First และตรวจ Coverage | กำลังดำเนินการ; Test EA สร้างแล้ว 40/40 Cases และ Static Checks ผ่าน; รอ Review ก่อนปิด Phase |
| Phase 3 | Policy Implementation หลัง Test-First Gate ตามแผนที่ตกลง | ยังไม่เริ่ม |

ผู้ใช้อนุมัติ Phase 2 แล้วเมื่อ 2026-11-17. Test EA ถูกสร้างที่ `Experts/TGK/Tests/Grids/test_grid_entry_execution_policy.mq5` ครบ 40 Cases ตาม Group A–F และผ่าน Static Checks (`git diff --check`, จำนวน Test/Group, delimiter balance, duplicate local declaration scan และตรวจว่าไม่มี Trade API/File I/O call). ยังไม่ได้ Compile/Run ใน MetaEditor/MT5. เนื่องจาก Policy Header/Contract ยังไม่ถูกสร้างตามขอบเขต Test-First Phase นี้ การ Compile/Run กับ Production Policy จะทำได้หลังมี Policy Contract ใน Phase ถัดไป; ห้ามนับ Static Checks เป็น Compile/Runtime PASS.

## 10. Related Files

- [Grid documentation index](../README.md)
- [Grid testing guide](../Testing/testing.md)
- [Grid Entry Execution Adapter — Round 1](phase-grid-entry-execution-adapter-round-1.md)
- [Project status](../../../../PROJECT_STATUS.md)

สถานะไฟล์ ณ 2026-11-17: Dedicated Test EA ถูกสร้างแล้ว; `Include/BotTrade/Grid/GridEntryExecutionPolicy.mqh` ยังไม่ถูกสร้างและยังไม่มี Decision Logic.
