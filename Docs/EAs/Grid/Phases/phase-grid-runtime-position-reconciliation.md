# Phase: Grid Runtime & Position Reconciliation — Round 1

- สถานะ: Implemented; รอผู้ใช้ Compile/Run Test EA ใหม่และ Regression Tests ใน MetaEditor/MT5
- เริ่ม Phase: 2026-10-29

## เป้าหมาย

สร้างขอบเขตที่ปลอดภัยสำหรับอ่านจำนวน Position ของ Grid Instance และประเมินความคืบหน้าการปิด Position ก่อนที่ Lifecycle/State Machine จะได้รับจำนวน Position ที่ยืนยันจากบัญชีจริง โดยยังไม่ส่งคำสั่งซื้อขาย

## ขอบเขตรอบแรก

- เพิ่ม `Include/BotTrade/Grid/GridPositionReconciler.mqh`
- กรอง Position ด้วย Symbol และ Magic Number ที่ตรงกันทั้งสองค่าเท่านั้น
- เพิ่ม `CountLiveOwnedPositions()` สำหรับอ่าน Position ปัจจุบันจากบัญชี โดยไม่แก้ไข Position
- เพิ่มการนับจาก Snapshot fixture เพื่อทดสอบ ownership โดยไม่ต้องเปิด Position จริง
- แยกผลของ Close Attempt เป็น Accepted, Market Closed, Failed และ None
- การตอบรับคำสั่งปิดไม่ใช่หลักฐานว่าปิด Position สำเร็จ ต้องตรวจจำนวน Position จากบัญชีใหม่
- หากมี Position เหลือหลังรอบตรวจครั้งถัดไป ให้คืนสถานะที่เรียกให้ลองใหม่ แทนการรอไม่สิ้นสุด
- เมื่อจำนวน Position ที่ตรวจใหม่เป็นศูนย์ จึงถือว่าการปิดครบแล้ว
- หากจำนวน Position ติดลบ/ไม่ถูกต้อง ให้เข้าสู่ Recovery Error
- เพิ่ม `Experts/TGK/Tests/Grids/test_grid_position_reconciler.mq5` ซึ่งไม่มีคำสั่งซื้อขายจริง

## การเชื่อมต่อกับ Lifecycle

ผู้เรียกต้องใช้ `CountLiveOwnedPositions(symbol, magic)` เพื่ออ่านจำนวน Position ล่าสุด แล้วจึงส่งจำนวนที่อ่านได้ให้ `CTGKGridLifecycle.AdvanceReset()` ตามความเหมาะสม ห้ามใช้จำนวนจาก Snapshot เก่าหรือถือว่า Close request ที่ตอบรับแล้วหมายถึงไม่มี Position เหลืออยู่

คลาส Reconciler นี้เป็น policy/read-only boundary เท่านั้น ไม่ได้ส่ง Close request และไม่ได้เปลี่ยน Lifecycle โดยตรง

## สิ่งที่ยังอยู่นอกขอบเขต

- ไม่เรียก `CTrade.PositionClose()` หรือส่งคำสั่งเปิด/ปิด Position
- ไม่สร้าง Grid Levels, ตรวจ Bounds, เปิด Initial Entry, จัดการ TP หรือ Re-entry
- ยังไม่มี EA Runtime ที่ประสาน Account scan, Close request และ Lifecycle แบบครบวงจร
- การเปิด/ปิดคำสั่งจริงจะเป็นขอบเขต Phase แยก และต้องได้รับอนุมัติชัดเจนก่อนเริ่ม

## Test-first coverage

`test_grid_position_reconciler.mq5` ครอบคลุม:

1. Position ต้องตรงทั้ง Symbol และ Magic Number จึงเป็นของ Instance นี้
2. นับเฉพาะ Position ที่ตรงกับ Instance จากข้อมูลจำลอง
3. Close request ที่ Accepted ต้องรอตรวจบัญชีใหม่ ไม่ถือว่าปิดสำเร็จทันที
4. หาก Position ยังเหลือหลังรอบตรวจ ให้ลองใหม่ได้
5. Market Closed และ Failed ต้องไม่ทำให้ระบบคิดว่าปิดสำเร็จ
6. Reconciler ที่สร้างใหม่หลัง Restart ต้องตรวจสถานะ Position ใหม่ ไม่สมมติว่าคำขอเดิมยัง pending
7. จำนวน Position ที่ไม่ถูกต้องทำให้เข้า Recovery Error

## การตรวจสอบ

- Baseline ก่อนเริ่ม Phase นี้คือผล 7/7 tests ที่ผู้ใช้รายงานว่าผ่านเมื่อ 2026-10-28
- หลังแก้ Source ผู้ใช้ต้อง Compile/Run `test_grid_position_reconciler.mq5` และ Regression Tests ทั้ง 7 ไฟล์ใน MetaEditor/MT5
- Assistant ตรวจ `git diff --check` และ Source/Docs ด้วย Serena; ไม่ได้รัน MetaEditor/MT5 และไม่อ้างว่า MQL5 Compile/Runtime ผ่าน
