# Grid Order Execution — Demo Integration Test

อัปเดตล่าสุด: 2026-11-02

## สถานะ

**Completed — user-reported MetaEditor compile and Demo Integration Test passed on 2026-11-02.** ผู้ใช้ยืนยัน Regression Baseline ทั้ง 10 Tests ผ่านก่อนเริ่ม Phase นี้ และยืนยันการทดสอบ Demo จนถึง FINAL PASS แล้ว

## เป้าหมาย

ทดสอบเส้นทางจริงของ CTGKGridOrderExecutionAdapter บนบัญชี Demo แบบ Hedging ตั้งแต่สร้าง Test Positions, สั่งปิด Position ของ Instance, ตรวจสอบ Foreign Position, จนถึง Cleanup และ Final Verification โดยไม่ใช้ EA หลักของ Grid

## ไฟล์

- Experts/TGK/Tests/Grids/test_grid_order_execution_demo.mq5
  - Test EA แยกจาก EA หลัก
  - ใช้ Grid Identity, Runtime Orchestrator และ Order Execution Adapter ที่มีอยู่
  - ไม่แก้ไข Production Grid EA หรือ Adapter

## Safety Gate

1. EnableDemoTest=false เป็นค่าเริ่มต้น
2. ต้องเปิด Input เป็น true และคลิกปุ่ม START บนกราฟก่อนเริ่มส่งคำสั่ง
3. ปฏิเสธบัญชีที่ไม่ใช่ ACCOUNT_TRADE_MODE_DEMO
4. ต้องเป็น Hedging account
5. ตรวจ Terminal/EA/Account trade permission
6. ตรวจ TestLot กับ Volume Min/Max/Step ของ Symbol
7. สร้าง Foreign Magic Number จาก Test Instance Magic Number และตรวจ collision กับ Position/Order ที่เปิดอยู่ทั่ว Account
8. ใช้ Symbol ของกราฟเท่านั้น
9. แนะนำให้ใช้กราฟใหม่ที่แยกจาก EA อื่น และห้ามเปิด Production Grid EA บนกราฟทดสอบเดียวกัน

## Test Flow

1. Initialize Identity, Runtime และ Adapter โดยเริ่มจากไม่มี Position ของ Test Instance
2. เปิด BUY 2 Positions ด้วย Instance Magic Number เดียวกัน
3. บันทึก Fill Price จริงของ Position แรกเป็น Runtime Anchor
4. เปิด BUY Foreign Position 1 รายการด้วย Foreign Magic Number
5. ตรวจว่ามี Owned Positions 2 รายการ และ Foreign Position 1 รายการตาม Ticket/Magic ที่คาดไว้
6. Request Mode change เพื่อให้ Runtime เข้าสู่ Reset / CLOSE_REQUIRED
7. Adapter ปิดเฉพาะ Position ที่ตรงกับกราฟ Symbol + Instance Magic Number
8. Runtime สแกน Account ใหม่และ Retry ตาม Reconciliation policy จน Owned Position เป็นศูนย์
9. ตรวจ Foreign Position ว่ายังเหลือหนึ่งรายการ พร้อม Symbol, Magic Number และ Ticket เดิม
10. แสดงปุ่ม CLEANUP FOREIGN POSITION ให้ผู้ใช้ตรวจผลก่อน
11. เมื่อผู้ใช้คลิก ปุ่มจะตรวจ Ticket, Symbol, Magic Number และจำนวน Foreign Position ซ้ำก่อนเรียก PositionClose(ticket)
12. Final Verification ต้องพบ Owned = 0 และ Foreign = 0 จึงรายงาน FINAL RESULT: PASS และลบเฉพาะ Test Persistence Snapshot

## Failure Handling

- หาก Scan ไม่สมบูรณ์, Runtime ERROR, Identity ไม่ตรง, Foreign Position เปลี่ยน Ticket/จำนวน หรือ Cleanup ไม่สำเร็จ Test จะหยุดเป็น FAIL
- เมื่อ FAIL จะไม่พยายามปิด Position ที่ไม่ตรงกับข้อมูลทดสอบ และจะพิมพ์จำนวน/Ticket/Magic ของ Test Positions ที่อาจเหลือให้ผู้ใช้ตรวจสอบและปิดเอง
- หาก Test ถูกหยุดกลางทาง อาจมี Position หรือ Snapshot ของ Test ค้างอยู่ ต้องตรวจสอบด้วย Symbol + Magic Number ก่อนลบ EA หรือเริ่มใหม่
- Foreign Cleanup เป็นขั้นตอนเฉพาะใน Test EA ไม่ได้เพิ่มความสามารถ Cleanup เข้า Production Adapter

## Inputs

| Input | Default | ความหมาย |
|---|---:|---|
| EnableDemoTest | false | ต้องเปิดใช้งานก่อนเริ่ม |
| TestLot | 0.01 | Lot ต่อ Position ทดสอบ |
| TestGridStep | 1.0 | Step สำหรับ Runtime fixture |
| TestDeviationPoints | 30 | Deviation สำหรับคำสั่งทดสอบ |

## ขั้นตอนที่ผู้ใช้ต้องทำ

1. Compile Test EA ใน MetaEditor
2. ใช้บัญชี Demo แบบ Hedging และเปิดกราฟ Symbol ที่ต้องการทดสอบบนกราฟใหม่ที่ไม่มี EA อื่น
3. ตรวจ Inputs ให้ TestLot เหมาะกับ Symbol และเปิด EnableDemoTest=true
4. Attach EA; ตรวจว่าแสดงปุ่ม START และไม่มี Safety Gate error
5. คลิก START เพื่อเริ่มส่ง Test Orders
6. ตรวจ Experts Log และ Trade tab ระหว่างทดสอบ
7. เมื่อขึ้น CORE PASS ให้ตรวจ Foreign Position ใน Trade tab ว่า Symbol, Ticket, Magic Number และจำนวนตรงตาม Log
8. เมื่อมั่นใจแล้วคลิก CLEANUP FOREIGN POSITION
9. รอ FINAL RESULT: PASS และตรวจ Trade tab ว่า Test Positions ทั้งหมดเป็นศูนย์
10. หลังจบ ให้ปิด/ถอด Test EA ได้

**ข้อควรระวัง:** แม้เป็น Demo Account การเปิด Position มี Spread, Commission และความเสี่ยงจากความผันผวนของราคา Test EA นี้ส่งคำสั่ง BUY 3 รายการ และปิด Position ที่สร้างไว้สำหรับการทดสอบเท่านั้น

## Validation Status

- ก่อนเริ่ม Phase: ผู้ใช้รายงานว่า Grid Regression Tests ทั้ง 10 ไฟล์ผ่านเมื่อ 2026-11-02
- Source implementation: เพิ่ม Test EA แยกแล้ว; ผู้ใช้รายงานว่า Compile ใน MetaEditor ผ่าน
- Demo execution: ผู้ใช้รายงานว่าเปิด BUY 3 Positions สำเร็จ (Owned 2 + Foreign 1), Adapter ปิด Owned ทั้ง 2 และยืนยันว่า Foreign Position เดิมยังอยู่ จากนั้นกด CLEANUP และปิด Foreign Position ได้สำเร็จ
- Final Log ที่ผู้ใช้รายงาน: `TGK DEMO INTEGRATION: FINAL RESULT: PASS` เมื่อ 2026-11-02 เวลา 22:58:52
- ผลนี้ยืนยันเส้นทาง Live Scan + ticket-specific `CTrade.PositionClose()` + Runtime reconciliation บน Demo Hedging Account สำหรับ Test Scenario นี้ ไม่ใช่การยืนยัน Grid V1 ทั้งระบบ
- Phase เสร็จสมบูรณ์ตามผล Compile/Runtime ที่ผู้ใช้รายงาน; Assistant ไม่ได้รัน MetaEditor/MT5 เอง
