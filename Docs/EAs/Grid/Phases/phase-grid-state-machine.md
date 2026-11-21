# Phase: Grid State Machine

- สถานะ: Implementation รอบแรกเสร็จ และผู้ใช้รายงานว่า Test ใหม่กับ Regression Tests เดิมผ่านครบ (2026-10-27)
- เริ่ม Phase: 2026-10-26

## เป้าหมาย

สร้าง State Machine ที่กำหนด Lifecycle ของ Grid แยกจาก Order Execution โดยไม่ส่งคำสั่งซื้อขาย และทดสอบ Transition ก่อนนำไปเชื่อมกับ EA ที่จัดการ Position จริง

## Lifecycle ที่ตกลง

- Attach EA บนกราฟใหม่ แม้เป็น Symbol เดิม ให้เป็น Grid Instance ใหม่ ใช้ Instance ID และ Magic Number ใหม่ และไม่จัดการ Position ของ Grid เดิม
- Grid เดิมกลับมาจัดการ Instance ของตัวเองเมื่อ Restore กราฟ/โปรไฟล์เดิมและ Identity/Persistence เดิมถูกกู้คืนได้
- การเปิดกราฟใหม่ไม่ใช่กระบวนการค้นหาและ Adopt Grid เดิมโดยอัตโนมัติ

## ไฟล์ที่เพิ่ม

- `Include/BotTrade/Grid/GridStateMachine.mqh`
  - ตรวจสอบข้อมูลเริ่มต้น
  - เปลี่ยนจาก `WAIT_INITIAL_ENTRY` เป็น `ACTIVE` เมื่อได้รับราคา Fill จริง
  - ขอ Reset เมื่อ Mode, Step หรือ Magic เปลี่ยน
  - คงสถานะ `RESET_CLOSE_OLD` จนจำนวน Position ที่เหลือจากการตรวจบัญชีจริงเป็นศูนย์
  - เปลี่ยนผ่าน `RESET_REBUILD` ก่อนใช้ Configuration ใหม่
  - เมื่อเปลี่ยน Mode จะล้าง Anchor เพื่อรอ Fill แรกของ Mode ใหม่
  - เมื่อเปลี่ยน Step จะคง Anchor เดิม
  - ป้องกันการเปลี่ยน State เมื่ออยู่ใน `RECOVERY_ERROR`

- `Experts/TGK/Tests/Grids/test_grid_state_machine.mq5`
  - ทดสอบ Initial State, actual fill anchor, Mode reset, Step reset, invalid input และ Recovery Error
  - ไม่มีคำสั่งซื้อขาย

## ขอบเขตและข้อจำกัด

- State Machine ไม่ส่งคำสั่งเปิด/ปิด Position และไม่อ่าน Market Data
- ผู้เรียกต้องส่งจำนวน Position ที่เหลือจากการตรวจบัญชี โดยกรองด้วย Symbol และ Magic Number ของ Instance นั้น
- การส่งคำสั่ง Close สำเร็จยังไม่ถือว่า Position ปิดหมดแล้ว
- การตรวจ Bounds, การสร้าง Grid Levels, TP, การเปิด Level ซ้ำหลัง TP, Position Reconciler และการเชื่อมเข้ากับ EA ยังอยู่นอก Implementation รอบนี้
- ผู้ใช้ยืนยันว่า Compile/Runtime ของ Test State Machine ผ่านเมื่อ 2026-10-27

## Baseline ก่อนแก้ Source

ผู้ใช้ยืนยันเมื่อ 2026-10-26 ว่า Regression Tests เดิมทั้งห้าผ่าน ได้แก่ `test_grid_types.mq5`, `test_grid_persistence.mq5`, `test_grid_identity.mq5`, `test_grid_identity_multichart.mq5` และ `test_grid_restart_persistence.mq5`.

## ผลการทดสอบและขั้นตอนถัดไป

ผู้ใช้รายงานเมื่อ 2026-10-27 ว่า Compile และ Run `test_grid_state_machine.mq5` ผ่านใน MetaEditor/MT5 และรัน Grid Regression Tests เดิมครบทั้งห้าอีกครั้งหลังแก้ Source แล้วผ่านทั้งหมด:

- `test_grid_types.mq5` — PASS
- `test_grid_persistence.mq5` — PASS
- `test_grid_identity.mq5` — PASS
- `test_grid_identity_multichart.mq5` — PASS
- `test_grid_restart_persistence.mq5` — PASS

ผลนี้เป็นการยืนยันจากผู้ใช้ Assistant ไม่ได้รัน MetaEditor/MT5 เอง

Phase นี้ถือว่าเสร็จแล้ว ขั้นต่อไปต้องรอผู้ใช้อนุมัติขอบเขต Phase ใหม่ โดยยังไม่รวม Order Execution โดยอัตโนมัติ
