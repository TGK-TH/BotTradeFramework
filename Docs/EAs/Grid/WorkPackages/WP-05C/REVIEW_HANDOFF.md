# WP-05C Review Handoff — CR-01 to CR-06

วันที่: 2026-11-27  
สถานะ: **Request Changes — Implementation Follow-up**  
ผู้รับงาน: Freebuff  
ผู้ตรวจ: ChatGPT (CTO / Technical Lead)

## 1. วัตถุประสงค์

แก้ไข Findings จาก Formal Code Review รอบแรกของ WP-05C Open Positions Reconciliation โดยจำกัด Scope เฉพาะ CR-01 ถึง CR-06 ในเอกสารนี้

Product Scope และ Technical Contract เดิมยังคงเดิม ห้ามเปลี่ยน Product Behavior หรือขยาย Scope เอง หากพบว่าจำเป็นต้องเปลี่ยน Contract ให้หยุดและรายงานเหตุผล/ผลกระทบเพื่อขอคำตัดสินก่อน

เอกสารอ้างอิงหลัก:
- `Docs/EAs/Grid/WorkPackages/WP-05C/IMPLEMENTATION_TASK.md`
- `Docs/EAs/Grid/WorkPackages/WP-05C/SPEC.md`
- `Docs/EAs/Grid/WorkPackages/WP-05C/TEST_PLAN.md`
- `Docs/EAs/Grid/WorkPackages/WP-05C/IMPLEMENTATION_REPORT.md`
- Skill: `tgk-implementation-self-review`

## 2. กฎการทำงาน

1. ใช้ Skill `tgk-implementation-self-review` เป็น Workflow หลัก
2. อ่าน Handoff นี้และเอกสารอ้างอิงทั้งหมดก่อนแก้ไข
3. เรียก Serena `initial_instructions` ก่อนเริ่ม Coding ตามกฎ Repository
4. ตรวจ `git status`, staged diff, unstaged diff และ untracked files ก่อนเริ่ม
5. **Preserve ทุก staged/unstaged/untracked changes** ห้าม reset, checkout, restore, clean, unstage หรือเขียนทับงานที่มีอยู่
6. ห้าม Commit หรือ Push
7. ห้ามเปลี่ยน Product Behavior, SPEC scope หรือ WP-05D behavior โดยไม่ได้รับอนุมัติ
8. ห้ามเพิ่ม CTrade, OrderSend, PositionClose, Trade Request หรือ Closing Deal History ใน WP-05C
9. ห้ามแก้ปัญหาด้วยการลดความเข้มงวดของ Validation หรือเปลี่ยน Failure ให้เป็น Empty Snapshot / NO_CHANGE
10. Implementer ต้อง Compile ทุก affected direct/transitive MQL5 consumer ให้ได้ **0 errors, 0 warnings** ตามวิธีที่ Repository กำหนด
11. Implementer ไม่ต้องรัน MT5 Tests; ส่งผล Compile และ Self-Review ให้ Product Owner ก่อน ผู้ใช้จะเป็นผู้รัน MT5 Tests
12. หากพบ CR เพิ่มเติมนอก CR-01 ถึง CR-06 ให้บันทึกแยกและรายงาน ห้ามขยาย Scope เอง

## 3. Findings และ Acceptance Criteria

### CR-01 — Production Adapter ต้องตรวจ Property Read Failure ทุก Field

**ตำแหน่งอ้างอิง:** `Include/BotTrade/Grid/GridOpenPositionSnapshot.mqh`, class `CTGKGridMT5OpenPositionSource::ReadSelectedPosition()`

ปัญหา:
- Current implementation อ่าน Position properties ด้วย getter ที่คืนค่า value โดยตรง
- ค่า default เช่น Magic = 0 อาจถูกตีความเป็นค่าที่อ่านสำเร็จ ทั้งที่ Property Read ล้มเหลว
- หาก Position ของ Instance ถูกจัดเป็น Foreign Position ผิดพลาด อาจทำให้ Mapping ที่ยังเปิดอยู่ถูกตีความว่า Full Close

งานที่ต้องทำ:
- ใช้ MQL5 Boolean overload ของ `PositionGetInteger`, `PositionGetString`, `PositionGetDouble` ที่มี output parameter สำหรับทุก Required Property
- ตรวจ Boolean return ของทุก Getter ก่อนนำค่ามา Validate หรือเขียนลง Record
- Required fields: `POSITION_IDENTIFIER`, `POSITION_TICKET`, `POSITION_SYMBOL`, `POSITION_MAGIC`, `POSITION_VOLUME`
- หาก Getter ใดล้มเหลว ให้ `ReadSelectedPosition()` คืน false และปฏิเสธ Snapshot ทั้งชุด
- ห้ามใช้ค่า 0, empty string หรือค่าเริ่มต้นอื่นเป็นหลักฐานว่า Property Read สำเร็จ

Acceptance:
- Property read failure ของแต่ละ Required Field ทำให้ Scan/Snapshot ล้มเหลว
- ไม่มีกรณี Property Read Failure ถูกจัดเป็น Foreign Position หรือกลายเป็น Empty Owned Set
- Production Adapter และ Fake Adapter มี Contract สอดคล้องกัน

Tests:
- เพิ่ม/ปรับ Fake Source failure injection ให้ครอบคลุม Required Property ทุกชนิด
- Assert ว่า Acquire คืน false, Snapshot ไม่เป็น COMPLETE และ Owned positions ถูก Clear
- ทดสอบโดยเฉพาะ Magic getter failure ที่ห้ามถูกตีความเป็น Magic 0

### CR-02 — NO_CHANGE ต้องสามารถ Validate, Hydrate และ Release Gate ได้

**ตำแหน่งอ้างอิง:**
- `Include/BotTrade/Grid/GridOpenPositionReconciliation.mqh`, `CTGKGridOpenPositionReconciliation::Run()`
- `Experts/TGK/Tests/Grids/test_grid_open_position_reconciliation.mq5`, Test C-05

ปัญหา:
- Run() คืนทันทีเมื่อ BuildBatch() ได้ `TGK_GRID_RECONCILIATION_NO_CHANGE`
- ทำให้ไม่มี Canonical Projection Hydration และไม่มี Explicit Gate Release
- Runtime หลัง Restart อาจค้าง Reconciliation Gate แม้ Live Snapshot ตรงกับ Durable Mapping อยู่แล้ว

Contract ที่ต้องรักษา:
- NO_CHANGE ต้องไม่ Append Journal และไม่เพิ่ม Reducer Sequence
- แต่ Snapshot ที่ Accepted/Consumed ต้องผ่านการตรวจ freshness, Base Sequence, Identity/Symbol/Magic/Config Epoch และ Projection consistency เช่นเดียวกับเส้นทางที่มี Durable Batch
- ต้องสร้าง Hydration Projection จาก Canonical Reducer เท่านั้น
- ต้อง Hydrate/ตรวจ Projection และ Release Gate ได้โดยไม่มี Journal mutation
- Release ต้องไม่สร้าง Candidate และต้อง Refresh Quote Baseline เพื่อให้ Price Processing เริ่มใน Event ถัดไป

งานที่ต้องทำ:
- แยก Durable Mutation ออกจาก Post-Reconciliation Finalization ให้ชัดเจน
- ทั้ง APPLIED และ NO_CHANGE ต้องเข้าสู่ Projection Validation / Hydration / Gate Release หลังผ่านเงื่อนไขของตน
- กรณี NO_CHANGE ห้ามเรียก AppendOne และห้ามเปลี่ยน Sequence
- ปรับ C-05: ห้าม Assert ว่า Gate ต้องค้างปิดหลัง NO_CHANGE เมื่อ Snapshot และ Projection ผ่านการตรวจครบแล้ว
- เพิ่ม Test สำหรับ NO_CHANGE ที่มี mapped live positions ตรงกัน และกรณีไม่มี Owned Positions โดยใช้ Snapshot ที่ถูกต้องตาม Contract ปัจจุบัน
- เพิ่ม Assert ว่า Gate ถูกปล่อย, Reducer Sequence ไม่เปลี่ยน, Journal ไม่มี record ใหม่ และไม่มี Candidate ถูกปล่อยระหว่าง Release

Acceptance:
- Stable accepted snapshot + unchanged canonical mapping -> NO_CHANGE, no journal append, same sequence, gate released
- Empty valid owned snapshot + empty canonical mapping -> NO_CHANGE, no journal append, same sequence, gate released
- Invalid/stale snapshot หรือ Projection mismatch -> Gate remains closed; no false success
- Candidate generation ไม่เกิดจาก Gate Release เอง

### CR-03 — ตรวจ Account Total ระหว่างสอง Full Scans

**ตำแหน่งอ้างอิง:** `Include/BotTrade/Grid/GridOpenPositionSnapshot.mqh`, `CTGKGridOpenPositionAcquirer::Acquire()`

ปัญหา:
- Current code เปรียบเทียบ Owned Position Set แต่ไม่ได้กำหนดให้ Account Total ของสอง Scans ต้องตรงกัน
- Account membership อาจเปลี่ยนระหว่าง Scans แต่ Snapshot ยังถูกยอมรับได้ หาก Owned Set ไม่เปลี่ยน

งานที่ต้องทำ:
- เปรียบเทียบ `first_total` กับ `second_total` ในแต่ละ Scan pair
- หากจำนวน Account Positions ต่างกัน ให้ถือว่า Pair นั้น Unstable และเข้าสู่ Bounded Retry ตามนโยบายเดิม
- หาก Retry หมด ให้ Acquire ล้มเหลวและ Snapshot ต้องไม่เป็น COMPLETE
- คงการตรวจ Owned Set แบบ order-independent และตรวจ Required Properties ครบทั้งสอง Scans
- Empty Snapshot ยังคงยอมรับได้เฉพาะเมื่อทั้งสอง Full Scans สำเร็จและทั้งสอง Account Total เป็นศูนย์ ตาม Contract ปัจจุบัน

Acceptance:
- Account Total mismatch ทำให้ Scan pair ไม่ผ่าน แม้ Owned Set จะตรงกัน
- Retry ได้ไม่เกิน configured max attempts
- Exhausted retry ไม่สร้าง accepted token หรือ owned snapshot
- Account Total เท่ากันแต่ Owned Set/Relevant Fields ต่างกันยังต้องไม่ผ่าน

Tests:
- เพิ่มกรณี foreign position เข้า/ออกระหว่างสอง Scans ทำให้ Total ต่างกัน
- เพิ่มกรณี Total mismatch ชั่วคราวแล้ว Retry pair ถัดไป Stable จึงสำเร็จ
- เพิ่มกรณี Total mismatch ทุก Attempt แล้ว Acquire ล้มเหลว

### CR-04 — Transaction Rollback ต้อง Fail Closed หาก Restore ล้มเหลว

**ตำแหน่งอ้างอิง:** `Include/BotTrade/Grid/GridEntryMappingReducer.mqh`, reconciliation batch apply / `RestoreState()`

ปัญหา:
- เมื่อ Batch Apply ล้มเหลว Reducer เรียก RestoreState() แต่ไม่ตรวจ Return Value
- RestoreState() อาจล้มเหลวจาก allocation/copy failure ทำให้ In-memory State อาจถูก mutate บางส่วนโดยไม่มี Recovery Error

งานที่ต้องทำ:
- ตรวจผลของ RestoreState() ทุกจุดที่ใช้เป็น rollback path
- หาก Restore ล้มเหลว ต้อง mark Reducer เป็น Recovery Error/Fail Closed ด้วยกลไกที่ไม่พึ่งการ allocation ที่อาจล้มเหลว
- ห้ามรายงาน Batch Apply เป็นเพียง Invalid แล้วให้ Reducer ทำงานต่อในสถานะไม่แน่นอน
- พิจารณา transaction design แบบ copy-validate-then-commit (ทำงานบน temporary state แล้ว swap/commit เมื่อทุก sub-event ผ่าน) หากทำได้โดยไม่ละเมิด MQL5 constraints
- หากใช้ rollback ต่อ ต้องพิสูจน์ว่า rollback failure ทำให้ทุก mutation API ถูกปฏิเสธจนกว่าจะ Recovery จาก Journal
- รักษา Legacy Lifecycle Replay Compatibility และ semantics ของ record เดิม

Acceptance:
- Invalid sub-event กลาง Batch ไม่ทิ้ง partial state
- Rollback/restore failure ทำให้ Reducer เข้า Recovery Error และ mutation/readiness ที่อาจทำให้ Runtime เดินหน้าต้อง Fail Closed
- ไม่มีการเขียน compensating journal record
- Replay จาก Journal ยังคงเป็น canonical recovery path

Tests:
- เพิ่ม failure injection สำหรับ backup/copy/restore หรือ transaction staging allocation failure เท่าที่ Test Architecture รองรับ
- Assert ว่า Batch ไม่ทิ้ง partial Request/Deal/Position/Level mutation
- Assert ว่า Recovery Error ถูกเปิดเมื่อ rollback guarantee ทำไม่ได้
- ตรวจว่า subsequent mutation/reconciliation ถูกปฏิเสธใน Recovery Error

### CR-05 — ป้องกันการเรียก BuildBatch โดยข้าม Snapshot Consume

**ตำแหน่งอ้างอิง:** `Include/BotTrade/Grid/GridOpenPositionReconciliation.mqh`, `CTGKGridOpenPositionReconciliationPolicy::BuildBatch()`

ปัญหา:
- BuildBatch() เป็น Public แต่ไม่ได้ยืนยันว่า Snapshot ถูก Consume โดย Acquirer จริง
- Caller สามารถเรียก Policy โดยตรงและข้าม Single-use / Latest-generation guard ใน Acquirer::Consume()

งานที่ต้องทำ:
- ปรับ API boundary ให้ BuildBatch ไม่สามารถถูกเรียกจากภายนอก Orchestration path โดยไม่ผ่านการ Consume
- เลือกแนวทางที่เหมาะสมกับ MQL5 access model เช่น จำกัด visibility/ownership ของ Policy method หรือให้ Policy ตรวจสอบ token กับ Acquirer-owned state ผ่าน API ที่เชื่อถือได้
- อย่าเชื่อเพียง public `snapshot.consumed` field เพราะ Caller สามารถสร้าง/แก้ DTO เองได้
- รักษาการปฏิเสธ stale generation, already-consumed token และ Base Sequence mismatch

Acceptance:
- Snapshot ที่ไม่ได้ Acquire/Consume ผ่าน Acquirer ตัวจริงไม่สามารถเข้าสู่ Diff/BuildBatch ได้
- Snapshot ที่ถูก Consume แล้วใช้ซ้ำไม่ได้
- Snapshot จาก generation เก่าหรือ Base Sequence เก่าใช้ไม่ได้
- API ปกติใน Run() ยังคง Acquire -> Consume -> Diff -> Persist (ถ้ามี mutation) -> Apply -> Hydrate -> Release

Tests:
- เพิ่ม Negative Test สำหรับ unconsumed/forged DTO, stale generation, replayed token และ sequence mismatch
- ยืนยันว่าไม่มี Journal write หรือ Reducer mutation จากทุก invalid token

### CR-06 — Recovery State ต้องครอบคลุม Hydration และ Gate Release Failure หลัง Durable Commit

**ตำแหน่งอ้างอิง:** `Include/BotTrade/Grid/GridOpenPositionReconciliation.mqh`, `CTGKGridOpenPositionReconciliation::Run()`

ปัญหา:
- m_recovery_required ถูกตั้งเฉพาะเมื่อ ApplyCommittedRecord() ล้มเหลวหลัง Append
- หาก Hydration หรือ ReleaseReconciliationGate() ล้มเหลวหลัง Durable Commit ระบบคืน error แต่ไม่ mark recovery required
- Run() ครั้งถัดไปอาจเดินเข้าสู่ NO_CHANGE และไม่สามารถกู้ Runtime ได้อย่างถูกต้อง

งานที่ต้องทำ:
- กำหนด Post-Commit Failure State ที่ชัดเจน ครอบคลุม:
  1. Append สำเร็จ แต่ ApplyCommittedRecord ล้มเหลว
  2. Durable Apply สำเร็จ แต่ BuildCoordinatorProjection/HydrateRuntimeState ล้มเหลว
  3. Hydration สำเร็จ แต่ ReleaseReconciliationGate ล้มเหลว
- ทุกกรณีหลัง Durable Commit ที่ Runtime ไม่ได้ Release อย่างสมบูรณ์ ต้อง Fail Closed และห้าม Run() รอบใหม่ใช้ Runtime เดิมต่อ
- ใช้ Recovery จาก Reducer/Journal เป็นทางกู้คืนเท่านั้น ห้าม rollback Durable Journal หรือสร้าง compensating state
- หากมี Recovery API ใน Process ให้ใช้เฉพาะเมื่อสามารถ rebuild จาก Canonical Reducer/Journal ได้อย่างพิสูจน์ได้; มิฉะนั้นต้องบังคับ Restart/Recovery Flow ตามสถาปัตยกรรมเดิม
- ตรวจว่าทั้ง APPLIED และ NO_CHANGE ใช้ finalization path ที่ปลอดภัยตาม CR-02

Acceptance:
- Hydration failure หลัง Durable Commit -> Recovery Required + Gate closed
- Gate release failure หลัง Durable Commit -> Recovery Required + Gate closed
- Subsequent Run() ไม่สามารถปล่อย Candidate หรือทำ Price Processing จาก Runtime ที่ไม่สมบูรณ์
- Recovery ต้อง derive จาก Reducer/Journal เท่านั้น
- No compensating journal record

Tests:
- เพิ่ม failure injection สำหรับ projection build, hydration และ gate release
- Assert recovery flag/state, gate remains closed, no subsequent journal append/sequence corruption, no candidate
- เพิ่ม test ว่า Run() subsequent call ถูกปฏิเสธจนกว่าจะ recovery ตาม Contract

## 4. Cross-Cutting Regression Requirements

หลังแก้ CR-01 ถึง CR-06 ต้องรัน Compile สำหรับทุก affected direct/transitive consumer และเพิ่ม/ปรับ Unit Tests ตาม Test Plan อย่างน้อย:

- `test_grid_open_position_snapshot.mq5`
- `test_grid_open_position_reconciliation.mq5`
- `test_grid_entry_mapping_reducer.mq5`
- `test_grid_entry_mapping_snapshot.mq5`
- `test_grid_level_runtime_coordinator.mq5`
- ทุก direct/transitive consumer ที่ได้รับผลจาก Header/API changes

ต้องรักษา:
- No Trade Requests ใน Unit Tests
- No CTrade / OrderSend / PositionClose ใน Reconciliation Path
- Identifier-only mapping
- Atomic single-record batch semantics
- Legacy journal replay compatibility
- Existing Reset / Close-confirmation semantics
- MQL5 test formatting conventions ของ Repository

## 5. Out of Scope / Separate Follow-up

**CR-07 — Aggregate unresolved Entry Evidence Volume** ไม่รวมในรอบแก้ไขนี้ ให้บันทึกเป็น follow-up ก่อนเริ่ม WP-05D:
- Current check validates each Position Identifier volume independently
- Must assess aggregate volume across all live unmapped identifiers associated with the same unresolved Entry Request
- Do not modify in this CR-01..CR-06 pass unless CTO/Product Owner explicitly adds it

**Design Risk — Empty Owned Set while Foreign Positions exist**
- Current SPEC requires empty accepted snapshot only when both complete scans report Account Total = 0
- Keep current behavior unchanged in this pass
- Record the operational consequence for multi-EA/shared-account review before WP-05D
- Do not silently relax this rule

## 6. Required Implementer Delivery

เมื่อเสร็จ ให้ส่ง:
1. รายการไฟล์ที่แก้ไขและเหตุผลแยกตาม CR
2. รายงาน Compile: ทุก affected consumers, 0 errors / 0 warnings
3. รายการ Tests ที่เพิ่ม/แก้ พร้อม Test IDs และสิ่งที่พิสูจน์
4. Self-Review ตาม Skill โดยเฉพาะ failure paths, transaction guarantees, token bypass, post-commit recovery
5. ผล `git diff --check`
6. สถานะ `git status --short` และยืนยันว่าไม่มี Commit/Push
7. ระบุ CR-07 และ Design Risk เป็น follow-up โดยไม่รวม scope

**อย่ารัน MT5 Tests แทน Product Owner** หลังส่งมอบให้หยุดรอ CTO Review และผู้ใช้จะเป็นผู้ Compile/Run Tests ตาม Workflow ของโครงการ

## 7. Completion Gate

งานนี้ยังไม่ถือว่าผ่าน Code Review จนกว่า:
- CR-01 ถึง CR-06 ได้รับการแก้ไขและ CTO Review ผ่าน
- ผู้ใช้ Compile และรัน MT5 Tests ที่เกี่ยวข้องผ่านทั้งหมด
- ไม่มี CRITICAL/MAJOR findings ค้างอยู่
- Product Owner อนุมัติปิด WP-05C แยกต่างหาก
