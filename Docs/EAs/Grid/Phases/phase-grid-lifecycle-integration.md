# Phase: Grid Lifecycle Integration

- สถานะ: Implementation รอบแรกเสร็จ และผู้ใช้รายงานว่า Integration Test กับ Regression Tests ที่เกี่ยวข้องผ่านครบ (2026-10-28)
- เริ่ม Phase: 2026-10-27

## เป้าหมาย

เชื่อม State Machine เข้ากับการบันทึก/กู้คืน Lifecycle ของ Grid Instance โดยยังไม่ส่งคำสั่งซื้อขายจริง

## ขอบเขตที่ทำในรอบแรก

- เพิ่ม `CTGKGridLifecycle` ใน `Include/BotTrade/Grid/GridLifecycle.mqh`
- ให้ผู้เรียก Initialize `CTGKGridIdentity` ก่อน แล้วส่ง Instance ID และ Magic Number ที่ได้มาให้ Lifecycle Coordinator
- โหลด Snapshot จาก `CTGKGridPersistence` และตรวจความสอดคล้องของ Instance ID, Symbol, Magic Number และ Fixed Lot
- บันทึกสถานะหลัง Initial Fill, Configuration Reset และ Reset transitions
- เมื่อ Snapshot หายไปแต่ยังมี Position ที่เป็นของ Instance นั้น ให้เข้า `RECOVERY_ERROR` แทนการเริ่ม Grid ใหม่
- เมื่อ Snapshot มีอยู่แต่ Restore ไม่ผ่าน ให้เข้า `RECOVERY_ERROR` แม้ไม่มี Position เหลืออยู่
- หากพบ Magic Number หรือ Fixed Lot ไม่ตรงกับ Snapshot ให้หยุดใน `RECOVERY_ERROR`
- หากมี Reset ค้างอยู่หลัง Restart ให้รักษา Reset เดิมไว้ และตรวจว่า Mode/Step ที่ผู้ใช้ส่งเข้ามาตรงกับ Configuration ที่รอ Apply
- เพิ่ม `HasSnapshot()` ใน `CTGKGridPersistence` เพื่อแยก Snapshot ที่หายไปจาก Snapshot ที่มีอยู่แต่เสียหาย
- เพิ่ม `Experts/TGK/Tests/Grids/test_grid_lifecycle.mq5` สำหรับ Integration Tests โดยไม่มีคำสั่งซื้อขาย

## ความปลอดภัยและข้อจำกัด

- Lifecycle Coordinator ไม่ Initialize Identity เอง; EA ต้องส่ง Identity ที่ผ่านการ Initialize แล้ว
- ผู้เรียกต้องส่งจำนวน Position ที่ตรวจใหม่และกรองด้วย Symbol + Magic Number ของ Instance นี้เมื่อเรียก `Initialize()` หรือ `AdvanceReset()`
- `RequestConfiguration()` เพียงบันทึก Reset request; EA ที่เชื่อมต่อในอนาคตต้องเป็นผู้ส่งคำสั่งปิด Position แล้วตรวจสถานะบัญชีใหม่
- ยังไม่มีการส่งคำสั่งเปิด/ปิด Position, Market Data, Bounds, Grid Level generation, TP หรือ Re-entry
- Fixed Lot ที่เปลี่ยนจากค่าที่ Persist ไว้จะทำให้เข้า `RECOVERY_ERROR` ในรอบนี้ เพราะยังไม่ได้ออกแบบนโยบายเปลี่ยน Lot ระหว่าง Grid ทำงาน
- ถ้าบันทึก Snapshot ไม่สำเร็จ ระบบจะไม่ถือว่าการเปลี่ยน Lifecycle สำเร็จ

## Test cases

`test_grid_lifecycle.mq5` ครอบคลุม:

1. Instance ใหม่ที่ไม่มี Position เริ่มที่ `WAIT_INITIAL_ENTRY`
2. บันทึก Fill จริงแล้ว Restore Anchor และ State ได้
3. Mode reset คงอยู่หลัง Restart และไม่ Apply จนจำนวน Position ที่ตรวจยืนยันเป็นศูนย์
4. ไม่มี Snapshot แต่มี Position ให้เข้า `RECOVERY_ERROR`
5. Magic Number ไม่ตรงกับ Snapshot ให้เข้า `RECOVERY_ERROR`
6. Snapshot มี Commit Marker แต่ข้อมูล Enum เสียหาย ให้เข้า `RECOVERY_ERROR`

## Regression

ก่อนเริ่ม Phase นี้ ผู้ใช้ยืนยันว่า State Machine Test และ Grid Regression Tests เดิมทั้ง 5 ผ่านเมื่อ 2026-10-27 หลังแก้ Source ใน Phase นี้แล้ว ต้อง Compile/Run Integration Test ใหม่และรัน Regression Tests ที่เกี่ยวข้องซ้ำก่อนปิด Phase

## ผลการทดสอบ

ผู้ใช้รายงานเมื่อ 2026-10-28 ว่า Compile และ Run ผ่านครบทั้ง 7 Test EAs ใน MetaEditor/MT5:

- `test_grid_lifecycle.mq5` — PASS
- `test_grid_state_machine.mq5` — PASS
- `test_grid_types.mq5` — PASS
- `test_grid_persistence.mq5` — PASS
- `test_grid_identity.mq5` — PASS
- `test_grid_identity_multichart.mq5` — PASS
- `test_grid_restart_persistence.mq5` — PASS

ผลนี้เป็นการยืนยันจากผู้ใช้ Assistant ไม่ได้รัน MetaEditor/MT5 เอง

Phase นี้ถือว่าเสร็จแล้ว ยังไม่มีการเชื่อม Order Execution หรือส่งคำสั่งเปิด/ปิด Position จริง
