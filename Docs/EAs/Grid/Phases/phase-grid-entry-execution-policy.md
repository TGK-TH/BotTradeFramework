# Grid Entry Execution Policy — Design Baseline และ Test Plan

สถานะ: **Phase 1 Design Baseline อนุมัติแล้ว; Phase 2 Test-First Specification Finalized; WP-01 Policy Implementation มี Source และผ่าน Static Review; รอผู้ใช้ Compile/Run ใน MetaEditor/MT5 ก่อนปิด Work Package**

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
- Caller/Resolver รับผิดชอบ Resolve Level Context จาก `candidate.instance_id` และ Target Key (`is_anchor`, `level_index`) ของ Candidate เดียวกัน
- Caller ต้องส่ง Context สดของ Target Level ใน Current Instance เท่านั้น และห้ามใช้ Context จาก Level หรือ Instance อื่นแทน
- Policy อ่าน `has_position_mapping` จาก Level Context ที่ Caller ส่งให้เท่านั้น; Policy ไม่มี field สำหรับตรวจสอบ Context provenance และไม่ตรวจ provenance ด้วยตนเอง
- Mapping Reducer ยังคงเป็น Authority สำหรับ Mapping validation และ State transition จริง
- Resolver correctness ต้องตรวจด้วย Integration Tests แยกต่างหาก; Policy Unit Tests ไม่พิสูจน์ provenance correctness

หาก Caller/Resolver Resolve Context ไม่สำเร็จ Caller ต้อง Fail Closed และ **ห้ามเรียก Policy**. ห้ามแทน Resolver failure ด้วย `has_position_mapping=false`. Policy ไม่ทำ Automatic Recovery.

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

Candidate ที่มี Identity/Config/Mode/Target ไม่ถูกต้อง, `magic_number <= 0`, `config_epoch <= 0` หรือ Entry Price ไม่ถูกต้อง ต้องถูกปฏิเสธ

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

API Names ที่อนุมัติสำหรับ Test Contract: `CTGKGridEntryExecutionPolicy`, `STGKGridEntryExecutionCandidate`, `STGKGridEntryTargetLevel`, `STGKGridEntryExecutionLevelContext`, `STGKGridEntryExecutionContext`, `STGKGridEntryExecutionResult`, `ENUM_TGK_GRID_ENTRY_DECISION`, `ENUM_TGK_GRID_ENTRY_REASON` และ `ENUM_TGK_GRID_ENTRY_EXECUTION_STATE`.

`Evaluate()` รับ Candidate, Level Context และ Execution Context เป็น `const` references; รับ Result เป็น output reference; return type เป็น `void`. ทุก call ต้องกำหนด `decision`, `reason_code` และ `target_level` ใหม่ในทุก path รวมถึง REJECT เพื่อไม่ให้มี output เก่าค้างอยู่.

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

## 7. Test Plan — 44 Cases / 6 Groups

Test EA ใช้ Fixtures และ Test Framework เท่านั้น ไม่มี Trade Request, `CTrade`, `OrderSend`, File I/O หรือ Persistent Storage

### Group A — Valid Candidate (4)

| ID | กรณี | Expected |
|---|---|---|
| A01 | Candidate valid, Anchor (`is_anchor=true`, index `-1`), Level `READY`, Execution `NORMAL` | ALLOW / ELIGIBLE |
| A02 | Candidate valid, Level `WAIT_RETURN`, Execution `NORMAL` | ALLOW / ELIGIBLE |
| A03 | Candidate valid, Grid Mode `BUY`, Level `READY`, Execution `NORMAL` | ALLOW / ELIGIBLE |
| A04 | Candidate valid, Grid Mode `SELL`, Level `READY`, Execution `NORMAL` | ALLOW / ELIGIBLE |

### Group B — Candidate Validation (13)

ทุกกรณีใช้ Level `READY`, ไม่มี Mapping และ Execution `NORMAL` นอกจากค่าของ Candidate ที่กำลังทดสอบ

| ID | กรณี | Expected |
|---|---|---|
| B01 | Instance ID ว่าง | REJECT / INVALID_CANDIDATE |
| B02 | Symbol ว่าง | REJECT / INVALID_CANDIDATE |
| B03 | Magic Number = 0 | REJECT / INVALID_CANDIDATE |
| B04 | Grid Mode unknown/invalid | REJECT / INVALID_CANDIDATE |
| B05 | Config Epoch = 0 | REJECT / INVALID_CANDIDATE |
| B06 | Anchor representation ผิด (`is_anchor=true`, index `0`) | REJECT / INVALID_CANDIDATE |
| B07 | Entry Price = 0 | REJECT / INVALID_CANDIDATE |
| B08 | Entry Price ติดลบ | REJECT / INVALID_CANDIDATE |
| B09 | Entry Price เป็น NaN | REJECT / INVALID_CANDIDATE |
| B10 | Entry Price เป็น Infinity | REJECT / INVALID_CANDIDATE |
| B11 | Magic Number ติดลบ | REJECT / INVALID_CANDIDATE |
| B12 | Config Epoch ติดลบ | REJECT / INVALID_CANDIDATE |
| B13 | Normal Level index ติดลบ (`is_anchor=false`, index `-1`) | REJECT / INVALID_CANDIDATE |

### Group C — Identity & Execution State (6)

| ID | กรณี | Expected |
|---|---|---|
| C01 | Identity invalid/mismatch | REJECT / IDENTITY_MISMATCH |
| C02 | Execution State `NORMAL` และ Gate อื่นผ่าน | ALLOW / ELIGIBLE |
| C03 | Execution State `MAINTENANCE_ERROR` | REJECT / EXECUTION_BLOCKED |
| C04 | Execution State `RECOVERY_ERROR` | REJECT / EXECUTION_BLOCKED |
| C05 | Execution State unknown/invalid | REJECT / EXECUTION_BLOCKED |
| C06 | Identity invalid พร้อม Execution blocked | REJECT / IDENTITY_MISMATCH |

### Group D — Request & Level Eligibility (9)

| ID | กรณี | Expected |
|---|---|---|
| D01 | มี Unresolved Request | REJECT / UNRESOLVED_REQUEST |
| D02 | Target Level ไม่มีอยู่ | REJECT / LEVEL_NOT_FOUND |
| D03 | Target Level `ACTIVE` | REJECT / LEVEL_NOT_ELIGIBLE |
| D04 | Target Level `WAIT_ACTIVATION` | REJECT / LEVEL_NOT_ELIGIBLE |
| D05 | Target Level มี Unknown State | REJECT / LEVEL_NOT_ELIGIBLE |
| D06 | Target Level `READY`, ไม่มี Mapping | ALLOW / ELIGIBLE |
| D07 | Target Level `WAIT_RETURN`, ไม่มี Mapping | ALLOW / ELIGIBLE |
| D08 | Target Level มี Position Mapping | REJECT / ALREADY_MAPPED |
| D09 | Level ไม่พบพร้อม Mapping flag = true | REJECT / LEVEL_NOT_FOUND |

### Group E — Decision Precedence (6)

แต่ละ Test เปิด Failure Gate สองข้อพร้อมกัน เพื่อยืนยันว่าใช้ Reason Code จาก Gate ที่มาก่อน

| ID | เงื่อนไขพร้อมกัน | Expected Reason |
|---|---|---|
| E01 | INVALID_CANDIDATE + IDENTITY_MISMATCH | INVALID_CANDIDATE |
| E02 | IDENTITY_MISMATCH + EXECUTION_BLOCKED | IDENTITY_MISMATCH |
| E03 | EXECUTION_BLOCKED + UNRESOLVED_REQUEST | EXECUTION_BLOCKED |
| E04 | UNRESOLVED_REQUEST + LEVEL_NOT_FOUND | UNRESOLVED_REQUEST |
| E05 | LEVEL_NOT_FOUND + LEVEL_NOT_ELIGIBLE | LEVEL_NOT_FOUND |
| E06 | LEVEL_NOT_ELIGIBLE + ALREADY_MAPPED | LEVEL_NOT_ELIGIBLE |

### Group F — Stateless & Deterministic (6)

ทุก Evaluation ใน Group F ต้อง assert Decision, Reason Code และ Target Level ตาม Candidate ที่ส่งใน call นั้น

| ID | กรณีและ Expected |
|---|---|
| F01 | Evaluate valid inputs เดิมสองครั้ง; ทั้งสองผลเป็น ALLOW / ELIGIBLE และ `target_level` ถูก Copy ถูกต้อง |
| F02 | Evaluate Candidate Level 0 ด้วย Context READY/unmapped -> ALLOW / ELIGIBLE; Candidate Level 7 ด้วย Context READY/mapped -> REJECT / ALREADY_MAPPED; Evaluate Level 0 ด้วย Context เดิมซ้ำ -> ALLOW / ELIGIBLE |
| F03 | Evaluate Candidate ที่มี Unresolved Request สองครั้ง; ทั้งสองผล REJECT / UNRESOLVED_REQUEST และ Target Level ถูก Copy |
| F04 | Evaluate valid Candidate/Contexts; ALLOW / ELIGIBLE, Target Level ถูก Copy และ Inputs ไม่ถูก Mutation |
| F05 | Evaluate ด้วย Execution `NORMAL` -> ALLOW / ELIGIBLE; จากนั้น `MAINTENANCE_ERROR` -> REJECT / EXECUTION_BLOCKED; Target Level ถูก Copy ทั้งสองครั้ง |
| F06 | Evaluate ด้วย `RECOVERY_ERROR` -> REJECT / EXECUTION_BLOCKED; จากนั้น `NORMAL` -> ALLOW / ELIGIBLE; Target Level ถูก Copy ทั้งสองครั้ง |

F02 ใช้ Level Context แยกกัน: Context ของ Level 0 ไม่มี Mapping และ Context ของ Level 7 มี Mapping พร้อมใช้ Result object ตัวเดียวกันตลอดทั้งสาม Evaluate calls. การ assert หลังทุก call ยืนยันว่า Policy เขียน Decision, Reason Code และ Target Level ใหม่ครบถ้วน ไม่มี stale output จาก call ก่อนหน้า และไม่มี mapping state รั่วระหว่างการประเมิน แต่ **ไม่พิสูจน์ว่า Caller/Resolver ให้ provenance ถูกต้อง**.

**รวม 44 Test IDs** (4 + 13 + 6 + 9 + 6 + 6)

### 7.1 API Contract ที่อนุมัติสำหรับ Phase 2 Test Contract

ชื่อเหล่านี้เป็น API Names ที่ผู้ใช้ออนุมัติแล้วสำหรับ Test Contract; ยังไม่มี Policy implementation:

- Class: `CTGKGridEntryExecutionPolicy`
- Candidate: `STGKGridEntryExecutionCandidate`
- Target: `STGKGridEntryTargetLevel`
- Level Context: `STGKGridEntryExecutionLevelContext`
- Execution Context: `STGKGridEntryExecutionContext`
- Result: `STGKGridEntryExecutionResult`
- Decision enum: `ENUM_TGK_GRID_ENTRY_DECISION` (`ALLOW`, `REJECT`)
- Reason enum: `ENUM_TGK_GRID_ENTRY_REASON` (`INVALID_CANDIDATE`, `IDENTITY_MISMATCH`, `EXECUTION_BLOCKED`, `UNRESOLVED_REQUEST`, `LEVEL_NOT_FOUND`, `LEVEL_NOT_ELIGIBLE`, `ALREADY_MAPPED`, `ELIGIBLE`)
- Execution State enum: `ENUM_TGK_GRID_ENTRY_EXECUTION_STATE` (`NORMAL`, `MAINTENANCE_ERROR`, `RECOVERY_ERROR`; unknown/invalid ต้อง Block)

Candidate fields: `instance_id`, `symbol`, `magic_number`, `mode`, `config_epoch`, `target_level`, `entry_price`.

Target fields: `is_anchor`, `level_index`. Anchor ใช้ `true/-1`; Normal Level ใช้ `false/ >= 0`.

Level Context fields: `level_exists`, `level_state`, `has_position_mapping`.

Execution Context fields: `has_unresolved_request`, `identity_valid`, `execution_state`.

Result fields: `decision`, `reason_code`, `target_level`.

`Evaluate()` contract: return type `void`; Candidate, Level Context และ Execution Context เป็น `const` references; Result เป็น output reference. ทุก call ต้องกำหนด Result ทั้งสาม field ใหม่ทุก path รวมถึง REJECT.

Policy-specific enum numeric values ไม่ใช่ persistent contract ใน Phase 2; Test ใช้ symbolic values. Grid Mode และ Grid Level State ใช้ enums ที่มีอยู่ใน `GridTypes.mqh`.

### 7.2 Caller / Resolver Contract สำหรับ Position Mapping

- Caller/Resolver Resolve Level Context จาก `candidate.instance_id` และ Target Key (`is_anchor`, `level_index`).
- Context ต้องเป็นของ Target Level ที่แน่นอนและ Current Instance เท่านั้น และต้องเป็น Fresh Context ทุก Evaluation.
- ห้ามใช้ Context จาก Level หรือ Instance อื่นแทน.
- Policy อ่าน `has_position_mapping` ที่ Caller ส่งมาเท่านั้น; Policy ตรวจ provenance เองไม่ได้ เพราะ Context ไม่มี identity/key/provenance fields.
- หาก Resolver ทำงานไม่สำเร็จ Caller ต้อง Fail Closed และ **ห้ามเรียก Policy**; ห้ามแทน Resolve failure ด้วย `has_position_mapping=false`.
- Resolver correctness ต้องทดสอบด้วย Integration Tests แยกต่างหาก; Policy Unit Tests ไม่พิสูจน์ provenance correctness.
- Mapping Reducer ยังคงเป็น Authority สำหรับ Mapping validation และ State transitions.

## 8. Acceptance Criteria — Phase 2 Test-First Specification

- Test EA มี 44 Test IDs ไม่ซ้ำ และ Group counts 4/13/6/9/6/6.
- Candidate boundary cases, แยก NaN/Infinity, และ E01–E06 precedence tests ตรงตาม Contract.
- F01–F06 assert Decision, Reason Code และ Target Level ในทุก Evaluation; F02, F05 และ F06 reuse Result object เดิมข้าม Evaluate calls เพื่อทดสอบการเขียนทับ Output และป้องกัน stale result.
- Test EA ไม่มี Trade API, `CTrade`, `OrderSend`, File I/O หรือ Persistent Storage dependency.
- Test EA ใช้ API Names และ Method Contract ที่อนุมัติ; ข้อนี้อธิบายขอบเขตของ Phase 2 ซึ่งไม่มี implementation รวมอยู่ใน Test-First Specification.
- Static source checks ผ่าน รวมจำนวน/ลำดับ IDs, duplicate IDs, group counts, delimiter balance และ `git diff --check`.
- Phase 2 เป็น Test-First Specification เท่านั้น; ไม่มีการ Compile/Run MetaEditor/MT5 และห้ามรายงาน Compile/Runtime PASS.
- Caller/Resolver provenance เป็น precondition; Phase 2 Unit Tests ไม่ยืนยัน Resolver correctness.
- Phase 2 เป็น Test-First Specification เท่านั้น; Implementation เริ่มภายหลังภายใต้ WP-01 ตาม Grid V1 Kickoff Authorization.

## 9. Phase Gate และสถานะ

| Phase | ขอบเขต | สถานะ |
|---|---|---|
| Phase 1 | ตรวจสอบ Design, Contract, Architecture และ Test Plan | Complete; ผู้ใช้อนุมัติ |
| Precondition | Latest Grid Regression Tests | PASS ตามที่ผู้ใช้รายงาน 2026-11-17 |
| Phase 2 | Test-First Specification, 44 Cases และ Static Review | Finalized ตาม Final Contract ที่ผู้ใช้อนุมัติ 2026-11-17; Static Checks ผ่านตามรายการใน Project Status |
| WP-01 | Policy Implementation | Source มีแล้ว; Static Review ผ่าน; รอผู้ใช้ Compile/Run Test EA 44 Cases และ Full Grid Regression |

Phase 2 เองเป็น Test-First Specification และไม่ได้สร้าง Header; WP-01 สร้าง `Include/BotTrade/Grid/GridEntryExecutionPolicy.mqh` ตาม Contract แล้ว. Test EA ยังไม่ Compile/Run กับ Production Policy และผล Static Checks ไม่ใช่ Compile/Runtime PASS.

## 10. Related Files

- [Grid documentation index](../README.md)
- [Grid testing guide](../Testing/testing.md)
- [Grid Entry Execution Adapter — Round 1](phase-grid-entry-execution-adapter-round-1.md)
- [Project status](../../../../PROJECT_STATUS.md)

สถานะไฟล์ ณ 2026-11-17: Phase 2 Test-First Specification มี 44 Test IDs และผ่าน Static Acceptance Checks. WP-01 เพิ่ม `Include/BotTrade/Grid/GridEntryExecutionPolicy.mqh` ตาม Contract; Static Review ผ่าน แต่ยังไม่มี Compile/Runtime ผลถัดไปคือผู้ใช้ Compile/Run Policy Test EA และ Full Regression.
