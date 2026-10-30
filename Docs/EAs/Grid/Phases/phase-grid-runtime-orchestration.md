# Grid Runtime Orchestration — Round 1

อัปเดตล่าสุด: 2026-10-30

## เป้าหมาย

ประสาน Grid components ที่มีอยู่ให้ทำงานเป็น Runtime flow สำหรับ Grid Instance หนึ่งตัว โดยยังไม่ส่งคำสั่งเปิดหรือปิด Position จริง

## ส่วนที่เพิ่ม

- `Include/BotTrade/Grid/GridRuntimeOrchestrator.mqh`
  - รับ Instance ID, Symbol และ Magic Number ที่ผ่านการ Initialize จาก `CTGKGridIdentity` แล้ว
  - เริ่มต้น/กู้คืน `CTGKGridLifecycle` โดยใช้จำนวน Position ที่นับใหม่จาก Symbol + Magic Number ที่ตรงกัน
  - มี Live account path สำหรับ Runtime และ Snapshot path สำหรับ deterministic tests
  - ประสาน `CTGKGridPositionReconciler` กับ `CTGKGridLifecycle`
  - แจ้ง `CLOSE_REQUIRED` เมื่อจำเป็นต้องให้ Execution adapter พยายามปิด Position
  - เมื่อ close request ได้รับการยอมรับ จะรอตรวจ Account state ใหม่; หาก Position ยังอยู่หลัง observation รอบถัดไป จะกลับไปแจ้งให้ลองใหม่
  - เมื่อยืนยันว่าไม่มี Position ของ Instance เหลือ จึงเดิน Lifecycle ผ่าน RESET_REBUILD และบันทึกสถานะใหม่
  - Count ที่ผิดพลาดหรือ State ที่ไม่ปลอดภัยจะนำไปสู่ Recovery Error

- `Experts/TGK/Tests/Grids/test_grid_runtime_orchestrator.mq5`
  - ทดสอบ fresh initialization และการบันทึก Fill จริง
  - ทดสอบ reset orchestration, close retry, และการ rebuild หลังยืนยัน Position เป็นศูนย์
  - ทดสอบ restart ระหว่าง pending reset
  - ทดสอบ close failure, Market Closed และกรณีไม่มี Snapshot แต่ยังมี Position
  - ใช้ Snapshot fixture; ไม่มีคำสั่งซื้อขายจริง

## ลำดับการทำงาน

1. EA เรียก `CTGKGridIdentity.Initialize()` และส่ง Instance ID/Magic Number ให้ Orchestrator
2. Orchestrator สแกน Position ใหม่โดยกรอง Symbol + Magic Number
3. Orchestrator Initialize หรือ Restore Lifecycle/Persistence
4. เมื่ออยู่ใน `RESET_CLOSE_OLD` จะรายงานสถานะให้ Execution adapter ทราบว่าต้องปิด Position หรือรอผล
5. Execution adapter เป็นผู้ส่งคำสั่งปิดและรายงานผลผ่าน `RecordCloseAttempt()`
6. Orchestrator สแกน Position ใหม่ทุกครั้งที่ Update
7. เมื่อจำนวน Position ของ Instance เป็นศูนย์ จึง Apply pending configuration และคืนสถานะพร้อมทำงาน

## ขอบเขตและข้อจำกัด

- Orchestrator ไม่ได้สร้าง Identity เอง; ผู้เรียกต้อง Initialize Identity ก่อน
- Orchestrator ไม่ส่งคำสั่งเปิด/ปิด Position และไม่มี dependency กับ `CTrade`
- ยังไม่มี EA adapter ที่เรียก Runtime นี้จาก `OnInit/OnTick/OnTimer`
- ยังไม่มีการจัดการ Order ค้าง (Pending Orders); การนับและ Ownership ในรอบนี้ครอบคลุมเฉพาะ Positions
- การเปลี่ยน Magic Number ไม่ใช่ Runtime configuration ที่เปิดให้ผู้ใช้เปลี่ยน; Magic Number มาจาก Identity ที่คงที่ของ Instance
- การจัดการ Grid levels, Bounds, TP, re-entry และการเปิด Position ยังไม่อยู่ในขอบเขต
- Snapshot test path ตรวจ filtering ด้วย Symbol + Magic แต่ไม่ได้แทนการทดสอบ Live account scan ใน MT5

## การตรวจสอบและผลการทดสอบ

- `git diff --check` และ Static review: PASS จากการตรวจใน Repository
- ผู้ใช้รายงานเมื่อ 2026-10-30 ว่า Compile และรัน `test_grid_runtime_orchestrator.mq5` พร้อม Grid Regression Tests เดิมทั้ง 8 ไฟล์ใน MetaEditor/MT5 แล้วผ่านทั้งหมด รวม 9 ไฟล์
- ผล Compile/Runtime เป็นผลที่ผู้ใช้รายงาน Assistant ไม่ได้รัน MetaEditor/MT5 เอง

### รายการ Test ที่ผู้ใช้ยืนยันว่าผ่าน

1. `test_grid_runtime_orchestrator.mq5`
2. `test_grid_position_reconciler.mq5`
3. `test_grid_lifecycle.mq5`
4. `test_grid_state_machine.mq5`
5. `test_grid_types.mq5`
6. `test_grid_persistence.mq5`
7. `test_grid_identity.mq5`
8. `test_grid_identity_multichart.mq5`
9. `test_grid_restart_persistence.mq5`

**สถานะ: Completed** — Grid Runtime Orchestration Round 1 ผ่านการตรวจสอบตามผล Compile/Runtime ที่ผู้ใช้รายงานเมื่อ 2026-10-30

## ขั้นตอนถัดไป

Phase นี้เสร็จสมบูรณ์แล้ว งาน EA Runtime adapter หรือ Order Execution ต้องแยกเป็น Phase ใหม่ กำหนด Scope และได้รับการยืนยันจากผู้ใช้ก่อนเริ่มพัฒนา
