# WP-05B Implementation Report — Runtime State Restoration

**Implementer:** Freebuff
**วันที่ Implement รอบแรก:** 2026-11-26
**วันที่ Remediation ตาม CTO Review:** 2026-11-26
**Branch:** `feature/grid-trading`
**สถานะ:** Implemented + CTO Remediation รอบที่ 1 (F-01, F-02, F-03, F-05, F-10) และ Remediation รอบที่ 2 (F-11, F-12) เสร็จ — Compile PASS (0 errors, 0 warnings) ทุกโปรแกรมที่ได้รับผลกระทบ; Product Owner รายงาน Runtime Verification PASS 2026-11-26 บน Source หลัง Remediation รอบที่ 1 และ PASS อีกครั้งบน Source หลัง Remediation รอบที่ 2 (รัน Test ครบทุกไฟล์); WP-05B ยังไม่ Done จนกว่า CTO Formal Code Review จะ `APPROVED`

## 1. ไฟล์ที่เปลี่ยน

| ไฟล์ | ประเภท | ขอบเขตการแก้ |
|---|---|---|
| `Include/BotTrade/Grid/GridEntryMappingReducer.mqh` | Production | เพิ่ม Typed Read-only Projection สำหรับ Position Mapping, Unresolved Entry Request และ Persisted Configuration |
| `Include/BotTrade/Grid/GridLevelRuntimeCoordinator.mqh` | Production | เพิ่ม Bulk Runtime Hydration API, Persisted Configuration Validation, Runtime Restore Status, Reconciliation Gate และ Position/Request Accessors; Hydration สร้าง Engine จาก Persisted Configuration (F-11) และ Invalidate Runtime ทั้งชุดเมื่อ Restore ล้มเหลว (F-12) |
| `Include/BotTrade/Grid/GridLevelEngine.mqh` | Production | เพิ่ม public `Reset()` เพื่อ Invalidate Geometry/Level State ที่ Derived ไว้ (F-12); พฤติกรรมเดิมของผู้เรียกไม่เปลี่ยน |
| `Experts/TGK/Tests/Grids/test_grid_runtime_restoration.mq5` | Test (ใหม่) | Test EA no-trade ครอบคลุม B-01 ถึง B-13 ตาม `TEST_PLAN.md` รวมกรณี Remediation |
| `Docs/EAs/Grid/WorkPackages/WP-05B/SPEC.md` | Doc (Status metadata) | แก้เฉพาะบรรทัดสถานะ Implementation (F-10) |
| `Docs/EAs/Grid/WorkPackages/WP-05B/TEST_PLAN.md` | Doc (Status metadata) | แก้เฉพาะบรรทัดสถานะ Implementation (F-10) |
| `Docs/EAs/Grid/WorkPackages/WP-05B/IMPLEMENTATION_REPORT.md` | Report | ไฟล์นี้ |

ไม่มีการแก้ `GridEntryMappingSnapshotStorage.mqh`, `GridEntryMappingStorage.mqh`, `GridPersistence.mqh`, `GridTypes.mqh`, Production EA หรือข้อกำหนด Functional ใน `SPEC.md`/`TEST_PLAN.md` (Remediation รอบที่ 2 เพิ่มเฉพาะ public `Reset()` ใน `GridLevelEngine.mqh` เพื่อ F-12)
ไม่มีการเปลี่ยน Trading Behavior, Entry Selection, Level Geometry หรือ Bounds
ไม่มีการ Commit/Push และไม่มีการใช้ destructive Git operation

## 2. Implementation Summary

### 2.1 Reducer — Typed Read-only Projection

`Include/BotTrade/Grid/GridEntryMappingReducer.mqh`

- เพิ่ม struct `STGKGridPositionMappingProjection` ประกอบด้วย `position_identifier`, `position_ticket`, `remaining_volume`, `symbol`, `magic_number`, `instance_id`, `target_kind`, `level_index`, `config_epoch`
- เพิ่ม `TryGetPositionMappingAt(int index, STGKGridPositionMappingProjection &projection)` — คืน Mapping ตามลำดับ committed Replay order (deterministic) และ Fail Closed เมื่อ Reducer ไม่ healthy, Index ผิดช่วง, Target ไม่ถูกต้อง, Symbol/Magic/Config Epoch ไม่ตรง, Identifier/Ticket ไม่ใช่ Canonical decimal หรือ Volume ไม่ถูกต้อง
- เพิ่ม `TryGetUnresolvedRequest(bool &has_unresolved_request, STGKGridMappingRequestState &request)` — แยก "ไม่มี Request" (`has_unresolved_request = false`) จาก "State ใช้งานไม่ได้" (คืน `false`) และปฏิเสธเมื่อมี Unresolved Request มากกว่าหนึ่งรายการ; คืนค่า `requested_volume` ครบตาม Canonical State
- เพิ่ม struct `STGKGridPersistedConfigProjection` และ `TryGetPersistedConfig(...)` สำหรับ F-01 (ดู §3.1)
- เพิ่ม private helper `IsRuntimeViewHealthy()` (initialized, ไม่ failed, Recovery Status = `TGK_GRID_MAPPING_STATUS_NORMAL`, committed Config Epoch > 0)
- Position Identifier ยังเป็น Canonical Identity; Position Ticket เป็น Operational Handle ตามเดิม
- Reducer ยังเป็น Canonical State Authority: Projection ทั้งหมดเป็น Read-only ไม่เขียน Journal และไม่เปลี่ยน Canonical State

### 2.2 Coordinator — Bulk Runtime Hydration

`Include/BotTrade/Grid/GridLevelRuntimeCoordinator.mqh`

- `STGKGridLevelPositionRecord` เพิ่มฟิลด์ `position_identifier` เพื่อรักษา Logical Identity ควบคู่กับ Ticket/Volume (ฟิลด์ใหม่ไม่บังคับใน `ValidateSnapshot()` เดิม จึงไม่เปลี่ยนพฤติกรรม `Reconcile()` ที่มีอยู่)
- เพิ่ม struct `STGKGridLevelStateHydration` (Level Index + State) และ `STGKGridEntryRequestHydration` (present, request_id, is_anchor, level_index, requested_volume)
- เพิ่ม enum `ENUM_TGK_GRID_RUNTIME_RESTORE_STATUS`: `TGK_GRID_RUNTIME_RESTORE_NONE`, `TGK_GRID_RUNTIME_RESTORE_PENDING_RECONCILIATION`, `TGK_GRID_RUNTIME_RESTORE_ERROR`
- เพิ่ม `HydrateRuntimeState(...)` — Bulk Hydration ครั้งเดียวต่อ Restore หนึ่งครั้ง:
  - ตรวจ Requested Configuration เทียบกับ Persisted Configuration Projection ก่อน (`ValidatePersistedConfig()`; ดู §3.1)
  - สร้าง Engine/Coordinator จาก Persisted Grid Configuration (`ENUM_TGK_GRID_MODE`, Anchor, Grid Step, Bounds, Normal Level Count, Symbol, Magic Number, Config Epoch, Current Quote)
  - Hydrate Anchor State, ทุก Normal Level State, ทุก Position Mapping และ Unresolved Entry Request
  - **All-or-Nothing**: Validation ทั้งชุดทำก่อน Mutate ใด ๆ (`ValidateHydrationProjection()`), จากนั้น Commit ผ่าน `ApplyHydratedState()`; หากขั้นใดล้มเหลว Runtime จะถูกทิ้งไว้ในสภาพใช้งานไม่ได้ (`m_initialized = false`, `RESTORE_ERROR`, ไม่มี Position state)
  - ไม่ Append Journal, ไม่อ่าน Account/Position API, ไม่สร้าง Candidate, ไม่สร้าง Entry Request
  - สำเร็จแล้วจบที่ `TGK_GRID_RUNTIME_RESTORE_PENDING_RECONCILIATION` และตั้ง `m_reconciliation_pending = true`
- Validation ที่บังคับ (Fail Closed):
  - Normal Level State ต้องครอบคลุมทุก Level ของ Engine ครั้งเดียว, Index ไม่ซ้ำ/ไม่เกินช่วง, State ต้องเป็น `READY`, `ACTIVE` หรือ `WAIT_ACTIVATION` (ไม่รับ `WAIT_RETURN` ซึ่ง Reducer normalize ไปแล้ว)
  - Mapping ต้องมี Symbol/Magic ตรง Identity, Ticket ≠ 0, Identifier เป็น Canonical decimal, Volume > 0, Target ถูกต้อง (Anchor = -1, Level อยู่ในช่วง)
  - ห้าม Mapping ซ้ำ Target, ซ้ำ Identifier หรือซ้ำ Ticket
  - Mapping มีได้เฉพาะ Target ที่ `ACTIVE` และ Target ที่ `ACTIVE` ต้องมี Mapping (สอดคล้อง Reducer invariant)
  - Unresolved Entry Request ต้องไม่ถือ Mapping และต้องไม่ทำให้ Target เป็น `ACTIVE`; ห้ามสร้าง ACTIVE จาก Request; `requested_volume` ต้อง finite และ > 0
  - Quote ต้องถูกต้อง (`bid > 0`, `ask >= bid`) และ Grid Geometry ต้องผ่าน `CTGKGridLevelEngine::Initialize()`
- Entry/Candidate Gate: `UpdatePrice()` ระหว่าง `m_reconciliation_pending` จะอัปเดตเฉพาะ Previous/Current Quote Baseline แล้วคืน `TGK_GRID_COORDINATOR_NO_CANDIDATE` โดยไม่เรียก Engine จึงไม่เกิด Candidate, Entry Request หรือ Activation Pending ระหว่าง Price Update
- `RegisterInitialAnchorPosition()` ถูกปฏิเสธระหว่าง Gate ปิด (Runtime ต้องนิ่งจนกว่าจะ Reconcile)
- `Reconcile()` ถูกปฏิเสธระหว่าง Gate ปิด (F-03; ดู §3.3) — ไม่ใช่ implicit gate release
- Public Read API ใหม่: `RestoreStatus()`, `IsReconciliationPending()`, `PendingRequestId()`, `PendingRequestVolume()`, `PersistedInstanceId()`, `PositionCount()`, `TryGetPositionAt()`
- `PendingRequestId()`/`PendingRequestVolume()` ถูกล้างเมื่อ `Reconcile()` resolve Request (Confirmed หรือ Failed)
- `StoreCurrentPositions()` copy `position_identifier` ต่อจาก Ticket/Volume
- ไม่มี Trade Request, `OrderSend`, `CTrade`, `PositionClose` หรือ Account Position scan ในไฟล์ที่แก้

### 2.3 Startup Restore Sequence ที่ทดสอบ

Test EA ใช้ลำดับ: committed Journal Fixture → `CTGKGridEntryMappingReducer::Replay()` (หรือ Snapshot Storage `Bootstrap`/`Replay` → `RestoreSnapshot()` + `Replay()`), `MatchesContext()` สำหรับ Identity/Configuration, `TryGetPersistedConfig()` เป็น Canonical Configuration, Projection, แล้ว `HydrateRuntimeState()` โดยยังไม่แตะ MT5 Account Position ใด ๆ (WP-05C)

## 3. CTO Remediation (2026-11-26)

CTO ตอบกลับ `CHANGES_REQUESTED` หลัง Static Source Review รอบแรก Remediation รอบที่ 1 แก้เฉพาะ Finding ที่อนุมัติ: **F-01, F-02, F-03, F-05, F-10** เท่านั้น; F-04, F-06, F-07, F-08, F-09 ไม่ถูกแก้ตามคำสั่ง CTO (§3.6) Remediation รอบที่ 2 (§3.7–§3.8) แก้เฉพาะ **F-11, F-12** ตาม Handoff ใหม่

### 3.1 F-01 [HIGH] — Persisted Grid Geometry Validation: แก้แล้ว

**Reducer** (`GridEntryMappingReducer.mqh`)

- เพิ่ม `STGKGridPersistedConfigProjection` ประกอบด้วย `instance_id`, `symbol`, `magic_number`, `mode` (`ENUM_TGK_GRID_MODE`), `anchor_price`, `grid_step`, `lower_bound`, `upper_bound`, `persisted_level_count` (นับรวม Anchor), `config_epoch`
- เพิ่ม `TryGetPersistedConfig(STGKGridPersistedConfigProjection &config)` — อ่านจาก committed/replayed Canonical State (`m_*` ที่ `RESET_COMMITTED`/`RestoreSnapshot` ตั้งไว้) เท่านั้น; ตั้งค่า output เป็น default ก่อนทุกครั้ง, คืน `false` เมื่อ Reducer ไม่ healthy, Mode ไม่ใช่ `BUY`/`SELL`, geometry ไม่ถูกต้อง หรือ `ArraySize(m_levels) != m_level_count - 1`; ไม่เขียน Journal และไม่เพิ่ม Configuration Authority ตัวที่สอง

**Coordinator** (`GridLevelRuntimeCoordinator.mqh`)

- `HydrateRuntimeState()` รับ `STGKGridPersistedConfigProjection &persisted_config` เพิ่ม (ต่อจาก `config_epoch`)
- เพิ่ม `ValidatePersistedConfig()` เรียกเป็นขั้นแรกของ Hydration — **ก่อน** `ValidateHydrationProjection()` และก่อน Mutate ใด ๆ; ปฏิเสธเมื่อ:
  - Instance Identity ไม่ใช่ Token / Symbol ว่าง / Magic Number ≤ 0 / Epoch ≤ 0 / Persisted Level Count ≤ 1 / geometry ที่ Persist ไม่ถูกต้อง
  - Requested `symbol`, `magic_number`, `config_epoch` หรือ `mode` ไม่ตรงกับ Persisted
  - `normal_level_count != persisted_level_count - 1` (Level Count ต้องตรงแบบ exact และต้องเทียบ Persisted Count กับ Engine Count ให้ถูกตัว)
  - ค่า Geometry ที่ Request ไม่ finite, `grid_step_price <= 0`, หรือผลต่างเกิน `epsilon = persisted_config.grid_step * 0.000000001` ซึ่งเป็น epsilon เดียวกับ `CTGKGridLevelEngine::BuildLevels()` (`m_grid_step_price * 0.000000001`)
- เมื่อสำเร็จ Coordinator เก็บ `persisted_config.instance_id` ไว้ที่ `PersistedInstanceId()` เป็นหลักฐานของ Instance ที่ผ่านการ Validate
- Coordinator include `GridEntryMappingReducer.mqh` เพื่อใช้ Type ของ Canonical Projection โดยตรง (ไม่สร้าง Struct คู่ขนาน)

**เหตุผล:** ก่อนแก้ การส่ง Anchor/Bounds ที่เลื่อนไปทั้งชุด (เช่น Anchor 4002, Bounds 3982–4022) ยังสร้าง Level ได้ 8 ตัวเท่าเดิม แต่ Level ทุกตัวเลื่อนราคาเงียบ ๆ (3990 → 3992) ทำให้ Mapping ชี้ Level ผิดโดยไม่มี Error

### 3.2 F-02 [MEDIUM-HIGH] — Hydration-time Mode Validation: แก้แล้ว

- Mode ถูกตรวจภายใน `ValidatePersistedConfig()` ระหว่าง Hydration (`mode != persisted_config.mode` → ปฏิเสธทั้งชุด) ไม่พึ่ง `MatchesModeContext()` ของ Caller อีกต่อไป
- Caller ยังใช้ `MatchesContext()`/`MatchesModeContext()` เป็น Pre-check ได้ แต่ไม่ใช่หลักประกันเดียวแล้ว

### 3.3 F-03 [MEDIUM] — ปิด Reconcile Path ระหว่าง Reconciliation Pending: แก้แล้ว

- เพิ่ม Early Guard ใน `Reconcile()`: ถ้า `m_reconciliation_pending == true` จะคืน `TGK_GRID_COORDINATOR_ERROR` ทันทีใน Validation Chain แรก — ก่อน `ValidateSnapshot()`, ก่อนแก้ Quote Baseline และก่อน Side Effect ใด ๆ
- ระหว่าง Gate ปิดจึงไม่มีการ Resolve Unresolved Request, ไม่ Apply Closed Position, ไม่เปลี่ยน Anchor/Level State, ไม่แทนที่ Position Mapping, ไม่ Offer Deferred Candidate และไม่ปล่อย Gate
- `Reconcile()` ไม่ใช่ implicit gate release; WP-05C จะกำหนด Release Mechanism อย่างชัดเจนหลังยืนยัน Complete/Stable Live Position Snapshot

### 3.4 F-05 [LOW-MEDIUM] — รักษา Requested Volume ของ Unresolved Entry Request: แก้แล้ว

- `STGKGridEntryRequestHydration` เพิ่มฟิลด์ `requested_volume`
- `ProjectRestoreState()` ใน Test EA ส่ง `request_state.requested_volume` จาก `TryGetUnresolvedRequest()` เข้า Hydration โดยตรง (Reducer คืนค่าอยู่แล้ว ไม่ต้องแก้ Reducer)
- `ValidateHydrationProjection()` ปฏิเสธ Request ที่ `requested_volume` ไม่ finite หรือ ≤ 0
- Coordinator เก็บค่าไว้ที่ `m_pending_request_volume` และเปิด Read-only Accessor `PendingRequestVolume()`; ล้างเป็น `0.0` เมื่อ `Reconcile()` resolve Request (ทั้ง Confirmed และ Failed) และเมื่อ `Initialize()`/Hydration ล้มเหลว
- Volume ที่ Hydrate กลับมาเป็น Evidence เท่านั้น: ไม่เปลี่ยนสถานะ unresolved และไม่ทำให้ Target เป็น `ACTIVE`

### 3.5 F-10 [LOW] — แก้ Authorization Metadata: แก้แล้ว

- `SPEC.md` บรรทัดสถานะ: `Implementation: NOT AUTHORIZED` → ระบุว่า Product Owner อนุมัติ Implementation 2026-11-26, Implement เสร็จรอบแรกและ Remediation ตาม CTO `CHANGES_REQUESTED` เสร็จแล้ว — รอ CTO Formal Code Review
- `TEST_PLAN.md` บรรทัดสถานะ: ระบุการอนุมัติ 2026-11-26 และ Remediation เสร็จ (หลัง Remediation บรรทัดนี้ถูกอัปเดตอีกครั้งว่า Product Owner รายงาน Test PASS 2026-11-26) — ขั้นที่เหลือคือ CTO Formal Code Review
- ไม่มีการแก้ Functional Requirement, Acceptance Criteria หรือ Scope ที่อนุมัติแล้ว

### 3.6 Findings ที่ไม่แก้ตามคำสั่ง CTO

| Finding | สถานะ |
|---|---|
| F-04 Position Identifier ใน Live Snapshot Reconciliation | เลื่อนไป WP-05C; WP-05C ต้องบังคับ Identifier ที่ถูกต้องและห้ามทับด้วยค่าว่าง |
| F-06 Hydration API Parameter Count / Input Struct Refactor | ไม่แก้ (API ปัจจุบันมี 16 พารามิเตอร์หลังเพิ่ม `persisted_config`) |
| F-07 `IsReconciliationPending()` Semantics | ไม่แก้; `RestoreStatus()` ยังเป็นตัวชี้ Restore Error ที่เป็นทางการ |
| F-08 Predicate ซ้ำ (`IsDecimalIdentity`/`IsTokenLiteral`) | ไม่แก้ |
| F-09 `UpdatePrice()` Pending-gate Result Semantics | ไม่แก้; `IsRequestUnresolved()`/`PendingRequestId()` ยังเป็น Accessor แยก |

### 3.7 F-11 [MEDIUM] — Engine ต้องสร้างจาก Persisted Configuration: แก้แล้ว

**Root cause:** `HydrateRuntimeState()` validate Requested Configuration เทียบ `STGKGridPersistedConfigProjection` (ยอมให้ต่างได้ภายใน Engine epsilon `grid_step * 1e-9`) แต่หลังจากนั้นเรียก `m_engine.Initialize()` ด้วยค่าที่ Caller ส่งมา ไม่ใช่ค่าที่ Persist ไว้ — Runtime Geometry จึงอาจต่างจาก Geometry ที่ Mapping ถูก Persist ไว้ได้เล็กน้อย ทั้งที่ถือว่าผ่าน Validation แล้ว

**Fix** (`GridLevelRuntimeCoordinator.mqh`)

- คง Epsilon Comparison เดิมใน `ValidatePersistedConfig()` ไว้ทั้งหมด (ไม่ผ่อน/ไม่เข้มขึ้น) — Requested Arguments ยังเป็น Validation Input ตามเดิม
- หลัง Validation ผ่าน `m_engine.Initialize()` ใช้ค่าจาก `persisted_config` เท่านั้น: `mode`, `anchor_price`, `grid_step`, `lower_bound`, `upper_bound` และ `persisted_level_count - 1` (แปลงเป็น Engine Normal Level Count ตามธรรมเนียม `persisted_level_count = normal_level_count + 1`; Anchor ไม่นับเป็น Engine Level)
- `m_mode`/`m_symbol`/`m_magic_number`/`m_config_epoch` ก็ตั้งจาก `persisted_config` เช่นกัน (Validation บังคับให้เท่ากับ Request แบบ exact อยู่แล้ว จึงไม่มี Behavior เปลี่ยน)
- เพิ่ม Read-only Accessor สำหรับตรวจ Geometry จริงของ Runtime: `AnchorPrice()` และ `GetLevelPrice(level_index, price)` — ทั้งคู่ Fail Closed (คืน `0.0` / `false`) เมื่อ Coordinator ไม่ initialized

**Test:** §4 (B-08) — Hydrate ด้วย Anchor ที่ต่างจาก Persisted ภายใน epsilon แล้วยืนยันว่า Anchor Price ของ Engine เท่ากับค่า Persisted, Level Price ที่คาดหมาย (3980 / 4005 / 4020) มาจาก Persisted Anchor/Step/Bounds, จำนวน Level ตรงกับ Persisted และกรณีที่ต่างเกิน epsilon ยังถูกปฏิเสธเหมือนเดิม

### 3.8 F-12 [LOW] — Failed Hydration ต้องไม่เหลือ Stale Runtime State: แก้แล้ว

**Root cause:** เมื่อ Coordinator เคย Hydrate/Initialize สำเร็จแล้ว Hydration ครั้งถัดไปที่ล้มเหลวก่อน `m_engine.Initialize()` ตั้งเพียง `m_initialized = false` บางฟิลด์ แต่ไม่ได้ทิ้ง Engine และฟิลด์ Runtime เดิม; `GetAnchorState()` อ่าน `m_engine` ตรง ๆ โดยไม่ตรวจ initialization จึงเปิดเผย Anchor State เก่าได้

**Fix**

- `GridLevelEngine.mqh`: เพิ่ม public `void Reset()` — ล้าง Level Price/State arrays, Anchor Activation Pending และคืนค่า Geometry/Anchor baseline ของ Constructor พร้อม `m_initialized = false`; ไม่เปลี่ยนพฤติกรรมของ Method เดิม
- `GridLevelRuntimeCoordinator.mqh`: เพิ่ม private `InvalidateRuntimeState()` ที่เรียก `m_engine.Reset()` และล้างทุกฟิลด์ Runtime (Mode/Symbol/Magic/Epoch/Instance, Quote Baseline, Anchor Activation, Initialized, Offered/Pending/Deferred Candidate, Unresolved Request, Restore Status, Reconciliation Gate, Pending Request ID/Volume, Position array)
- `HydrateRuntimeState()` เรียก `InvalidateRuntimeState()` เป็นบรรทัดแรก (ก่อน Validation ใด ๆ) แล้วตั้ง `RESTORE_ERROR` และเรียกซ้ำใน Failure Path ของ `ApplyHydratedState()` — ทุกจุดที่ Hydration คืน `false` จึงจบที่ Runtime ที่ใช้งานไม่ได้จริง ไม่ใช่แค่ flag
- Public Accessors ที่เคยอ่านค่าไม่ผ่าน initialization ถูกกันทั้งหมด: `GetAnchorState()` คืน `TGK_GRID_LEVEL_WAIT_ACTIVATION` (ค่าที่ไม่เข้าเงื่อนไข Entry) เมื่อไม่ initialized, `PendingRequestId()`/`PersistedInstanceId()` คืน `""`, `PendingRequestVolume()` คืน `0.0`, `AnchorPrice()` คืน `0.0`, `GetLevelPrice()` คืน `false` (ส่วน `PositionCount()`, `TryGetPositionAt()`, `GetLevelState()`, `IsReconciliationPending()`, `IsRequestUnresolved()`, `HasPendingAnchorActivation()`, `Matches*()`, `UpdatePrice()` มี Guard เดิมอยู่แล้ว)
- `RestoreStatus()` ยังคงคืน `TGK_GRID_RUNTIME_RESTORE_ERROR` ได้ตามเดิม เพราะเป็นตัวบอกเหตุผลที่ Restore ล้มเหลว

**Test:** §4 (B-10) — Hydrate สำเร็จ (Anchor ACTIVE + 3 Mappings) แล้ว Hydrate ซ้ำด้วย Persisted Configuration ที่ Config Epoch ไม่ตรง (ล้มเหลวก่อน Engine Initialize) แล้วยืนยัน Accessor ทุกตัวว่าไม่เหลือ State เก่า, Reducer ไม่ถูกแก้ และ Price Update ไม่ Offer Candidate

## 4. Tests Added

`Experts/TGK/Tests/Grids/test_grid_runtime_restoration.mq5` — ไม่มี Trade Request และไม่ใช้ Account Position API

| Test | Scenario | การยืนยันหลัก |
|---|---|---|
| B-01 | Anchor `READY` จาก committed Snapshot | Hydration สำเร็จ, `RESTORE_PENDING_RECONCILIATION`, Gate ปิด, ทุก Level `READY`, ไม่มี Mapping, `RegisterInitialAnchorPosition()` ถูกปฏิเสธ, Price Update ไม่สร้าง Candidate, **(F-01)** `TryGetPersistedConfig()` คืน Instance Identity และ Persisted Level Count = Engine Count + 1 |
| B-02 | Anchor `ACTIVE` พร้อม Mapping | Anchor `ACTIVE`, Mapping ผูก Anchor target, Identifier/Ticket/Volume ตรง, Level ปกติคง `READY` |
| B-03 | Anchor `WAIT_ACTIVATION` หลัง Full Close | State คงเดิม, ไม่มี Mapping, ไม่มี Activation Pending, Price Update ไม่สร้าง Candidate/Activation |
| B-04 | Normal Levels หลาย State | Level 0/2/6/7 `READY`, 1 `ACTIVE`, 3/5 `WAIT_ACTIVATION`; Level 4 ไม่ถูกเขียนทับด้วย Quote-derived `WAIT_ACTIVATION` |
| B-05 | หลาย Position Mappings | Anchor + Level 1 + Level 6: Identifier/Target/Ticket/Volume ถูกต้องครบ, `TryGetPositionAt(3, ...)` คืน false |
| B-06 | Unresolved Entry Request | Reducer และ Runtime คง Unresolved + Request ID, ไม่มี Mapping, Target คง `READY`, Gate ยังปิด; **(F-05)** `PendingRequestVolume()` เท่ากับ `requested_volume` ที่ Reducer Project และ Volume 0 / ติดลบ / Non-finite (`MathArcsin(2.0)`) ถูกปฏิเสธพร้อม `RESTORE_ERROR` และไม่มี Partial State; **(F-03)** `Reconcile()` ระหว่าง Gate ปิดคืน `ERROR` และ Request/Volume/Target State ไม่เปลี่ยน |
| B-07 | Reducer Recovery Error / Projection ไม่ครบ | Replay ล้มเหลว → `RECOVERY_ERROR`, ไม่มี Anchor State, ไม่ Activate Runtime, Hydration ที่ Projection ไม่ครบถูกปฏิเสธพร้อม `RESTORE_ERROR` และใช้งานไม่ได้ |
| B-08 | Identity/Symbol/Magic/Mode/Epoch mismatch + Persisted Configuration | `MatchesContext()` ปฏิเสธทั้ง 5 กรณี; Projection เก็บ Instance ID, Position Identifier และ Target ถูกต้อง; **(F-01)** Projection คืน Symbol/Magic/Mode/Anchor/Step/Lower/Upper/Persisted Count/Epoch ครบ; Hydration ปฏิเสธ Anchor ที่เลื่อนทั้งชุดแต่ยังได้ 8 Level, Anchor ต่าง, Grid Step ต่าง, Lower Bound ต่าง, Upper Bound ต่าง, Persisted Level Count ต่าง และ **(F-02)** Mode ต่าง — ทุกกรณีไม่มี Partial State, `RESTORE_ERROR`, Gate ปิด, Instance ว่าง และ Reducer Sequence/Mapping/Anchor ไม่เปลี่ยน; Anchor ที่ต่างภายใน epsilon (`grid_step * 5e-10`) ยัง Hydrate ผ่าน; **(F-11)** หลัง Hydrate ด้วย epsilon นี้ Runtime Anchor Price เท่ากับค่า Persisted, Level Price 0/4/7 เท่ากับ 3980/4005/4020 (Persisted Geometry) และ Index 8 (เกินจำนวน Level ที่ Persist) อ่านไม่ได้; กรณี Shifted Anchor ที่ถูกปฏิเสธก็ไม่เปิดเผย Anchor Price |
| B-09 | Mapping ซ้ำ/Invalid Target | ซ้ำ Identifier, ซ้ำ Target, Level Index เกินช่วง, Anchor Mapping ที่มี Level Index และ Mapping ไปยัง Level ที่ `READY` ถูกปฏิเสธทั้งหมด |
| B-10 | ล้มเหลวกลางรายการ Mapping | Reject ทั้งชุด, ไม่มี Position, `GetLevelState()` ใช้งานไม่ได้, Price Update คืน Error; Projection เดิมยัง Hydrate ได้ครบ 3 รายการ; **(F-12)** Hydrate ซ้ำบน Coordinator เดิมด้วย Config Epoch ที่ไม่ตรง (ล้มเหลวก่อน Engine Initialize) ต้องคืน `RESTORE_ERROR` และไม่เหลือ Anchor State/Anchor Price/Level State/Level Price/Position/Pending Request/Instance Identity/Gate/Candidate ใด ๆ พร้อม Reducer Sequence และ Mapping ไม่เปลี่ยน |
| B-11 | Restore Dataset เดิมซ้ำผ่าน Snapshot Storage | Runtime Projection เหมือนเดิมทุกฟิลด์, Journal Sequence ไม่เปลี่ยนจาก Hydration, Sequence ตรง committed checkpoint |
| B-12 | Snapshot Checkpoint + Journal Replay | Checkpoint 2, Journal 4 records, Next Sequence 7; Runtime สะท้อน Level 1 `ACTIVE` + Mapping หลัง Replay และไม่ Append Journal |
| B-13 | Restore สำเร็จแต่ยังไม่ Reconcile Live Positions | หลาย Price Update ไม่สร้าง Candidate, `RecordEntryRequest()` ถูกปฏิเสธ, Gate ยังปิด, Level/Mapping ไม่เปลี่ยน; **(F-03)** `Reconcile()` ระหว่าง Gate ปิดคืน `ERROR`, ไม่ Offer Candidate, Level/Mapping/Restore Status ไม่เปลี่ยน |

Helper ที่เพิ่มใน Test EA: `HydrateRequest()` (Hydration ด้วย Input ที่ระบุชัดเจนเพื่อแปรผันทีละฟิลด์), `HydrateFixture()` (Request ที่ตรงกับ Fixture), `AssertRejectedHydration()` (ตรวจว่า Rejected Hydration ไม่เหลือ Runtime ที่ใช้งานได้)

## 5. Tests Executed and Results

**Implementer ไม่ได้ Run MetaEditor/MT5 Test Suite** — ตาม Working Agreement ผู้ Run คือ Product Owner

| Test Run | ผู้ Run | ผล |
|---|---|---|
| `test_grid_runtime_restoration.mq5` (B-01 ถึง B-13) — Source **ก่อน** Remediation | Product Owner (MetaEditor/MT5), 2026-11-26 | PASS ตามรายงานของ Owner |
| Latest no-trade Grid Regression Suite — Source **ก่อน** Remediation | Product Owner (MetaEditor/MT5), 2026-11-26 | PASS ตามรายงานของ Owner |
| `test_grid_runtime_restoration.mq5` (B-01 ถึง B-13 รวม Assertion ของ Remediation) — Source **หลัง** Remediation รอบที่ 1 | Product Owner (MetaEditor/MT5), 2026-11-26 | PASS ตามรายงานของ Owner |
| Latest no-trade Grid Regression Suite — Source **หลัง** Remediation รอบที่ 1 | Product Owner (MetaEditor/MT5), 2026-11-26 | PASS ตามรายงานของ Owner |
| Test Suite ครบทุกไฟล์ (รวม `test_grid_runtime_restoration.mq5` B-01 ถึง B-13 พร้อม Assertion F-11/F-12) — Source **หลัง** Remediation รอบที่ 2 | Product Owner (MetaEditor/MT5), 2026-11-26 | PASS ตามรายงานของ Owner |
| Latest no-trade Grid Regression Suite — Source **หลัง** Remediation รอบที่ 2 | Product Owner (MetaEditor/MT5), 2026-11-26 | PASS ตามรายงานของ Owner |

**ผล Runtime ของ Source หลัง Remediation รอบที่ 1: PASS ตามรายงานของ Product Owner (2026-11-26)**

- Product Owner รายงานว่า Run Test ครบทั้งชุดบน Source ที่ Compile ตาม §6 แล้วผ่านทั้งหมด; Implementer ไม่ได้ Run Test เอง และไม่ได้สร้างตัวเลข Assertion/เวลารันขึ้นเอง
- ยังไม่มี Log ดิบหรือผลราย Assertion แนบมากับรายงานนี้; หาก Product Owner ส่ง Log มา จะบันทึกเพิ่มใน §5 โดยไม่แก้ข้อความสรุป
- Static Review, Compile PASS และ `git diff --check` **ไม่ใช่ Runtime Evidence**

**ผล Runtime ของ Source หลัง Remediation รอบที่ 2 (F-11/F-12): PASS ตามรายงานของ Product Owner (2026-11-26)**

- Product Owner รายงานว่า Run Test ครบทุกไฟล์บน Source ปัจจุบัน (§6 Remediation 2) แล้วผ่านทั้งหมด — รวม Assertion ใหม่ของ F-11 (Engine Geometry มาจาก Persisted Configuration) ใน B-08 และ F-12 (Failed Hydration ไม่เหลือ Stale State) ใน B-10
- Implementer ไม่ได้ Run Test เอง และไม่ได้สร้างตัวเลข Assertion/เวลารันขึ้นเอง
- ยังไม่มี Log ดิบหรือผลราย Assertion แนบมากับรายงานนี้; หาก Product Owner ส่ง Log มา จะบันทึกเพิ่มใน §5 โดยไม่แก้ข้อความสรุป
- Runtime Verification ครบทั้ง 2 รอบแล้ว; ขั้นที่เหลือคือ CTO Formal Code Review (WP-05B ยังไม่ Done)

## 6. Compile Evidence

สภาพแวดล้อม: MetaEditor64 ผ่าน Wine ตาม Verified Compile Environment ใน `AGENTS.md` (`WINEPREFIX="$HOME/wine-python-mt5"`, `/inc:` ชี้ repository root)

ผล compile รอบ Remediation (2026-11-26, Source ฉบับปัจจุบัน) — ทุกโปรแกรม `0 errors, 0 warnings`:

| Program | Result |
|---|---|
| `Experts/TGK/Tests/Grids/test_grid_runtime_restoration.mq5` | `Result: 0 errors, 0 warnings, 8337 ms elapsed, cpu='X64 Regular'` |
| `Experts/TGK/Tests/Grids/test_grid_entry_mapping_reducer.mq5` | `Result: 0 errors, 0 warnings, 7446 ms elapsed, cpu='X64 Regular'` |
| `Experts/TGK/Tests/Grids/test_grid_entry_mapping_snapshot.mq5` | `Result: 0 errors, 0 warnings, 10484 ms elapsed, cpu='X64 Regular'` |
| `Experts/TGK/Tests/Grids/test_grid_level_runtime_coordinator.mq5` | `Result: 0 errors, 0 warnings, 3197 ms elapsed, cpu='X64 Regular'` |
| `Experts/TGK/Tests/Grids/test_grid_entry_execution.mq5` | `Result: 0 errors, 0 warnings, 6157 ms elapsed, cpu='X64 Regular'` |
| `Experts/TGK/Tests/Grids/test_grid_entry_execution_resolver.mq5` | `Result: 0 errors, 0 warnings, 4595 ms elapsed, cpu='X64 Regular'` |
| `Experts/TGK/Tests/Grids/test_grid_entry_execution_pipeline.mq5` | `Result: 0 errors, 0 warnings, 4861 ms elapsed, cpu='X64 Regular'` |

Consumer ที่ครอบคลุม: ทุกโปรแกรมที่ include `GridEntryMappingReducer.mqh`, `GridEntryMappingSnapshotStorage.mqh`, `GridLevelRuntimeCoordinator.mqh` โดยตรงหรือผ่าน `GridEntryExecutionAdapter.mqh` / `GridEntryExecutionResolver.mqh` / `GridEntryExecutionPipeline.mqh`

**ผล compile รอบ Remediation 2 (F-11/F-12 — Source ฉบับปัจจุบัน) — ทุกโปรแกรม `0 errors, 0 warnings`:**

| Program | Result |
|---|---|
| `Experts/TGK/Tests/Grids/test_grid_runtime_restoration.mq5` | `Result: 0 errors, 0 warnings, 7681 ms elapsed, cpu='X64 Regular'` |
| `Experts/TGK/Tests/Grids/test_grid_level_engine.mq5` | `Result: 0 errors, 0 warnings, 2290 ms elapsed, cpu='X64 Regular'` |
| `Experts/TGK/Tests/Grids/test_grid_level_runtime_coordinator.mq5` | `Result: 0 errors, 0 warnings, 4197 ms elapsed, cpu='X64 Regular'` |
| `Experts/TGK/Tests/Grids/test_grid_entry_mapping_reducer.mq5` | `Result: 0 errors, 0 warnings, 7321 ms elapsed, cpu='X64 Regular'` |
| `Experts/TGK/Tests/Grids/test_grid_entry_mapping_snapshot.mq5` | `Result: 0 errors, 0 warnings, 9707 ms elapsed, cpu='X64 Regular'` |
| `Experts/TGK/Tests/Grids/test_grid_entry_execution.mq5` | `Result: 0 errors, 0 warnings, 5833 ms elapsed, cpu='X64 Regular'` |
| `Experts/TGK/Tests/Grids/test_grid_entry_execution_resolver.mq5` | `Result: 0 errors, 0 warnings, 5193 ms elapsed, cpu='X64 Regular'` |
| `Experts/TGK/Tests/Grids/test_grid_entry_execution_pipeline.mq5` | `Result: 0 errors, 0 warnings, 5066 ms elapsed, cpu='X64 Regular'` |

ขอบเขตรอบที่ 2 กว้างกว่ารอบแรกเพราะ `GridLevelEngine.mqh` เปลี่ยน (เพิ่ม `Reset()`): ครบทุกโปรแกรมที่ include `GridLevelEngine.mqh`, `GridLevelRuntimeCoordinator.mqh` หรือ `GridEntryMappingReducer.mqh` โดยตรงหรือโดยอ้อม (ไล่ `#include` แบบ Transitive) รวม 8 โปรแกรม

Compile Log: เขียนเป็น `wp05b2_<program>.log` / `wp05b3_<program>.log` ที่ repository root แล้วลบหลังอ่านผล; ไม่มี Log ค้างและไม่มีไฟล์ `.ex5` เป็น Untracked artifact (`git status` แสดงเฉพาะ Source และ Docs)

Compile PASS เป็นเพียง Compile Evidence **ไม่ใช่ Test PASS**

## 7. Remaining Issues and Limitations

1. **User Runtime Verification: ผ่านทั้ง 2 รอบ** — Product Owner รายงาน PASS 2026-11-26 ทั้งบน Source หลัง Remediation รอบที่ 1 และบน Source หลัง Remediation รอบที่ 2 (F-11/F-12) โดย Run Test ครบทุกไฟล์ รวม `test_grid_runtime_restoration.mq5` และ Latest no-trade Grid Regression; ไม่มี Blocking Item ด้าน Runtime เหลือก่อน Formal Review
2. **Reconciliation Gate ยังไม่มี Release Path** — WP-05B ตั้งใจไม่เปิด Gate; `IsReconciliationPending()` คืน `true` จนกว่า WP-05C จะเพิ่มขั้นตอนยืนยัน Complete/Stable Live Position Snapshot (อยู่นอก Scope นี้)
3. **F-04 ยังเปิดอยู่ (Deferred to WP-05C)** — `ValidateSnapshot()`/`StoreCurrentPositions()` ยังไม่บังคับ `position_identifier`; เมื่อ WP-05C ส่ง Position Record ต้องส่ง Identifier ที่ถูกต้องและห้ามให้ค่าว่างทับค่าที่ Hydrate มา
4. **Hydration API มี 16 พารามิเตอร์** — เพิ่ม `persisted_config` ตาม F-01; CTO ระบุว่าไม่ต้อง Refactor เป็น Input Struct (F-06)
5. **`IsReconciliationPending()` ยังคืน `false` เมื่อ Coordinator ไม่ initialized (F-07)** — `RestoreStatus()` เป็นตัวชี้ Restore Error ที่เป็นทางการ
6. **Helper Predicate ซ้ำ (F-08)** — `IsDecimalIdentity()`/`IsTokenLiteral()` ใน Coordinator ยังซ้ำกับ Reducer; คงไว้ตามคำสั่ง CTO
7. **`UpdatePrice()` ระหว่าง Gate ปิดคืน `NO_CANDIDATE` (F-09)** — ไม่คืน `REQUEST_UNRESOLVED` แม้มี Restored Request; `IsRequestUnresolved()`/`PendingRequestId()` ยังเป็น Accessor แยก
8. **Hydration ล้มเหลวจะทิ้ง Runtime เดิม** — เพื่อ All-or-Nothing ในเชิง Activation; Caller ต้องสร้าง Instance/Coordinator ใหม่หรือคง Fail Closed
9. **Level State Projection ต้องครบทุก Level** — Hydration ปฏิเสธ Projection ที่ไม่ครอบคลุม Normal Level ทุกตัวและไม่รับ `WAIT_RETURN` ที่หลุดมาจาก Persistence รุ่นเก่า
10. **`normal_level_count` คือ Engine Level Count** — ต้องเท่ากับ `persisted_level_count - 1`; ตอนนี้ Hydration ตรวจความสัมพันธ์นี้เองแล้ว (ไม่ใช่แค่เอกสารกำกับ)
11. **WP-05C/WP-05D ไม่ได้ Implement** — ไม่มี MT5 Open Positions scan, Deal History ingestion, Production `OnTradeTransaction` หรือ Entry/Close execution
12. **เอกสาร Status ระดับโครงการยังไม่อัปเดต** — `PROJECT_STATUS.md`/`Docs/EAs/Grid/*` และ Documentation Consistency Gate เป็นขั้นของ CTO หลัง Formal Review; รายนี้หยุดที่ Implementation + Remediation ของ WP-05B เท่านั้น
13. **`GetAnchorState()` ของ Coordinator ที่ไม่ initialized คืน `TGK_GRID_LEVEL_WAIT_ACTIVATION`** — เป็น Placeholder ที่ไม่เข้าเงื่อนไข Entry (ไม่ใช่ `READY`) แทนการอ่าน `m_engine` ตรง ๆ ซึ่งเคยค้างค่าเก่า; Caller ที่ต้องการแยก "ยังไม่ initialized" ควรตรวจ Accessor ที่ Fail Closed เช่น `GetLevelState()`/`GetLevelPrice()` หรือสถานะ `RestoreStatus()`
14. **`Initialize()` ยังไม่ Invalidate Runtime Field ชุดเดิมเมื่อล้มเหลว** — F-12 จำกัดขอบเขตที่ Failed Hydration; Public Accessor ที่เหลือถูก Guard ด้วย `m_initialized` ทั้งหมดจึงไม่เปิดเผย State เก่า แต่ Field ภายในยังค้างจนกว่าจะ Invalidate; หากต้องการให้ `Initialize()` ล้มเหลวแล้วล้างด้วยเช่นกัน ถือเป็นการเปลี่ยน Behavior ของ API เดิมและต้องขออนุมัติ CTO
