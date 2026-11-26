# WP-05B — Test Plan

**สถานะ: COMPLETED — Product Owner ปิด WP-05B 2026-11-26; Freebuff Implement และ CTO Remediation ทั้ง 2 รอบเสร็จ, Product Owner รายงาน Run Test PASS บน Source ล่าสุด (รันครบทุกไฟล์), CTO Formal Code Review APPROVED.**

## 1. Test Strategy

ทดสอบ Storage → Reducer → Runtime Hydration โดยใช้ Snapshot/Journal fixtures และ Fake Runtime inputs ไม่เรียก MT5 Account APIs และไม่ส่ง Trade Request

## 2. Test Cases

| ID | Scenario | Expected Result |
|---|---|---|
| B-01 | Restore valid Snapshot + Journal ที่มี Anchor READY | Engine/Coordinator Anchor READY; Runtime อยู่ RESTORED_PENDING_RECONCILIATION และ Entry/Candidate gate ปิด |
| B-02 | Restore Anchor ACTIVE พร้อม Mapping | Anchor ACTIVE และ Mapping ไป Anchor target ถูกต้อง |
| B-03 | Restore Anchor WAIT_ACTIVATION | State คงเดิม; Activation Pending ต้องไม่ถูกสร้างจากการ Hydrate |
| B-04 | Restore Normal Levels หลาย State (READY/ACTIVE/WAIT_ACTIVATION) | ทุก Level ตรงกับ Reducer โดยไม่มี State เริ่มต้นจาก Current Quote มาเขียนทับ |
| B-05 | Restore หลาย Position Mappings | แต่ละ Position Identifier ถูกจับคู่กับ Target/Level/Ticket/Volume ที่ถูกต้อง |
| B-06 | Restore Unresolved Entry Request | Request ยังคง unresolved; ห้ามสร้าง Mapping หรือ ACTIVE |
| B-07 | Reducer/Storage Recovery Error | Runtime ไม่ Activate; Fail Closed |
| B-08 | Identity/Symbol/Magic/Mode/Config Epoch mismatch และ Persisted Geometry | ปฏิเสธ Hydration ทั้งชุด; ไม่มี Partial Runtime State; Anchor ที่ต่างภายใน Engine epsilon ต้อง Hydrate ด้วย Geometry ของ Persisted Configuration (F-11) ไม่ใช่ Geometry ของ Request |
| B-09 | Mapping ซ้ำ Target หรือ Identifier / Target ไม่ถูกต้อง | ปฏิเสธ Restore; ไม่เดา Target จากราคา/Ticket |
| B-10 | Hydration ล้มเหลวระหว่าง Level/Mapping หลายรายการ และ Hydration ครั้งที่สองหลัง Restore สำเร็จ | Runtime ไม่พร้อมใช้งาน; ไม่มีการปล่อย Partial State ให้ Price Update; Hydration ที่ล้มเหลวต้องไม่เปิดเผย Anchor/Level/Position/Request/Instance State ที่ค้างจาก Restore ก่อนหน้า (F-12) |
| B-11 | Restore Dataset เดิมซ้ำ | ได้ Runtime Projection เดิม; ไม่ Append Journal |
| B-12 | Restore หลัง Snapshot Checkpoint + Journal Replay | Runtime สะท้อน State หลัง Replay และ Sequence ถูกต้อง |
| B-13 | Restore Mapping สำเร็จ แต่ WP-05C ยังไม่ Reconcile Live Positions | Runtime คง RESTORED_PENDING_RECONCILIATION; ห้าม Offer Candidate/Entry Request |

## 3. Required Assertions

- Reducer Recovery Status และ Last Sequence
- Engine Anchor/Level State ทุก Index
- Coordinator Anchor/Level State และ Position Collection
- Position Identifier ↔ Target ↔ Ticket ↔ Volume
- Pending Request ID และ unresolved flag
- Runtime restore status and Reconciliation Gate (must remain closed after WP-05B)
- Journal Sequence ไม่เปลี่ยนจาก Hydration

## 4. Regression / Safety

- Compile/Run Test EA ใหม่ของ WP-05B
- รัน Reducer, Snapshot Storage, Coordinator และ Runtime Regression ที่เกี่ยวข้อง
- รัน Latest no-trade Grid Regression suite
- ไม่มี `CTrade`, `OrderSend`, `PositionClose` หรือ Account Position API ใน Unit Tests
- ไม่รวม Demo Trade Test

## 5. Evidence

Freebuff ต้อง Compile ทุก Test EA ที่ include Header ที่แก้ให้ได้ 0 errors / 0 warnings; ผู้ใช้เป็นผู้ Run MetaEditor/MT5 Tests และรายงานผลจริง
