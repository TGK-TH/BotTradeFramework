# WP-05C — Implementation Report

**Card:** WP-05C Open Positions Reconciliation
**Implementer:** Freebuff
**วันที่:** 2026-11-27
**สถานะ:** Implemented — User Verification PASS หลัง Remediation CR-01…CR-06 (Product Owner รัน MT5 Test ครบทุกไฟล์) — รอ CTO Code Review รอบถัดไป
**Branch:** `feature/grid-trading`
**Pre-change tree:** Clean (ไม่มี staged/unstaged/untracked changes ก่อนเริ่มงาน)

> เอกสารนี้เป็นรายงานของ Implementer เท่านั้น ไม่ใช่ Code Review
> ผล MT5 Test ใน §12 เป็นข้อมูลที่ Product Owner รันและรายงานเอง — Implementer ไม่ได้รัน Test Suite

---

## 1. สรุปงานที่ทำ

Implement Authoritative Open Positions Reconciliation ตาม Scope และ Technical Contract ใน `SPEC.md` / `TEST_PLAN.md` / `IMPLEMENTATION_TASK.md` โดย:

- แยก Snapshot Acquisition ออกจาก Pure Reconciliation Policy ผ่าน Port ที่ Inject ได้
- เพิ่ม Read-only MT5 Position Adapter และ Stable Two-scan Acquirer
- เพิ่ม Versioned One-record Reconciliation Batch ใน Reducer พร้อม Transactional Apply
- เพิ่ม Durable Batch Coordination ผ่าน Mapping Journal Port ที่ครอบ Snapshot Storage เดิม
- เพิ่ม Coordinator Hydration จาก Canonical Reducer Projection และ Explicit Gate-release API

ไม่มีการเปลี่ยนแปลง Grid Trading Behavior, Entry Selection, Grid Geometry, Reset/Close-confirmation Semantics เดิม หรือ WP-05A.2 Close State Rule

---

## 2. Changed Files

### New Source

| ไฟล์ | Responsibility |
|---|---|
| `Include/BotTrade/Grid/GridOpenPositionSnapshot.mqh` | Snapshot DTO, Fakeable Acquisition Port, Read-only MT5 Port, Stable Two-scan Acquirer, Consumed-token Guard |
| `Include/BotTrade/Grid/GridOpenPositionReconciliation.mqh` | Journal Port + Production Adapter, Pure Reconciliation Diff/Policy, Durable Batch Coordination, Coordinator Hydration + Gate Release |

### Modified Source

| ไฟล์ | การเปลี่ยนแปลง |
|---|---|
| `Include/BotTrade/Grid/GridEntryMappingReducer.mqh` | เพิ่ม `RECONCILIATION_BATCH` lifecycle payload + `ApplyReconciliationBatch()`, `ApplyCommittedRecord()`, `TryGetDealAssociationProjection()`, state backup/restore helper |
| `Include/BotTrade/Grid/GridLevelEngine.mqh` | เพิ่ม `TryGetPostCloseState()` (read-only preview ของ WP-05A.2 rule) |
| `Include/BotTrade/Grid/GridLevelRuntimeCoordinator.mqh` | เพิ่ม `STGKGridReconciliationGateProof`, `TryGetPostCloseState()`, `ReleaseReconciliationGate()`, freshness token fields |

### New Tests

| ไฟล์ | Coverage |
|---|---|
| `Experts/TGK/Tests/Grids/test_grid_open_position_snapshot.mq5` | C-01, C-02, C-03, C-04, Empty Snapshot, Consumed/stale token |
| `Experts/TGK/Tests/Grids/test_grid_open_position_reconciliation.mq5` | C-05 … C-17 + Foreign filter + released-Gate refusal |

### Extended Tests

| ไฟล์ | Coverage ที่เพิ่ม |
|---|---|
| `Experts/TGK/Tests/Grids/test_grid_entry_mapping_reducer.mq5` | Batch atomic apply, malformed batch (no prefix applied), RECOVERY_ERROR, Deal Association projection |
| `Experts/TGK/Tests/Grids/test_grid_entry_mapping_snapshot.mq5` | One-record batch durability, replay after restart, sequence continuity, rotation check |
| `Experts/TGK/Tests/Grids/test_grid_level_runtime_coordinator.mq5` | Gate release refused before/with mismatch, accepted release, quote baseline refresh, no Candidate during release, no double release |

ไม่มีไฟล์ใดถูกลบ และ `git diff --stat` เป็นการเพิ่มบรรทัดทั้งหมด (0 deletions) — โค้ดเดิมไม่ถูกแก้ไขเชิงความหมาย

---

## 3. API / Data Contracts ที่เพิ่ม

### 3.1 `GridOpenPositionSnapshot.mqh`

- `struct STGKGridOpenPositionRecord` — `position_identifier` (decimal string), `ticket` (`ulong`), `symbol`, `magic_number`, `volume`
- `struct STGKGridOpenPositionSnapshot` — `status`, `symbol`, `magic_number`, `first_scan_total`, `second_scan_total`, `generation`, `base_sequence`, `consumed`
- `ENUM_TGK_GRID_OPEN_POSITION_STATUS` — `INVALID`, `UNSTABLE`, `COMPLETE`
- `class CTGKGridOpenPositionSource` — `TotalPositions`, `TicketAt`, `SelectTicket`, `ReadSelectedPosition`
- `class CTGKGridMT5OpenPositionSource` — Production read-only adapter (`PositionsTotal`, `PositionGetTicket`, `PositionSelectByTicket`, Position getters เท่านั้น)
- `class CTGKGridOpenPositionAcquirer` — `Initialize`, `Acquire`, `Consume`, `CopyOwnedPositions`, `OwnedCount`, `TryGetOwnedAt`, `Generation`, `AcceptedGeneration`, `IsConsumed`, `SetMaxAttemptsForTest`

### 3.2 `GridEntryMappingReducer.mqh`

- `bool ApplyCommittedRecord(record_type, payload)` — Apply record ที่ Persist แล้วที่ `LastSequence() + 1` โดยไม่เขียน Journal
- `bool TryGetDealAssociationProjection(identifier, has_association, request_id, associated_volume)` — Read-only
- `bool ApplyReconciliationBatch(payload)` — Private, เรียกผ่าน `ApplyLifecycleUpdate`
- Batch payload: `v1|RECONCILIATION_BATCH|<count>|POSITION_METADATA|<id>|<vol>|<ticket>|POSITION_CLOSED|<id>|<STATE>|...`
- `#define TGK_GRID_MAPPING_MAX_RECONCILIATION_EVENTS` (= `TGK_GRID_MAPPING_MAX_POSITIONS`)

### 3.3 `GridLevelEngine.mqh` / `GridLevelRuntimeCoordinator.mqh`

- `bool CTGKGridLevelEngine::TryGetPostCloseState(is_anchor, level_index, bid, ask, state)` — Read-only, ใช้ `StateAfterPositionClose()` เดิม
- `struct STGKGridReconciliationGateProof` — `instance_id`, `symbol`, `magic_number`, `mode`, `config_epoch`, `snapshot_generation`, `base_sequence`
- `bool CTGKGridLevelRuntimeCoordinator::TryGetPostCloseState(...)`
- `bool CTGKGridLevelRuntimeCoordinator::ReleaseReconciliationGate(proof, anchor_state, level_states, positions, entry_request, bid, ask)`

### 3.4 `GridOpenPositionReconciliation.mqh`

- `ENUM_TGK_GRID_RECONCILIATION_STATUS` — `NO_CHANGE`, `APPLIED`, `INVALID`, `CONFLICT`, `ORPHAN`, `STORAGE_FAILED`, `APPLY_FAILED`, `HYDRATION_FAILED`, `GATE_FAILED`
- `class CTGKGridMappingJournalPort` — `ReadNextSequence`, `AppendOne`
- `class CTGKGridSnapshotStorageJournalPort` — Production adapter ครอบ `CTGKGridEntryMappingSnapshotStorage` (ไม่ Bypass Sequence/Rotation Contract)
- `class CTGKGridOpenPositionReconciler` — `BuildBatch(...)` Pure Diff/Policy
- `class CTGKGridOpenPositionReconciliation` — `Initialize`, `Run`, `IsRecoveryRequired`

### 3.5 ลำดับการทำงานของ `Run()`

`Gate pending check → Acquire (two scans) → Consume (base_sequence + generation) → BuildBatch (validate ทั้งหมดก่อนเขียน) → ReadNextSequence/AppendOne (1 record) → ApplyCommittedRecord → BuildCoordinatorProjection จาก Reducer → HydrateRuntimeState → ReleaseReconciliationGate`

Failure path สำคัญ:

- Acquire/Consume/BuildBatch ล้มเหลว → ไม่มีการเขียนใด ๆ, Gate ยังปิด
- Append ล้มเหลว → `STORAGE_FAILED`, Reducer/Coordinator ไม่เปลี่ยน
- Append สำเร็จแต่ Apply ล้มเหลว → `APPLY_FAILED` + `IsRecoveryRequired() == true`, Gate คงปิด (Recovery จาก Journal เท่านั้น)
- Hydration/Gate Release ล้มเหลวหลัง Durable Commit → Runtime คง Gated ไม่มี Rollback หรือ Compensating State

---

## 4. Test Inventory ที่เพิ่ม

| Test EA | จำนวน Test block ที่เพิ่ม | หมายเหตุ |
|---|---|---|
| `test_grid_open_position_snapshot.mq5` | 11 | ไฟล์ใหม่ |
| `test_grid_open_position_reconciliation.mq5` | 14 | ไฟล์ใหม่ |
| `test_grid_entry_mapping_reducer.mq5` | 4 | ต่อท้ายก่อน `EndSuite()` |
| `test_grid_entry_mapping_snapshot.mq5` | 1 | ต่อท้ายก่อน `EndSuite()` |
| `test_grid_level_runtime_coordinator.mq5` | 3 | ต่อท้ายก่อน `EndSuite()` |

ทุก Test ใช้ Fake Ports/Fake Records เท่านั้น ไม่มี `CTrade`, `OrderSend`, `PositionClose` หรือ Trade Request และไม่อ่าน/แก้ไข MT5 Account จริง

---

## 5. Compile Evidence (Developer Compile Gate)

Environment ตาม `AGENTS.md` §Developer compile gate: `WINEPREFIX="$HOME/wine-python-mt5"`, wine-11.0, `/inc:` ชี้ที่ Repository Root

Affected consumers (Direct + Transitive) หาได้จาก `grep -rl` ของ Header ที่เปลี่ยนทั้ง 6 ไฟล์:

```text
Experts/TGK/Tests/Grids/test_grid_entry_mapping_reducer.mq5
Experts/TGK/Tests/Grids/test_grid_entry_mapping_snapshot.mq5
Experts/TGK/Tests/Grids/test_grid_level_engine.mq5
Experts/TGK/Tests/Grids/test_grid_level_runtime_coordinator.mq5
Experts/TGK/Tests/Grids/test_grid_open_position_reconciliation.mq5
Experts/TGK/Tests/Grids/test_grid_open_position_snapshot.mq5
Experts/TGK/Tests/Grids/test_grid_runtime_restoration.mq5
```

ผล Compile รอบสุดท้าย (หลังแก้ไขทั้งหมด):

```text
test_grid_entry_mapping_reducer       Result: 0 errors, 0 warnings
test_grid_entry_mapping_snapshot      Result: 0 errors, 0 warnings
test_grid_level_engine                Result: 0 errors, 0 warnings
test_grid_level_runtime_coordinator   Result: 0 errors, 0 warnings
test_grid_open_position_reconciliation Result: 0 errors, 0 warnings
test_grid_open_position_snapshot      Result: 0 errors, 0 warnings
test_grid_runtime_restoration         Result: 0 errors, 0 warnings
```

Compile Evidence เป็นหลักฐานของ Compile เท่านั้น **ไม่ใช่หลักฐานของ Runtime/Test PASS**

---

## 6. Tests Run / Not Run

- **ไม่ได้รัน** MT5 Test Suite ใด ๆ — ตาม `AGENTS.md` และ Handoff Product Owner เป็นผู้รัน
- **ยังไม่ถูกตรวจสอบด้วยการรันจริง:** ทุก Test ใน §4, Latest no-trade Grid Regression Suite
- Product Owner ต้องรันอย่างน้อย:
  1. `test_grid_open_position_snapshot.mq5`
  2. `test_grid_open_position_reconciliation.mq5`
  3. `test_grid_entry_mapping_reducer.mq5`
  4. `test_grid_entry_mapping_snapshot.mq5`
  5. `test_grid_level_runtime_coordinator.mq5`
  6. `test_grid_runtime_restoration.mq5`
  7. Latest no-trade Grid Regression Suite ทั้งชุด

---

## 7. Self-Review

### 7.1 Contract trace

| Requirement | การ Implement |
|---|---|
| Two full scans ใน Serialized Event เดียว | `Acquire()` เรียก `CaptureScan()` สองครั้งต่อเนื่อง ไม่มี Queue |
| Scan failure ≠ Empty | `CaptureScan()` คืน false → `INVALID`; Empty ยอมรับเฉพาะเมื่อทั้งสองรอบสำเร็จและ Total = 0 |
| Account Total เปลี่ยนระหว่าง Scan | ตรวจ `TotalPositions()` ซ้ำท้าย Scan, ไม่ตรง → `INVALID`; ความเสถียรระหว่างสอง Scan ตัดสินจาก Owned Position Set ไม่ใช่ Account Total |
| Ticket 0 / Select ล้มเหลว / Property Read ล้มเหลว | ทุกจุดคืน `INVALID` ทั้งชุด |
| Order-independent Owned set comparison | `SetsMatch()` match ด้วย Identifier และเทียบ Ticket/Symbol/Magic/Volume |
| Bounded Retry | `TGK_GRID_OPEN_POSITION_MAX_ATTEMPTS = 3` เฉพาะกรณี Scan ไม่ตรงกัน |
| Consume ปฏิเสธ used/stale/base-sequence | `Consume()` ตรวจ generation ปัจจุบัน, accepted generation, `m_consumed`, `base_sequence` |
| Match ด้วย Position Identifier เท่านั้น | `FindLiveIndex()` ด้วย Identifier; Ticket เป็น Operational Handle |
| Volume ลด → Metadata หนึ่งรายการ (Volume + Ticket) | `POSITION_METADATA` ผ่าน `ApplyPositionMetadata()` เดิม |
| Volume เท่าเดิม + Ticket เปลี่ยน → Metadata | เช่นเดียวกัน |
| Volume เพิ่ม → Conflicting Evidence | `CONFLICT`, ไม่เขียน record |
| Mapped Identifier หาย → Reason-free Full Close | `POSITION_CLOSED` หนึ่งรายการต่อ Position ใน Batch เดียว |
| Post-close state ณ Consume Time (BUY=Ask, SELL=Bid) | `TryGetPostCloseState()` เรียก `StateAfterPositionClose()` เดิม ไม่ Duplicate Rule |
| Orphan / Unproven Ownership → Fail Closed | `IsUnresolvedEntryEvidence()` ตรวจ Request ID + Identifier + Associated Volume; ไม่ผ่าน → `ORPHAN` |
| One-record Durable Batch | `RECONCILIATION_BATCH` เดียวต่อ Snapshot; ไม่ Append แยกต่อ Position |
| Transactional Apply | Backup/Restore ของ Requests/Deals/Positions/Levels/Anchor/RecoveryStatus |
| No-op ไม่ Append/ไม่เพิ่ม Sequence | `NO_CHANGE` ก่อนถึง Journal |
| Duplicate ไม่สร้าง Close ซ้ำ | Mapping ถูกลบใน Batch แรก; Observation ซ้ำเป็น no-op |
| ไม่ Bypass Sequence/Rotation | `AppendOne()` ผ่าน `CTGKGridEntryMappingSnapshotStorage::Append()` เท่านั้น |
| Hydration จาก Reducer เท่านั้น | `BuildCoordinatorProjection()` อ่าน `TryGetPersistedConfig`, `TryGetAnchorState`, `LevelStateAt`, `TryGetPositionMappingAt`, `TryGetUnresolvedRequest` |
| Gate Release ต้องมี Proof + Projection ตรงกัน | ตรวจ Identity/Symbol/Magic/Mode/Epoch/Generation/Base Sequence + Level/Anchor/Position/Request projection |
| Refresh Quote Baseline, ไม่ Emit Candidate | `ReleaseReconciliationGate()` set `m_previous_*`/`m_current_*` และปฏิเสธถ้ามี Candidate/Activation ค้าง |

### 7.2 Failure-path review

- Append failure → ไม่มี Reducer/Coordinator mutation (ทดสอบแล้วใน C-14)
- Apply failure หลัง Append → `IsRecoveryRequired()`, Gate คงปิด, ไม่มี Rollback
- Hydration failure → Coordinator `RESTORE_ERROR` และไม่ Usable (พฤติกรรมเดิมของ `HydrateRuntimeState`)
- Gate Release failure → `m_reconciliation_pending` คงเดิม (ไม่ Clear ก่อนตรวจครบ — ทุก Guard อยู่ก่อน mutation)

### 7.3 Safety checks

- ไม่มี `CTrade`, `OrderSend`, `PositionClose`, Buy/Sell ใน Module ใหม่ (ตรวจด้วย grep)
- ไม่มี `OnTradeTransaction`, ไม่มี Closing Deal History, ไม่มี TP/NON_TP หรือ Close Reason
- `GridPositionReconciler.mqh` ไม่ถูกแก้ไข — Reset/Close-confirmation semantics เดิมคงอยู่
- `GridEntryExecutionAdapter.mqh` ไม่อยู่ใน Dependency ของ Module ใหม่

### 7.4 ข้อสังเกต / Known Limitations

1. **`Run()` ทำงานได้ครั้งเดียวต่อ Hydration** — ต้องมี `IsReconciliationPending() == true` หลัง Gate ถูกปล่อยแล้วจะต้อง Hydrate ใหม่ก่อน Reconcile รอบถัดไป นี่เป็นผลจาก WP-05B Gate Contract ไม่ใช่ Regression
2. **`RestoreStatus()` ยังคง `PENDING_RECONCILIATION` หลัง Gate Release** — ค่านี้บันทึกวิธีที่ Runtime ถูก Restore ไว้ ไม่ใช่สถานะ Gate (`IsReconciliationPending()` เป็นตัวชี้ Gate ที่เป็นทางการ) เลือกไม่เปลี่ยน Enum เพื่อไม่ให้ WP-05B Test เดิมเปลี่ยนความหมาย
3. **Batch ที่ใหญ่เกิน `TGK_GRID_MAPPING_MAX_RECORD_BYTES`** จะถูกปฏิเสธ (`INVALID`) ก่อนเขียน — Fail Closed ตาม Contract ที่ห้ามแยก Record
4. **Production MT5 Adapter ยังไม่ถูกเรียกใน Production Path** — WP-05C ไม่เชื่อม `OnTradeTransaction`/EA (เป็น WP-05D) จึงยังไม่มี Runtime Evidence ของ Adapter นี้

### 7.5 Git hygiene

- `git diff --check` → ผ่าน (ไม่มี whitespace error)
- `git diff --stat` → 6 ไฟล์ที่แก้ไข เป็นการเพิ่มอย่างเดียว 1186 บรรทัด ไม่มี deletion
- ไม่มี Commit/Push
- ไม่มีไฟล์.compile.log ค้างใน Repository

---

## 8. สิ่งที่ยังไม่ได้ทำ (ตาม Scope)

- ไม่เชื่อม `OnTradeTransaction` หรือ Production EA (WP-05D)
- Implementer ไม่ได้รัน MT5 Tests หรือ Regression Suite (เป็นสิทธิ์ของ Product Owner — ดูผลใน §12)
- ไม่ได้ Update `PROJECT_STATUS.md` / Grid Docs — รอ CTO Code Review ก่อนปิด WP

## 9. คำถาม / ประเด็นที่ต้องให้ CTO ตัดสิน

ไม่มีข้อขัดแย้งกับ Contract ที่พบระหว่าง Implement ทุกจุดที่ Contract เปิดให้ Implementer ปรับได้ (ชื่อไฟล์, Encoding ของ Batch Payload) ถูกใช้ตามข้อเสนอใน SPEC โดยไม่เปลี่ยน Responsibility หรือ API Boundary

---

## 10. Remediation หลัง Product Owner รัน Test รอบแรก (2026-11-27)

Product Owner รันเฉพาะ Test ใหม่ 2 ไฟล์ พบ 2 Defect ที่เป็น Implementation Bug (ไม่ใช่ Fixture Error) จึงแก้เฉพาะจุดและ Compile ซ้ำ

### 10.1 `test_grid_open_position_snapshot` — `reordered set with a foreign record is COMPLETE` (expected=2, actual=1)

- **อาการ:** Owned Set ที่ Stable แต่มี Foreign Position เพิ่มเข้ามาใน Scan ที่สองถูกปฏิเสธเป็น `UNSTABLE`
- **สาเหตุ:** `Acquire()` เทียบ `first_total != second_total` (Account Total ดิบ) ก่อนสร้าง Owned Set ทำให้ Foreign Position ที่ไม่เกี่ยวกับ Grid นี้ทำให้ทั้ง Snapshot ใช้ไม่ได้
- **การแก้:** ลบ Gate ที่เทียบ Account Total ดิบออก แล้วตัดสินความเสถียรจาก `SetsMatch(first_owned, second_owned)` ตาม SPEC §8.2 ที่ระบุให้เปรียบเทียบ **Owned Position Set** แบบไม่ขึ้นกับลำดับ Enumeration
- **รักษา Contract เดิมไว้:** ยังตรวจ `TotalPositions()` ซ้ำท้ายทุก Scan (Total เปลี่ยนระหว่าง Scan → `INVALID`) และ Empty Owned Set ยังยอมรับเฉพาะเมื่อทั้งสอง Scan รายงาน Total = 0 ตาม SPEC §8.2 ข้อสุดท้าย

### 10.2 `test_grid_open_position_reconciliation` — ทุก Case คืน `INVALID` (2) และ Crash ที่บรรทัด 689

- **อาการ:** `Run()` คืน `INVALID` ทุก Case, ไม่มี Journal record, แล้ว Assertion ถัดไปที่อ่าน `journal.records[0]` เกิด `array out of range`
- **สาเหตุ:** `Run()` เรียก `Consume()` (ซึ่งตั้ง `snapshot.consumed = true`) แล้วส่ง Envelope เดียวกันเข้า `BuildBatch()` ซึ่ง Guard ปฏิเสธ Snapshot ที่ `consumed` แล้ว → ทุก Reconciliation ตายที่ Policy
- **การแก้:** เอา `snapshot.consumed` ออกจาก Guard ของ `BuildBatch()` พร้อม Comment ระบุว่า Single-use/Latest-generation ถูกบังคับโดย `Consume()` ก่อนถึง Policy แล้ว ส่วน Policy ยังตรวจ Status, Symbol, Magic และ `base_sequence == reducer.LastSequence()` ซึ่งเป็นสิ่งที่ทำให้ Observation เก่าใช้ไม่ได้
- **ไม่เปลี่ยนพฤติกรรมที่ Contract กำหนด:** `Consume()` ยังปฏิเสธ Token ที่ใช้แล้ว/เก่ากว่า/Base Sequence ไม่ตรง (Test C-11, C-15, C-17 ยังครอบคลุม) และ Stale Snapshot ยังถูกปฏิเสธด้วย Base Sequence

### 10.3 Compile หลังแก้

Affected consumers ทั้ง 7 ไฟล์ Compile ผ่าน `Result: 0 errors, 0 warnings` ทั้งหมด (Snapshot, Reconciliation, Entry Mapping Reducer, Entry Mapping Snapshot, Level Engine, Level Runtime Coordinator, Runtime Restoration)

### 10.4 สถานะ

- การแก้นี้ยัง **ไม่ผ่านการรัน MT5 Test จริง** — เป็น Compile Evidence และการวิเคราะห์ตาม Contract เท่านั้น
- ต้องรอ Product Owner รัน Test ซ้ำทั้ง 2 ไฟล์ก่อนสรุปผล

---

## 11. Remediation รอบที่ 2 หลัง Product Owner รัน Test ซ้ำ (2026-11-27)

ผลรันจริงรอบที่ 2: `test_grid_open_position_snapshot` **PASS ทั้งไฟล์** ส่วน `test_grid_open_position_reconciliation` เหลือ **2 tests / 6 assertions FAIL** โดยทั้งสอง Defect อยู่ใน **Test Fixture ของ WP-05C เอง** ไม่ใช่ Source Bug และไม่ต้องแก้ Source

### 11.1 `C-10 multiple missing Mappings share one atomic Journal record` — `second Level READY` (actual=3)

- **อาการ:** Level 5 คืน `TGK_GRID_LEVEL_WAIT_ACTIVATION` (3) แทน `READY` (0) หลัง Full Close ทั้งสอง Mapping
- **สาเหตุ:** Fixture Geometry คือ Anchor 4000 / Step 5 / Bounds 3980–4020 / 8 Levels → Level 5 = **4010** ส่วน Quote ของ Case นี้คือ Bid 3999 / Ask 4000 สำหรับ BUY Rule `IsWrongSideAfterEntryMove()` คือ `level_price >= current_price` (Ask) ดังนั้น 4010 ≥ 4000 → Wrong Side → `WAIT_ACTIVATION` ซึ่งเป็นพฤติกรรมที่ถูกต้องตาม WP-05A.2 ที่ `TryGetPostCloseState()` เรียกใช้ (ไม่ Duplicate Rule)
- **การแก้:** แก้ **Expectation ของ Test** ให้ตรง Rule (Level 0 = 3980 → `READY`, Level 5 = 4010 → `WAIT_ACTIVATION`) พร้อม Comment ระบุเหตุผลด้าน Geometry ไม่แตะ Source
- **ยืนยันว่า Batch ยัง Atomic:** ยังคง Assert ว่า 1 Journal record, 2 close events, Mapping หมด, Sequence +1 ครั้งเดียว ซึ่งเป็นเจตนาหลักของ Case นี้

### 11.2 `C-10 SELL direction uses Bid for the post-close state` — `build SELL fixture` (false) + 3 Assertions ต่อเนื่อง

- **อาการ:** `BuildFixture(..., "SELL", 2)` คืน `false`, `Run()` คืน `INVALID` (2) แทน `APPLIED` (1), และ Level 0 ไม่เปลี่ยน State
- **สาเหตุ:** Helper `AddMappedPosition()` ของ Test Fixture **Hard-code `BUY`** ไว้ใน `ENTRY_INTENT` Payload (`v1|<req>|<symbol>|<magic>|BUY|LEVEL|...`) ทุกกรณี ทำให้ Fixture ที่ประกาศ Mode `SELL` ใน `RESET_COMMITTED` มี Intent ที่ขัดกับ Context → `ApplyEntryIntent()` ปฏิเสธ (`fields[4] != m_mode`) → `Replay()` ล้มเหลว → Reducer เป็น `RECOVERY_ERROR` → `MatchesContext()` ปฏิเสธทุก Reconciliation
- **การแก้:** เพิ่ม Parameter `mode` ให้ `AddMappedPosition()` และใช้ค่านั้นใน `ENTRY_INTENT` Payload (Field count ยังเป็น 10 ตาม Contract ของ Reducer) พร้อมส่ง `mode` จาก `BuildCommittedRecords()` ทั้งสอง Call site
- **ไม่แตะ Source:** `MatchesContext()`, `ApplyEntryIntent()` และ Mode Validation ของ Reducer ถูกต้องอยู่แล้ว — Defect อยู่ที่ Fixture ที่สร้าง Journal ไม่ตรง Mode ของตัวเอง

### 11.3 Compile หลังแก้

`Experts/TGK/Tests/Grids/test_grid_open_position_reconciliation.mq5` Compile ผ่าน `Result: 0 errors, 0 warnings` (Source ทั้งหมดไม่มีการเปลี่ยนแปลงในรอบนี้ จึงไม่ต้อง Compile Consumer อื่นซ้ำ)

### 11.4 สถานะ

- ยัง **ไม่ผ่านการรัน MT5 Test จริง** — เป็น Compile Evidence และการวิเคราะห์ตาม Rule/Geometry เท่านั้น
- ต้องรอ Product Owner รัน `test_grid_open_position_reconciliation.mq5` ซ้ำ แล้วต่อด้วย `test_grid_entry_mapping_reducer.mq5`, `test_grid_entry_mapping_snapshot.mq5`, `test_grid_level_runtime_coordinator.mq5`, `test_grid_runtime_restoration.mq5` และ Latest no-trade Grid Regression Suite
- ยังไม่มี Runtime evidence ของ Hydration + Gate Release Path และของ MT5 Production Adapter

---

## 12. User Verification (Product Owner) — 2026-11-27

Product Owner รัน MT5 Test ครบทุกไฟล์ที่มีของ WP-05C แล้วรายงานว่า **ผ่านทั้งหมด (PASS)** จึงปิดสถานะ "รอ Test" ที่ค้างอยู่ใน §10.4 และ §11.4

### 12.1 ผล Test

- **ผู้รัน:** Product Owner (Implementer ไม่ได้รัน MT5 Test Suite เอง ตาม `AGENTS.md`)
- **ผล:** PASS ทุกไฟล์ — ไม่มี Defect ค้างจาก Remediation รอบที่ 1 (§10) และรอบที่ 2 (§11)
- **ขอบเขตที่ยืนยันแล้ว:** Snapshot Acquisition (Stable Two-scan, Consumed-token), Reconciliation Diff/Policy, Atomic Batch Apply, Coordinator Hydration + Gate Release, Entry Mapping Reducer/Snapshot, Level Engine, Runtime Restoration
- **สรุปเชิงสาเหตุ:** Remediation ทั้ง 2 รอบแก้ถูกจุด — รอบที่ 1 เป็น Implementation Bug จริง (`Acquire()` Account-total Gate, `BuildBatch()` Consumed Guard) และรอบที่ 2 เป็น Test Fixture Bug (`AddMappedPosition()` hard-code `BUY`, Expectation ของ Level 5 ไม่ตรง Geometry) โดยไม่มีการเปลี่ยน Source ในรอบที่ 2

### 12.2 Compile Gate (Implementer รันเอง หลังปิด Remediation รอบที่ 2)

Compile ทุก Affected MQL5 Consumer ของ `.mqh` ที่ถูกแก้/เพิ่ม — **ทั้ง 9 โปรแกรม `Result: 0 errors, 0 warnings`**

| โปรแกรม | เหตุผลที่อยู่ในชุด Compile | Result |
|---|---|---|
| `Experts/TGK/Tests/Grids/test_grid_open_position_snapshot.mq5` | Test ใหม่ (Snapshot) | 0 errors, 0 warnings |
| `Experts/TGK/Tests/Grids/test_grid_open_position_reconciliation.mq5` | Test ใหม่ (Reconciliation) | 0 errors, 0 warnings |
| `Experts/TGK/Tests/Grids/test_grid_entry_mapping_reducer.mq5` | Consumer `GridEntryMappingReducer.mqh` | 0 errors, 0 warnings |
| `Experts/TGK/Tests/Grids/test_grid_entry_mapping_snapshot.mq5` | Consumer `GridEntryMappingSnapshotStorage.mqh` → Reducer | 0 errors, 0 warnings |
| `Experts/TGK/Tests/Grids/test_grid_level_runtime_coordinator.mq5` | Consumer `GridLevelRuntimeCoordinator.mqh` | 0 errors, 0 warnings |
| `Experts/TGK/Tests/Grids/test_grid_runtime_restoration.mq5` | Consumer Coordinator + Mapping Storage | 0 errors, 0 warnings |
| `Experts/TGK/Tests/Grids/test_grid_level_engine.mq5` | Consumer `GridLevelEngine.mqh` | 0 errors, 0 warnings |
| `Experts/TGK/Tests/Grids/test_grid_entry_execution.mq5` | Consumer `GridEntryExecutionAdapter.mqh` → Reducer + Coordinator | 0 errors, 0 warnings |
| `Experts/TGK/Tests/Grids/test_grid_entry_execution_resolver.mq5` | Consumer `GridEntryExecutionResolver.mqh` → Reducer + Coordinator | 0 errors, 0 warnings |

- คำสั่ง: `MetaEditor64.exe /compile:<program>.mq5 /inc:<repo root> /log:<temp>.log` (ตาม `AGENTS.md`)
- Log เป็นไฟล์ชั่วคราวที่ลบหลังอ่านผล — ไม่มี `compile_*.log` ค้างใน Repository
- Compile Evidence นี้เป็นคนละส่วนกับ MT5 Test Evidence ใน §12.1

### 12.3 Known Limitations ที่ยังคงอยู่

1. **ไม่มี Runtime evidence ของ Hydration + Gate Release Path ใน EA จริง** — Test เป็น Unit-level บน Test EA เท่านั้น
2. **MT5 Production Open-position Adapter ยังไม่ถูกเรียกจาก Production Path** — WP-05C ไม่เชื่อม `OnTradeTransaction`/EA (เป็น WP-05D) จึงยังไม่มี Live evidence
3. **ไม่มี Commit/Push** — Working tree ยังคง staged/untracked ตามเดิม

### 12.4 พร้อมสำหรับ CTO Code Review

- Diff ที่ต้อง Review: Source 5 ไฟล์ (ใหม่ 2 + แก้ 3), Test 5 ไฟล์, Report 1 ไฟล์
- ไม่มีการเปลี่ยน Product Behavior หรือ Public Contract นอกเหนือจากที่ระบุใน §10–§11
- ยังไม่มีการ Update `PROJECT_STATUS.md` / Grid Docs / Trello — รอผล Code Review

---

## 13. Implementer Self-Review (ก่อนส่ง CTO Review) — 2026-11-27

ทบทวน Source Diff ทั้งหมด (ทั้งไฟล์ใหม่ 2 และ Diff ของไฟล์ที่แก้ 3) + Test Diff 5 ไฟล์ เทียบ `SPEC.md` (โดยเฉพาะ §8 Technical Contract Addendum), `TEST_PLAN.md` (§5.2, §5.3) และ `references/review-lessons.md` ของ Skill

### 13.1 Acceptance Criteria → หลักฐาน

| Acceptance Criteria (SPEC §6) | หลักฐานใน Diff / Test |
|---|---|
| Failed/Incomplete/Unstable Snapshot ไม่มี Durable Mutation | `CaptureScan()` fail-closed ทุกขั้น; `BuildBatch()` ตรวจ Status ก่อนสร้าง Event; Test C-02 (ครบทุก getter 1–5), C-03, C-13 |
| Foreign/Manual/Other Instance ไม่ถูก Adopt | `BuildOwnedSet()` กรองหลัง Full Scan เท่านั้น; Test C-04 (5 ตำแหน่ง เหลือ Owned 1) |
| Identifier เป็น Mapping Key; Ticket Refresh ไม่สร้าง Lifecycle ใหม่ | `FindLiveIndex()` ใช้ Identifier; Test C-05, C-06 |
| Partial Close คง ACTIVE | `POSITION_METADATA` อัปเดต Volume/Ticket เท่านั้น; Test C-07 |
| Full Close เฉพาะเมื่อหายจาก Complete/Stable Snapshot | `AppendCloseEvent()` เรียกจาก Policy ที่ผ่าน Status Guard; Test C-10 (4 เคส), C-13 |
| Full Close Reason-free + Current Quote (BUY=Ask/SELL=Bid) | `coordinator.TryGetPostCloseState()` → `engine.TryGetPostCloseState()` (Rule เดียวกับ WP-05A.2); Test C-10 BUY/SELL |
| Orphan/Conflict Fail Closed | `IsUnresolvedEntryEvidence()` + `TryGetDealAssociationProjection()`; Test C-09, C-12 (2 เคส), C-16 |
| Duplicate/Reconcile Idempotent | `Consume()` single-use + generation + Base Sequence; `NO_CHANGE` ไม่ Append; Test C-11, C-15, C-17 |
| Append/Apply Failure ไม่เกิด Partial Transition | 1 record + `ApplyCommittedRecord()` + Backup/Restore ทั้ง Batch; Test C-14 |
| Tests ใช้ Fake Port ไม่มี Trade Request | ไม่มี `CTrade`/`OrderSend`/`PositionClose` ใน Diff ทั้งหมด (ตรวจด้วย grep) |

Test Case ครบ C-01…C-17 ตาม `TEST_PLAN.md` (C-02 วนทดสอบ getter ทั้ง 5 Field, C-10 มี 4 เคสครอบ BUY/SELL/Multi-mapping/Quote side)

### 13.2 Findings ที่พบเอง (ไม่มีการแก้ Source — ต้องให้ CTO ตัดสิน)

ทั้ง 6 ข้อเป็น **ข้อสังเกต/ความเสี่ยงที่ disclose** ไม่ใช่ Defect ที่ขัด Acceptance Criteria และไม่กระทบผล Test ที่ PASS แล้ว จึง**ไม่แก้ Source** ในรอบนี้เพื่อไม่ให้ Product Owner ต้องรัน Test ซ้ำโดยไม่จำเป็น

| ID | ระดับ | ตำแหน่ง | ประเด็น | ข้อเสนอ |
|---|---|---|---|---|
| SR-01 | ต่ำ (Disclose) | `GridOpenPositionReconciliation.mqh` `BuildBatch()` | Policy ไม่ตรวจ `snapshot.consumed` อีกต่อไป (Remediation §10.2) — ความสดของ Token จึงขึ้นกับ `Run()` ที่เรียก `Consume()` ก่อนเสมอ และ `base_sequence == LastSequence()` | ยอมรับได้เพราะ `Run()` เป็น Caller เดียวใน Scope นี้; WP-05D ต้องไม่เรียก `BuildBatch()` ตรง ๆ |
| SR-02 | กลาง (Liveness) | `Run()` หลัง `ApplyCommittedRecord()` สำเร็จ | ถ้า Hydration หรือ Gate Release ล้มเหลว `m_recovery_required` **ไม่ถูกตั้ง** และ Batch ถูก Apply ไปแล้ว → `Run()` รอบถัดไปได้ `NO_CHANGE` ซึ่ง return ก่อนถึง Hydration/Release → Gate ค้างปิดจนกว่าจะ Restart (Fail Closed แต่ไม่มี In-process Retry) | ยืนยันว่าเป็นไปตาม SPEC §8.5 ("Recovery ต้องเริ่มจาก Reducer/Journal"); ให้ CTO ตัดสินว่าต้องมี Retry Path ใน WP-05D หรือไม่ |
| SR-03 | กลาง (Operational) | `Acquire()` `empty_with_nonzero_total` | Owned Set ว่างแต่ Account Total ≠ 0 (มี Position ของ EA อื่น) → `UNSTABLE` ตลอด → Reconciliation ไม่มีวันสำเร็จและ Gate ไม่ถูกปล่อย | เป็นไปตาม SPEC §8.2 ข้อสุดท้ายตรงตัว; ต้องแจ้ง CTO ว่าพฤติกรรมนี้มีนัยสำคัญเมื่อรันร่วม EA อื่นบนบัญชีเดียวกัน |
| SR-04 | ต่ำ (Future Risk) | `IsUnresolvedEntryEvidence()` | ตรวจแต่ละ Position เทียบ Unresolved Request แยกกัน จึงมีทางที่ 2 Position (Volume 0.2 + 0.2) ผ่านได้เมื่อ Associated Volume = 0.2 | ไม่มีผลด้านความปลอดภัยวันนี้เพราะ Evidence ไม่ Activate Target; ต้องแก้ก่อน WP-05D เริ่ม Derive State จาก Evidence |
| SR-05 | ต่ำ | `GridEntryMappingReducer.mqh` `ApplyReconciliationBatch()` | ค่า return ของ `RestoreState()` ในสาขา `!valid` ไม่ถูกตรวจ — ถ้า Copy ระหว่าง Restore ล้มเหลว State อาจค้างบางส่วนขณะคืน `false` (โอกาสต่ำมากเพราะ Array ถูกจัดขนาดไว้แล้ว) | ควรตรวจ return และตั้ง `m_failed`; เสนอเป็น Finding ของ CTO ถ้าต้องการให้แก้ |
| SR-06 | ต่ำ (Doc) | `AppendEvent()` + `TGK_GRID_MAPPING_MAX_RECONCILIATION_EVENTS` | Batch ที่มี Event เกิน Cap (= `TGK_GRID_MAPPING_MAX_POSITIONS`) ถูกปฏิเสธเป็น `INVALID` (Fail Closed) แต่ §7.4 เอกสารไว้เฉพาะ Record Bytes | เพิ่มหมายเหตุใน §7.4 หรือเอกสาร Phase เมื่อ CTO อนุมัติ |

### 13.3 Checklist ที่ผ่านแล้ว

- Full Diff อ่านครบ (Source + Test) ไม่ได้ดูเฉพาะ Hunk ที่แก้
- `git diff --check` ผ่าน; Working tree มีเฉพาะไฟล์ใน Scope (12 รายการ) ไม่มีไฟล์นอก Scope
- ไม่มี `CTrade` / `OrderSend` / `PositionClose` / `OnTradeTransaction` / Closing Deal History ใน Module ใหม่
- `GridPositionReconciler.mqh` และ Reset/Close-confirmation semantics ไม่ถูกแก้
- Compile Gate ครบ 9 โปรแกรม `0 errors, 0 warnings` (§12.2) — แยกจาก Test Evidence ชัดเจน
- ไม่มี Commit/Push; ไม่ได้รัน MT5 Test Suite เอง

### 13.4 สรุป Self-Review

- **ผล:** ไม่พบ Defect ที่ขัด Acceptance Criteria หรือ SPEC §8 — ไม่มีการแก้ Source เพิ่มหลัง Test PASS
- **สิ่งที่ต้องให้ CTO ตัดสิน:** SR-01…SR-06 (โดยเฉพาะ SR-02 และ SR-03 ที่มีนัยต่อ WP-05D)
- **ข้อจำกัด:** Self-Review นี้เป็นการอ่าน Diff เชิงสถิต ไม่ใช่ Runtime Evidence และไม่ใช่ Code Review แทน CTO

## 14. Remediation ตาม Review Handoff CR-01…CR-06 (2026-11-27)

อ้างอิง: `Docs/EAs/Grid/WorkPackages/WP-05C/REVIEW_HANDOFF.md` (สถานะ `CHANGES_REQUESTED`)

ขอบเขต: แก้เฉพาะ CR-01…CR-06 — **ไม่แตะ Product Behavior, SPEC scope หรือ WP-05D** และไม่เพิ่ม Trade Request / `CTrade` / `OrderSend` / `PositionClose` / Closing Deal History ใน Reconciliation Path

### 14.1 สรุปการแก้ไขแยกตาม CR

| CR | ไฟล์ | การแก้ไข | Acceptance ที่ปิด |
|---|---|---|---|
| CR-01 | `GridOpenPositionSnapshot.mqh` (`CTGKGridMT5OpenPositionSource::ReadSelectedPosition`) | เปลี่ยนมาใช้ Boolean overload ของ `PositionGetInteger` / `PositionGetString` / `PositionGetDouble` ครบทั้ง 5 Required Field (`POSITION_IDENTIFIER`, `POSITION_TICKET`, `POSITION_SYMBOL`, `POSITION_MAGIC`, `POSITION_VOLUME`) และ `return false` ทันทีเมื่อ Getter ใดล้มเหลว — ค่า default เช่น Magic 0 ไม่ถูกนำมาใช้ตัดสินความสำเร็จของการอ่าน | Property Read Failure ทำให้ Scan/Snapshot ล้มเหลว; Magic Getter failure ไม่กลายเป็น Magic 0 / Foreign Position / Empty Owned Set |
| CR-02 | `GridOpenPositionReconciliation.mqh` (`Run()`) | แยก **Durable Phase** (Append + `ApplyCommittedRecord`) ออกจาก **Post-Reconciliation Finalization** (Projection → Hydrate → Release) แล้วให้ทั้ง `APPLIED` และ `NO_CHANGE` ผ่าน Finalization เดียวกัน; `NO_CHANGE` ไม่เรียก `AppendOne` และไม่แตะ Sequence | Stable Snapshot + Mapping ไม่เปลี่ยน → `NO_CHANGE`, ไม่มี Journal record, Sequence เดิม, Gate ถูกปล่อย; Empty owned + Empty mapping ก็ปล่อย Gate; Snapshot ไม่ผ่าน/Projection ไม่ตรง → Gate ค้างปิด |
| CR-03 | `GridOpenPositionSnapshot.mqh` (`Acquire()`) | เพิ่มเงื่อนไข `first_total == second_total` เป็นส่วนหนึ่งของความ Stable ของ Scan pair (ยังอยู่ใน Bounded Retry และ `SetsMatch()` แบบ order-independent + `empty_with_nonzero_total` เดิม) | Account Total ต่างกัน → pair ไม่ผ่านแม้ Owned Set ตรงกัน; Retry ไม่เกิน max attempts; Retry หมด → ไม่มี accepted token / owned snapshot; Total เท่ากันแต่ Owned Set ต่างยังไม่ผ่าน |
| CR-04 | `GridEntryMappingReducer.mqh` (`ApplyReconciliationBatch()`, `RestoreState()`) | ตรวจ return ของ `RestoreState()`; ถ้า Restore ล้มเหลวตั้ง `m_failed = true` + `m_recovery_status = TGK_GRID_MAPPING_STATUS_RECOVERY_ERROR` ด้วยการ assign scalar เท่านั้น (ไม่พึ่ง allocation) → ทุก mutation/readiness API ถูกปฏิเสธจนกว่าจะ Replay Journal ใหม่ | Invalid sub-event กลาง Batch ไม่ทิ้ง partial state; Rollback failure → Fail Closed; ไม่มี compensating record; Journal replay ยังเป็น canonical recovery |
| CR-05 | `GridOpenPositionSnapshot.mqh` (`TakeConsumedToken()`), `GridOpenPositionReconciliation.mqh` (`BuildBatch()` → private, `TryBuildBatch()` → public entry) | `BuildBatch()` ถูกย้ายเป็น **private**; ทางเข้าเดียวคือ `TryBuildBatch()` ซึ่งต้องผ่าน **Acquirer-owned single-use grant** (`TakeConsumedToken()` ตรวจ generation/base sequence/symbol/magic จาก state ของ Acquirer แล้วล้าง grant ทันที) — ไม่เชื่อ `snapshot.consumed` ที่ Caller เขียนได้ | Snapshot ที่ไม่ได้ Acquire/Consume, DTO ที่ Caller สร้างเอง, token ที่ replay, generation เก่า และ Base Sequence เก่า เข้า Diff ไม่ได้; ไม่มี Journal write/Reducer mutation จาก token ที่ไม่ผ่าน |
| CR-06 | `GridOpenPositionReconciliation.mqh` (`Run()`) | ตั้ง `m_recovery_required = true` ใน **ทุก** Post-Commit Failure: (1) `ApplyCommittedRecord` ล้มเหลว (2) `BuildCoordinatorProjection` / `HydrateRuntimeState` ล้มเหลว (3) `ReleaseReconciliationGate` ล้มเหลว; `Run()` รอบถัดไปคืนค่าใหม่ `TGK_GRID_RECONCILIATION_RECOVERY_REQUIRED` และไม่ปล่อย Candidate/Price Processing จาก Runtime ที่ไม่สมบูรณ์ | Hydration/Gate failure หลัง Durable Commit → Recovery Required + Gate ปิด; subsequent `Run()` ถูกปฏิเสธ; Recovery derive จาก Reducer/Journal เท่านั้น; ไม่มี compensating record |

### 14.2 Test Coverage ที่เพิ่ม/ปรับ

**`test_grid_open_position_snapshot.mq5`**

| Test | สิ่งที่พิสูจน์ |
|---|---|
| `C-02 failed required property read rejects the Snapshot` (ปรับ) | Fake Source อ่าน Property ผ่าน Boolean Getter แยกทีละ Field (1…5) — Getter ล้มเหลว → `Acquire` false, Snapshot `INVALID`, `OwnedCount()==0`, `Consume()` ปฏิเสธ |
| `CR-01 a failed Magic Getter is never read as Magic 0` (ใหม่) | Magic Getter failure ไม่ถูกตีความเป็น Magic 0; ตรงข้ามกับ Position ที่ **อ่าน Magic 0 สำเร็จ** ซึ่งยังถูกคัดเป็น Foreign Position และ Scan ยังสำเร็จ |
| `CR-03 an Account Total change between scans is UNSTABLE` (ใหม่) | Foreign Position เข้าเฉพาะ Scan แรก (Owned Set ตรงกัน, Total 3 vs 2) → `UNSTABLE`, ไม่มี Owned Position ค้าง, ไม่มี token |
| `CR-03 a transient Account Total change recovers on retry` (ใหม่) | Attempt 0 ไม่ Stable → Attempt 1 Stable → `COMPLETE`, Total 2/2, `AttemptCount()==2` |
| `CR-03 an Account Total mismatch on every attempt fails closed` (ใหม่) | `UNSTABLE` ทุก Attempt, `AttemptCount()==TGK_GRID_OPEN_POSITION_MAX_ATTEMPTS`, Owned ว่าง, ไม่มี token |
| `C-03 Owned set comparison ignores enumeration order only` (ปรับ) | ให้ทั้งสอง Scan เห็น Membership เดียวกัน (Foreign record อยู่ทั้งคู่) เพื่อไม่ให้ Total mismatch มาบดบัง invariant ที่ Test นี้ต้องการพิสูจน์ |
| `Consume rejects used, superseded and stale tokens` (ปรับ) | เพิ่ม `TakeConsumedToken()` — grant ใช้ได้ครั้งเดียว |

**`test_grid_open_position_reconciliation.mq5`**

| Test | สิ่งที่พิสูจน์ |
|---|---|
| `C-05`, `C-08`, `C-16`, `Foreign Symbol and Magic are never reconciled` (ปรับ) | `NO_CHANGE` ที่ผ่าน Validation ครบ → Gate ถูกปล่อย, Sequence เดิม, ไม่มี Journal record, Runtime Hydrate Mapping ครบ (Identifier/Ticket/Volume), ไม่มี Anchor Activation ค้าง |
| `C-11`, `C-15` (ปรับ) | เปลี่ยนจาก `BuildBatch()` (ตอนนี้ private) เป็น `TryBuildBatch()` ผ่าน Acquirer จริง |
| `CR-02 an empty Snapshot and empty Mapping release the Gate` (ใหม่) | Empty valid owned snapshot + empty canonical mapping → `NO_CHANGE`, ไม่มี write, Sequence เดิม, Gate ถูกปล่อย, ไม่ต้อง Recovery |
| `CR-05 a forged Snapshot never reaches the Diff` (ใหม่) | DTO ที่ Caller สร้างเอง (รวม `consumed=true`) → `INVALID`, ไม่มี Journal/Sequence/Mapping เปลี่ยน, Gate ค้างปิด |
| `CR-05 an unconsumed Snapshot is refused` (ใหม่) | Acquire แล้วไม่ Consume → `INVALID`, ไม่มี write |
| `CR-05 a consumed Snapshot cannot be replayed` (ใหม่) | Grant ใช้ได้ครั้งเดียว: ครั้งแรก `NO_CHANGE`, ครั้งที่สอง `INVALID`, ไม่มี write |
| `CR-05 a superseded generation is refused` (ใหม่) | Envelope ของ generation เก่าใช้ไม่ได้หลังมี generation ใหม่ |
| `CR-05 a Base Sequence mismatch is refused` (ใหม่) | Reducer advance หลัง Consume → Diff ถูกปฏิเสธ ไม่มี write |
| `CR-06 a Projection failure …` / `a Hydration failure …` / `a Gate release failure … after the durable commit requires recovery` (ใหม่ 3 เคส) | ทุกเคส: error status ตรงตามขั้นที่ล้ม, `IsRecoveryRequired()`, Journal มี 1 record, Sequence 10, Gate ปิด, `Run()` รอบถัดไปได้ `RECOVERY_REQUIRED`, ไม่มี record ที่สอง; Replay Journal ไปยัง Reducer ใหม่ได้ state เดิม (Ticket/Sequence) |

**`test_grid_entry_mapping_reducer.mq5`**

| Test | สิ่งที่พิสูจน์ |
|---|---|
| `CR-04 a rejected Batch rolls back every sub-event` (ใหม่) | Sub-event แรกถูกต้อง (จะเปลี่ยน Volume) + sub-event ที่สองไม่ถูกต้อง → Batch ถูกปฏิเสธ, Volume/Ticket/Level ทั้งสอง/Sequence ไม่เปลี่ยน, Reducer ยัง `NORMAL` |
| `CR-04 a failed rollback fails the Reducer closed` (ใหม่) | Restore failure injection → `RECOVERY_ERROR`, `ApplyCommittedRecord` รอบถัดไปถูกปฏิเสธ, `TryGetPositionMapping` / `MatchesContext` fail closed, Journal replay ไปยัง Reducer ใหม่คืน state เดิม |

### 14.3 Compile Evidence (Developer Compile Gate)

คำสั่ง: `wine MetaEditor64.exe /compile:"<program>" /inc:"Z:\...\BotTradeFramework"` ตาม `AGENTS.md` (ตัดสินจาก `Result:` line)

| Program (affected consumer) | Result |
|---|---|
| `Experts/TGK/Tests/Grids/test_grid_open_position_snapshot.mq5` | 0 errors, 0 warnings |
| `Experts/TGK/Tests/Grids/test_grid_open_position_reconciliation.mq5` | 0 errors, 0 warnings |
| `Experts/TGK/Tests/Grids/test_grid_entry_mapping_reducer.mq5` | 0 errors, 0 warnings |
| `Experts/TGK/Tests/Grids/test_grid_entry_mapping_snapshot.mq5` | 0 errors, 0 warnings |
| `Experts/TGK/Tests/Grids/test_grid_level_runtime_coordinator.mq5` | 0 errors, 0 warnings |
| `Experts/TGK/Tests/Grids/test_grid_runtime_restoration.mq5` | 0 errors, 0 warnings |
| `Experts/TGK/Tests/Grids/test_grid_entry_execution.mq5` | 0 errors, 0 warnings |
| `Experts/TGK/Tests/Grids/test_grid_entry_execution_resolver.mq5` | 0 errors, 0 warnings |
| `Experts/TGK/Tests/Grids/test_grid_entry_execution_pipeline.mq5` | 0 errors, 0 warnings |

Affected set มาจากการไล่ `#include` แบบ transitive จาก Header ที่แก้ (`GridOpenPositionSnapshot.mqh`, `GridOpenPositionReconciliation.mqh`, `GridEntryMappingReducer.mqh`, `GridLevelRuntimeCoordinator.mqh`) — ครบทุก `.mq5` ที่ได้รับผล

### 14.4 Self-Review (Failure Paths / Transaction / Token / Post-Commit)

- **Token bypass (CR-05):** `BuildBatch()` ไม่ใช่ public อีกต่อไป; `TryBuildBatch()` ตรวจ grant จาก state ของ Acquirer ไม่ใช่ field ใน DTO; grant ถูกล้างก่อน Validation จึงกันทั้ง forged / unconsumed / replayed / superseded / stale Base Sequence และจำกัด 1 Batch attempt ต่อ 1 accepted Snapshot
- **Transaction (CR-04):** Batch ยังเป็น all-or-nothing ผ่าน backup/restore; เมื่อ restore ทำไม่ได้ Reducer ถูกปิดด้วย scalar assignment (`m_failed`, `m_recovery_status`) ซึ่งไม่พึ่ง allocation และทุก API ที่อ่าน/mutate ถูกปฏิเสธ; ไม่มีการเขียน compensating record
- **NO_CHANGE (CR-02):** ยังผ่าน freshness / Base Sequence / Identity / Symbol / Magic / Config Epoch / Projection consistency ครบเหมือนเส้นทางที่มี Durable Batch; Durable Phase ถูกข้ามทั้งบล็อก (ไม่มี `ReadNextSequence`/`AppendOne`)
- **Post-commit recovery (CR-06):** ทั้ง 3 จุดหลัง Durable Commit ตั้ง `m_recovery_required`; `Run()` รอบถัดไปคืน `RECOVERY_REQUIRED` โดยไม่ Acquire/เขียน/ปล่อย Gate; ไม่มี Recovery API ใน Process นี้ จึงบังคับ Restart/Replay ตามสถาปัตยกรรมเดิม (ทดสอบด้วย Replay Journal ไปยัง Reducer ใหม่)
- **Regression:** `GridPositionReconciler.mqh`, Reset/Close-confirmation semantics, Legacy journal replay, Identifier-only mapping และ Atomic single-record batch ไม่ถูกแก้
- **ข้อสังเกตที่ปิดจาก §13:** SR-01 ปิดโดย CR-05 (Caller เรียก `BuildBatch()` ตรงไม่ได้แล้ว), SR-02 ปิดโดย CR-02 + CR-06 (NO_CHANGE ปล่อย Gate ได้ และ Post-Commit Failure เป็น Recovery Required), SR-05 ปิดโดย CR-04

### 14.5 Git / Diff Check

- `git diff --check` ผ่าน (ไม่มี whitespace error)
- ไม่มี Commit / Push; staged/unstaged/untracked เดิมถูก Preserve ไว้ทั้งหมด (ไม่ได้ใช้ reset/checkout/restore/clean/stash)
- ไม่มีไฟล์นอก Scope ถูกแก้ (รายการไฟล์ตาม §14.1 + `IMPLEMENTATION_REPORT.md`)

### 14.6 Known Limitations / Follow-up (ไม่รวมในรอบนี้)

- **CR-07 (Aggregate unresolved Entry Evidence Volume)** — ยังไม่แก้ตาม Handoff §5; ต้องทำก่อน WP-05D (ยังคงเป็น SR-04)
- **Design Risk — Empty Owned Set while Foreign Positions exist** — คงพฤติกรรมเดิมตาม SPEC (Total ทั้งสอง Scan ต้องเป็น 0) ไม่ผ่อนเงื่อนไข
- **SR-06** — Batch ที่ Event เกิน Cap ถูกปฏิเสธเป็น `INVALID`; ยังไม่ได้เพิ่มหมายเหตุในเอกสาร §7.4
- **Candidate assertion ใน CR-02** — `CTGKGridLevelRuntimeCoordinator` ไม่มี public accessor สำหรับ `m_candidate_offered`; Test จึงยืนยัน "ไม่มี Candidate จาก Release" ทางอ้อมด้วย `IsReconciliationPending()==false`, `HasPendingAnchorActivation()==false` และ Projection ที่ Hydrate ตรงกับ Reducer (ตัว `ReleaseReconciliationGate()` เองปฏิเสธการปล่อยถ้ามี Candidate ค้างอยู่แล้ว) — ถ้า CTO ต้องการ Assert ตรง ๆ ต้องเพิ่ม Read-only accessor ใน WP ถัดไป
- **Production Adapter** — CR-01 แก้ `CTGKGridMT5OpenPositionSource` แล้ว แต่ Unit Test ครอบได้เฉพาะ Fake Source (Contract เดียวกัน) ยังไม่มี Runtime Evidence ของ MT5 Position API จริง — ต้องยืนยันใน WP-05D
- **MT5 Tests** — Implementer ไม่ได้รัน; Product Owner รันครบทุกไฟล์หลัง Remediation แล้วรายงาน PASS (ดู §15)

### 14.7 สถานะ

- CR-01…CR-06: remediated, compile 0/0 ครบ 9 โปรแกรม, Test เพิ่ม/ปรับตาม Handoff
- Product Owner รัน MT5 Test ครบทุกไฟล์หลัง Remediation แล้วรายงาน PASS — ดู §15
- **ยังไม่ถือว่าผ่าน** จนกว่า CTO Review รอบถัดไปจะ `APPROVED`
- `PROJECT_STATUS.md` / Grid docs / Trello ยังไม่อัปเดต (รอผล Review)

---

## 15. User Verification หลัง Remediation CR-01…CR-06 (Product Owner) — 2026-11-27

Product Owner รัน MT5 Test ครบทุกไฟล์ที่เกี่ยวข้องกับ WP-05C ภายหลัง Remediation รอบ CR-01…CR-06 แล้วรายงานว่า **ผ่านทั้งหมด (PASS)**

### 15.1 ผล Test

- **ผู้รัน:** Product Owner (Implementer ไม่ได้รัน MT5 Test Suite เอง ตาม `AGENTS.md`)
- **ขอบเขต:** Test ทุกไฟล์ของ WP-05C — Snapshot, Reconciliation, Entry Mapping Reducer/Snapshot, Level Runtime Coordinator, Runtime Restoration และ Grid Regression ที่เกี่ยวข้อง
- **ผล:** PASS ทั้งหมด — ไม่มี Failure หรือ Defect ที่ Product Owner รายงานกลับมา
- **สิ่งที่ยืนยันได้บน Runtime จริงของ MT5 Test EA:** Acceptance Criteria ของ CR-01…CR-06 ที่ตรวจได้ด้วย Unit Test — Property Read Failure (CR-01), Scan-pair Account Total mismatch + Bounded Retry (CR-03), `NO_CHANGE` ที่ยังปล่อย Gate (CR-02), Batch Rollback + Fail Closed (CR-04), Single-use Acquirer Grant (CR-05) และ Post-Commit Recovery Required (CR-06)
- **หมายเหตุ:** Implementer บันทึกตามคำรายงานของ Product Owner เท่านั้น ไม่ได้รันหรือเห็น Log เอง จึงไม่ระบุจำนวน Assertion หรือจำนวนเคสต่อไฟล์

### 15.2 สถานะหลัง User Verification

- Developer Compile Gate (§14.3) และ User Verification (§15.1) ครบทั้งสองส่วน — หลักฐานแยกกันตาม `AGENTS.md`
- ไม่มี Finding ใหม่จาก Test ที่ต้องแก้ Source — รอบนี้แก้เฉพาะเอกสารรายงาน ไม่แตะ Source/Test
- ยัง **ไม่ถือว่า WP-05C ปิด** — รอ CTO Code Review รอบถัดไปตัดสิน `APPROVED` / `CHANGES_REQUESTED`
- `PROJECT_STATUS.md` / Grid docs / Trello ยังไม่อัปเดต (รอผล Review ตาม §14.7)
- ไม่มี Commit/Push; staged/unstaged/untracked ยัง Preserve ตามเดิม

### 15.3 ขั้นถัดไป

1. CTO Review Diff จริงเทียบ `REVIEW_HANDOFF.md` CR-01…CR-06 + Acceptance Criteria
2. ถ้า `CHANGES_REQUESTED` → Implementer แก้เฉพาะ Finding, Compile affected consumers 0/0, Product Owner รัน Test ซ้ำ
3. ถ้า `APPROVED` → Documentation Consistency Gate: `PROJECT_STATUS.md`, Grid docs, Trello Card

---

## 16. CTO Remediation CR-08 / CR-09 — 2026-11-27

หลัง CTO Review รอบที่ 2 พบ CR-08 (Diff รับ Position Set จาก Caller โดยตรง) และ CR-09 (Failure Injection ของ Property Getter ยังทดสอบเฉพาะ Magic) Product Owner อนุญาตให้ CTO implement แทน Freebuff เนื่องจากโควตาใกล้หมด

### 16.1 CR-08 — Acquirer-owned Position Set

- เพิ่ม `CTGKGridOpenPositionAcquirer::TakeConsumedSnapshot()` เพื่อส่งมอบ Acquirer-owned Owned Position Set พร้อมตรวจและใช้ Single-use Consumed Grant ใน operation เดียว
- ตัด `TakeConsumedToken()` ที่ไม่ส่งมอบ Position Set ออกจาก Public API; `TryBuildBatch()` ไม่มีพารามิเตอร์ Position Array จาก Caller อีกต่อไป
- Acquisition attempt ใหม่ invalidate Accepted/Consumed Generation และ Owned Set เดิมตั้งแต่ต้น แม้ Acquisition รอบใหม่จะล้มเหลว; hand-off ตรวจ Latest Generation ด้วย
- เพิ่ม Test สำหรับกรณี Acquire รอบใหม่ล้มเหลวหลังมี Snapshot เก่าถูก Consume แล้ว เพื่อยืนยันว่า Token เก่าใช้ต่อไม่ได้
- `CTGKGridOpenPositionReconciler::TryBuildBatch()` ไม่รับ `live_positions[]` จาก Caller อีกต่อไป และสร้าง Trusted Position Set ภายในจาก Acquirer เท่านั้น
- `CTGKGridOpenPositionReconciliation::Run()` เรียก API ใหม่โดยไม่คัดลอก/ส่ง Position Array ผ่าน Caller boundary
- เพิ่ม Test ยืนยันการส่งมอบ Position Set จาก Acquirer และการใช้ Grant ซ้ำไม่ได้ รวมถึง Reconciliation NO_CHANGE ที่อาศัยข้อมูลจาก Acquirer

### 16.2 CR-09 — Property Getter Failure Coverage

- เพิ่ม Failure Injection Test ครบทั้ง `POSITION_IDENTIFIER`, `POSITION_TICKET`, `POSITION_SYMBOL`, `POSITION_MAGIC` และ `POSITION_VOLUME`
- แต่ละกรณียืนยัน Acquire ไม่สำเร็จ, Snapshot เป็น INVALID, ไม่มี Owned Position, Consume ไม่สำเร็จ และไม่มี Trusted Consumed Snapshot ให้ส่งมอบ

### 16.3 Verification Boundary — Final Result

- Product Owner รายงานเมื่อ 2026-11-27 ว่า MetaEditor Compile ผ่าน และรัน Test ผ่านทุกไฟล์ หลัง CTO Remediation CR-08/CR-09
- CTO Final Review ตรวจ CR-08/CR-09 แล้ว APPROVED: Diff ใช้ Acquirer-owned Position Set ผ่าน Single-use hand-off เท่านั้น; ป้องกัน replay/stale generation; Failure Injection ครบ Required Position Properties ทั้ง 5 รายการ
- `git diff --check` ของ Worktree ผ่าน; ตรวจสถานะ Git รอบปิดงานพบไฟล์ WP-05C ทั้ง 12 รายการอยู่ใน Staging Area
- ไม่มี Commit/Push

### 16.4 Formal Closure — 2026-11-27

- Product Owner อนุมัติปิด WP-05C เมื่อ 2026-11-27 หลัง Compile/Test PASS และ CTO Final Review APPROVED
- Trello Card ถูกย้ายไป `Done` และ Marked Complete พร้อมบันทึกผลปิดงาน
- **CR-07 ยังคงเป็น Follow-up แยกต่างหากและเป็น Gate ก่อน WP-05D:** `IsUnresolvedEntryEvidence()` ต้อง aggregate Volume ของ Unmapped Live Position Identifiers ทั้งหมดที่สัมพันธ์กับ Unresolved Entry Request เดียวกัน แล้วตรวจเทียบกับ Requested Volume เพื่อป้องกันการยอมรับ Live Volume รวมที่เกินคำขอ ห้ามถือว่า CR-07 ถูกแก้หรือรวมอยู่ใน WP-05C
- WP-05C ปิดแล้ว; WP-05D ยังห้ามเริ่มจนกว่า CR-07 จะได้รับการแก้ไข/ทดสอบและมีการอนุมัติ scope/implementation ตาม workflow
