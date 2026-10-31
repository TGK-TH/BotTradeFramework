# Grid Order Execution Adapter — Round 1

อัปเดตล่าสุด: 2026-10-31

## สถานะ

**Completed — User-reported MetaEditor/MT5 PASS (2026-10-31).** ผู้ใช้ยืนยันว่า Unit Test ใหม่และ Grid Regression Tests ทั้งหมด Compile/Run ผ่าน

## เป้าหมาย

เพิ่มความสามารถในการปิด Position เก่าของ Grid Instance ระหว่าง Lifecycle Reset โดยเชื่อม Grid Runtime Orchestrator กับ CTrade อย่างปลอดภัย

รอบนี้ทำเฉพาะ Close Execution ไม่รวมการเปิด Initial Position หรือ Grid Level

## ข้อตกลงการทำงาน

- Adapter จะทำงานเฉพาะเมื่อ Runtime status เป็น TGK_GRID_RUNTIME_CLOSE_REQUIRED
- Ownership ต้องตรงทั้ง Symbol และ Magic Number ของ Instance
- เมื่อได้รับ CLOSE_REQUIRED Adapter จะสแกน Position ใหม่ก่อน แล้วพยายามปิดทุก Ticket ที่พบใน Batch เดียว
- ปิดด้วย Ticket ไม่ใช้ Symbol-only close เพื่อรองรับ Hedging account
- อ่าน CTrade.ResultRetcode() ทันทีหลังแต่ละคำขอ ไม่ตัดสินจาก bool return เพียงอย่างเดียว
- รวมผลของทุก Ticket แล้วเรียก RecordCloseAttempt() หนึ่งครั้ง
- Accepted หมายถึง Server/Trade API รับคำขอไว้เพื่อรอตรวจสอบ ไม่ใช่หลักฐานว่า Position ปิดแล้ว
- Orchestrator ต้องสแกน Account ใหม่ใน Update รอบถัดไป และ Adapter จะทำงานซ้ำเฉพาะ Ticket ที่ยังเหลืออยู่
- หาก Account scan ผิดพลาด จะไม่ส่งคำสั่งใด ๆ จาก Snapshot ที่อ่านได้ไม่ครบ และรายงาน Failed เพื่อให้ Runtime Retry
- หาก Snapshot ล่าสุดไม่พบ Position ของ Instance แล้ว จะไม่ส่งคำสั่งปิด และให้ Runtime reconcile สถานะสด

## ไฟล์ที่เพิ่ม

- Include/BotTrade/Grid/GridOrderExecutionPolicy.mqh
  - Pure policy สำหรับสร้าง Close Batch จาก Snapshot
  - กรองด้วย exact Symbol + Magic Number
  - ปฏิเสธการสร้าง Batch หาก Runtime ไม่ใช่ CLOSE_REQUIRED หรือ Identity ไม่ถูกต้อง
  - จำแนก Retcode เป็น Accepted, Market Closed หรือ Failed
  - รวมผลลัพธ์ของ Batch โดย Failed มีลำดับความสำคัญเหนือ Market Closed และ Accepted

- Include/BotTrade/Grid/GridOrderExecutionAdapter.mqh
  - Live account scan และส่ง CTrade.PositionClose(ticket)
  - ปิดเฉพาะ Ticket ที่ผ่าน Ownership filter
  - พยายามปิดทุก Ticket ใน Snapshot หนึ่งรอบ
  - รายงานผลรวมกลับไปที่ Runtime เพียงครั้งเดียว
  - ไม่เปิด Position และไม่จัดการ Pending Orders

- Experts/TGK/Tests/Grids/test_grid_order_execution.mq5
  - Compile และทดสอบ Adapter initialization, Runtime identity matching และ CLOSE_REQUIRED gate โดยไม่เรียก Close จริง
  - ไม่มีการส่งคำสั่งซื้อขายจริง

## ลำดับการทำงาน

1. EA/Caller เรียก runtime.UpdateLive() เพื่ออ่านสถานะล่าสุด
2. หากไม่ใช่ CLOSE_REQUIRED จะไม่ส่งคำสั่งปิด
3. เมื่อเป็น CLOSE_REQUIRED เรียก adapter.ExecuteCloseIfRequired(status, runtime, trader)
4. Adapter สแกน Positions ทั้งหมด; หาก scan ไม่สมบูรณ์จะไม่ส่งคำสั่ง
5. สร้าง Batch จาก exact Symbol + Magic Number
6. เรียก PositionClose(ticket) ทีละ Ticket ใน Batch เดียว และอ่าน Retcode หลังแต่ละคำขอ
7. รวมผลลัพธ์และบันทึกผ่าน runtime.RecordCloseAttempt()
8. ในรอบถัดไป Runtime สแกน Account ใหม่; หากยังเหลือ Position จะกลับมา CLOSE_REQUIRED และ Adapter จะปิดเฉพาะ Ticket ที่ยังเหลือ

## Unit Test Coverage

ไฟล์: Experts/TGK/Tests/Grids/test_grid_order_execution.mq5

- Batch มีเฉพาะ Position ที่ตรง Symbol + Magic Number
- ปิดกั้นการสร้าง Batch เมื่อ Runtime ไม่ใช่ CLOSE_REQUIRED
- ปฏิเสธ Symbol ว่างและ Magic Number ที่ไม่ถูกต้อง
- DONE, DONE_PARTIAL และ PLACED ถูกจัดเป็น Accepted เพื่อรอ Reconciliation
- MARKET_CLOSED ถูกจัดเป็นผลลัพธ์ Retryable
- Request ที่ส่งไม่สำเร็จถูกจัดเป็น Failed แม้ Retcode จะดูเหมือนสำเร็จ
- Batch ที่มีผลลัพธ์ผสมต้องไม่ถูกตีความว่า Accepted ทั้งหมด
- Batch ว่างไม่ถือเป็นการปิดสำเร็จ

## ขอบเขตที่ยังไม่รวม

- เปิด Initial BUY/SELL
- เปิด Grid Level เพิ่มเติม
- Grid Level Engine, Bounds, TP และ Re-entry
- Pending Order cancellation/management
- EA Event Handler integration (OnInit/OnTick/OnTimer)
- Demo account integration test ที่ส่งคำสั่งปิด Position จริง ต้องวางแผนและอนุมัติขั้นตอนทดสอบแยกต่างหาก

## การตรวจสอบ

- Regression Baseline ก่อนเริ่ม Phase: ผู้ใช้รายงานว่าทั้ง 9 Grid Tests ผ่านเมื่อ 2026-10-31
- หลัง Source changes: ผู้ใช้ยืนยันว่า Unit Test ใหม่และ Regression Tests ทั้ง 9 ไฟล์ Compile/Run ผ่านเมื่อ 2026-10-31 (10 Tests รวม)
- Source review และ git diff --check: ผ่าน
- Assistant ไม่ได้รัน MetaEditor/MT5; ผล Compile/Runtime เป็นผลที่ผู้ใช้รายงาน

## เกณฑ์ปิด Phase

1. test_grid_order_execution.mq5 Compile และ Run ผ่าน
2. Grid Regression Tests ทั้ง 9 ไฟล์ Compile และ Run ผ่านหลัง Source changes
3. ตรวจสอบ Interface/การเรียกใช้ Adapter และ Retcode handling ร่วมกัน
4. หากต้องทดสอบ Live close ให้ตกลงขั้นตอน Demo integration แยกต่างหากก่อนส่งคำสั่งจริง

**สถานะปัจจุบัน: Completed — ผู้ใช้รายงานว่า 10 Tests ผ่านใน MetaEditor/MT5 เมื่อ 2026-10-31**
