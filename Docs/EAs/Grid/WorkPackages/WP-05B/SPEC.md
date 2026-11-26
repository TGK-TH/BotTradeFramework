# WP-05B — Runtime State Restoration

**สถานะ: APPROVED — Product Owner อนุมัติ Design/Scope 2026-11-25**
**Implementation: AUTHORIZED — Product Owner อนุมัติ Implementation 2026-11-26; Implement เสร็จรอบแรกและ Remediation ตาม CTO `CHANGES_REQUESTED` เสร็จแล้วทั้ง 2 รอบ (F-01/F-02/F-03/F-05/F-10 และ F-11/F-12); Product Owner รายงาน Compile/Runtime Test PASS 2026-11-26 ทั้งบน Source หลัง Remediation รอบที่ 1 และ Source หลัง Remediation รอบที่ 2 (รัน Test ครบทุกไฟล์) — ขั้นที่เหลือคือ CTO Formal Code Review**
**Dependencies:** WP-05A Persistence Foundation (รวม WP-05A.3)

## 1. วัตถุประสงค์

กำหนดและ Implement การกู้คืน Canonical Trading State จาก Snapshot + Journal ให้กลับมาเป็น Runtime State ของ Grid Engine/Coordinator อย่าง Deterministic หลัง EA/Terminal Restart โดยไม่สร้าง Persistence Authority หรือ Mapping ชุดที่สอง

## 2. Source Inspection Findings

ปัจจุบันมี:
- `CTGKGridEntryMappingSnapshotStorage::Initialize()/Replay()` สำหรับ Recover Manifest/Generation และคืน Snapshot + Journal
- `CTGKGridEntryMappingReducer::RestoreSnapshot()/Replay()` สำหรับกู้ Canonical State
- Reducer มี Read APIs สำหรับ Anchor State, Level State, Position Count, Position Identifier, Ticket, Volume และ Unresolved Request
- `CTGKGridLevelEngine` มี `SetLevelState()` และ `SetAnchorState()`
- `CTGKGridLevelRuntimeCoordinator` มี Initialize/Entry/Reconcile และ State getters แต่ยังไม่มี Bulk Runtime Restore API
- Reducer Read Model ปัจจุบันยังไม่มี Public Typed Position Mapping View ที่คืน Target Kind/Level Index พร้อม Identifier/Ticket/Volume ในรายการเดียว
- Coordinator Position Record ใช้ Ticket เป็น Operational Handle; Reducer ใช้ Position Identifier เป็น Canonical Identity

ช่องว่างเหล่านี้ต้องได้รับการแก้ด้วย Read-only Projection / Runtime Hydration Contract ที่ชัดเจนก่อน Production Integration

## 3. In Scope

- กำหนด Startup Restore Sequence:
  1. ยืนยัน Instance Identity และ Requested Configuration
  2. Initialize Snapshot Storage และ Recover Committed Generation
  3. Replay Snapshot + Journal เข้า Canonical Reducer
  4. Validate Storage/Reducer Recovery Status, Identity, Mode และ Config Epoch
  5. สร้าง Engine/Coordinator จาก Persisted Grid Configuration
  6. Hydrate Anchor State, Normal Level States, Position Mappings และ unresolved Entry Request
  7. Hydrate สำเร็จแล้วให้ Runtime อยู่ในสถานะ RESTORED_PENDING_RECONCILIATION; ปิด Entry/Candidate gate ไว้จน WP-05C ยืนยัน Complete/Stable Live Position Snapshot และปล่อย Gate อย่างชัดเจน
- เพิ่ม Typed Read-only Reducer Projection สำหรับ Position Mapping ที่จำเป็นต่อ Restore
- เพิ่ม Coordinator/Runtime Hydration API ที่รับ State ซึ่งผ่าน Validation แล้ว โดยไม่ทำ Journal Append หรือเปลี่ยน Canonical Persistence State
- รักษา Position Identifier เป็น Canonical Identity และ Position Ticket เป็น Current Operation Handle
- Fail Closed เมื่อ State ไม่ครบ ซ้ำ ขัดแย้ง หรือไม่ตรง Identity/Configuration
- Test ด้วย Snapshot/Journal Fixtures และ Fake Runtime State เท่านั้น

## 4. Out of Scope

- MT5 Open Positions scan และการเปรียบเทียบ Persisted Mapping กับ Live Positions (WP-05C); WP-05B ไม่สามารถพิสูจน์ได้ว่า Position ที่ Persist ไว้ยังเปิดอยู่ หรือว่ามี Position เปิด/ปิดระหว่าง EA Offline
- Deal History ingestion หรือ Close Reason Classification
- Production `OnTradeTransaction` Integration (WP-05D)
- Entry/Close Order Execution และ Trade Requests
- เปลี่ยน Grid Entry Selection, Level Geometry, Bounds หรือ Trading Behavior

## 5. Proposed Technical Contract

1. Reducer เป็น Canonical State Authority; Runtime Engine/Coordinator เป็น Derived Projection
2. Restore ต้องเป็น All-or-Nothing ในเชิง Runtime Activation: หาก Hydration ส่วนใดไม่ผ่าน ห้ามปล่อย Coordinator ให้ทำงานต่อ
3. Hydration API ต้องไม่เขียน Journal และต้องไม่แก้ Reducer
4. Position Mapping Projection ต้องมีอย่างน้อย: Target Kind, Level Index, Position Identifier, Position Ticket, Remaining Volume, Symbol, Magic Number และ Instance Identity ที่จำเป็นต่อ Validation
5. Runtime Coordinator ต้องรับ Mapping ได้หลายรายการใน Restore เดียว รวม Anchor และ Normal Levels; ห้ามใช้ Initial-Anchor-only registration เป็นวิธี Restore ทั่วไป
6. Unresolved Entry Request ต้องคงสถานะ unresolved; ห้ามสร้าง ACTIVE จาก Request/Deal Association เพียงอย่างเดียว
7. Current Quote ใช้ตั้ง Previous/Current Quote Baseline สำหรับ Runtime หลัง Restore แต่ห้ามให้การ Hydrate เองสร้าง Candidate หรือ Durable State Transition
8. WP-05B ไม่ตัดสินว่าตำแหน่งใดในบัญชีเป็น Position ของ Instance; การพิสูจน์ Live Ownership/Presence อยู่ใน WP-05C
9. หลัง Hydration ห้าม Price Update สร้าง Candidate หรือ Entry Request จนกว่า WP-05C จะยืนยัน Snapshot และเปิด Reconciliation Gate; การ Restore Persisted Mapping เพียงอย่างเดียวไม่ใช่หลักฐานว่า Position ยังเปิดอยู่

## 6. Acceptance Criteria

- [ ] Storage Recovery + Reducer Restore/Replay ให้ Canonical State เดิมอย่าง Deterministic
- [ ] Anchor State และทุก Normal Level State ตรงกับ Reducer
- [ ] Position Mapping ทุกตัวถูก Hydrate ไปยัง Target ที่ถูกต้อง โดยใช้ Identifier เป็น Logical Identity
- [ ] Ticket/Volume metadata ถูก Restore ครบ
- [ ] Unresolved Entry Request ยังคง unresolved และไม่ทำให้ Level ACTIVE
- [ ] Invalid/Missing/Duplicate/Conflicting state ทำให้ Runtime ไม่พร้อมใช้งานและ Fail Closed
- [ ] Valid Hydration จบที่ RESTORED_PENDING_RECONCILIATION; Entry/Candidate gate ยังคงปิดจน WP-05C ยืนยัน Live Snapshot
- [ ] Hydration ไม่ Append Journal และไม่เปลี่ยน Reducer Canonical State
- [ ] Repeated Restore จาก Dataset เดิมให้ Runtime State เหมือนเดิม
- [ ] No-trade tests ไม่มี Trade Request

## 7. Dependencies / Gate

WP-05B ต้องรอ WP-05A.3 ปิดก่อน Implementation เพื่อยืนยัน Anchor persistence path แต่สามารถทำ Design/Planning พร้อม WP-05A.3 ได้

Implementation ต้องได้รับ Product Owner Approval แยกต่างหาก และต้องมี Pre-change no-trade Grid Regression Baseline ใหม่
