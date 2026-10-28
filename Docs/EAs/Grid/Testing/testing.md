# คู่มือทดสอบ Grid

อัปเดตล่าสุด: 2026-10-27

## ก่อนเริ่ม

- เปิด Repository ที่เป็น Source of Truth: `BotTradeFramework`
- Compile Test EA ใน MetaEditor แล้วรันบนกราฟตามวิธีของ Test นั้น
- อ่านผลจากแท็บ Experts
- อย่าถือว่าการตรวจโค้ดผ่านหมายถึง Compile/Runtime ผ่าน
- Test EA ในชุดที่อธิบายด้านล่างไม่ควรส่งคำสั่งซื้อขายจริง แต่ควรตรวจ Source Code ก่อนรันหากไฟล์มีการเปลี่ยนแปลงภายหลัง

## Unit Tests: Framework

| ไฟล์ | สิ่งที่ทดสอบ | ผลที่ผู้ใช้รายงาน |
|---|---|---|
| `Experts/TGK/Tests/Framework/test_framework.mq5` | Smoke test ของ Test framework | ผ่าน |
| `Experts/TGK/Tests/Framework/test_framework_selftest.mq5` | ตรวจว่า Runner นับ Assertion ที่ล้มเหลวและ Test ที่ไม่มี Assertion ได้ถูกต้อง | ผ่าน |

ใน Self-test จะมี Diagnostic Probe ที่ตั้งใจพิมพ์ผล FAIL เพื่อทดสอบตัวตรวจจับ ความสำเร็จที่ใช้ตัดสินคือผลของ Outer Self-test Suite ที่ต้องเป็น PASS

## Unit/Integration Tests: Grid components

| ไฟล์ | สิ่งที่ทดสอบ | ผลที่ผู้ใช้รายงาน |
|---|---|---|
| `Experts/TGK/Tests/Grids/test_grid_types.mq5` | Enum และการกำหนด/อ่านค่าฟิลด์ของโครงสร้างข้อมูล | ผ่าน |
| `Experts/TGK/Tests/Grids/test_grid_persistence.mq5` | Save/Restore, mismatch, invalid enum, Level State และ Delete | ผ่าน |
| `Experts/TGK/Tests/Grids/test_grid_identity.mq5` | Initialize และ Identity คงเดิมเมื่อเรียกซ้ำบนกราฟเดียว | ผ่าน |
| `Experts/TGK/Tests/Grids/test_grid_lifecycle.mq5` | Lifecycle + Persistence integration, Anchor restore, reset recovery และ safe error state | รอ Compile/Runtime |
| `Experts/TGK/Tests/Grids/test_grid_identity_multichart.mq5` | กราฟคนละหน้าต่างต้องได้ Instance ID และ Magic Number คนละค่า | ผ่าน |
| `Experts/TGK/Tests/Grids/test_grid_restart_persistence.mq5` | Restore Identity, Snapshot และ Level State หลัง Restore กราฟ/โปรไฟล์ | ผ่านหลังปรับเงื่อนไข Chart ID |

ผลทั้งหมดข้างต้นเป็นผลที่ผู้ใช้รายงานจาก MetaEditor/MT5 ไม่ใช่ผลจากการรันโดย Assistant

## Grid Regression Baseline ก่อน Grid State Machine (2026-10-26)

ผู้ใช้ยืนยันผล Compile/Runtime ว่าผ่านครบทั้ง 5 ไฟล์ก่อนเริ่ม Grid State Machine:

- `test_grid_types.mq5` — ผ่าน
- `test_grid_persistence.mq5` — ผ่าน
- `test_grid_identity.mq5` — ผ่าน
- `test_grid_identity_multichart.mq5` — ผ่าน
- `test_grid_restart_persistence.mq5` — ผ่าน

ให้ถือผลนี้เป็น Baseline ที่ผู้ใช้รายงานก่อนเริ่ม State Machine และรัน Regression Test ที่เกี่ยวข้องซ้ำหลังมีการแก้ Source Code

## Grid Regression หลัง Grid State Machine — ผู้ใช้รายงานว่าผ่าน (2026-10-27)

หลังเพิ่ม `GridStateMachine.mqh` ผู้ใช้ยืนยันว่า Test ใหม่ของ State Machine และ Regression Tests เดิมทั้ง 5 ไฟล์ Compile/Runtime ผ่านทั้งหมด:

- `test_grid_state_machine.mq5` — ผ่าน
- `test_grid_types.mq5` — ผ่าน
- `test_grid_persistence.mq5` — ผ่าน
- `test_grid_identity.mq5` — ผ่าน
- `test_grid_identity_multichart.mq5` — ผ่าน
- `test_grid_restart_persistence.mq5` — ผ่าน

ผลนี้เป็นการยืนยันจากผู้ใช้ ไม่ใช่การรัน MetaEditor/MT5 โดย Assistant

## Grid State Machine Test — ผู้ใช้รายงานว่าผ่าน (2026-10-27)

ไฟล์: `Experts/TGK/Tests/Grids/test_grid_state_machine.mq5`

ทดสอบ State transitions โดยไม่ส่งคำสั่งซื้อขาย:

- Initialize และรอ Fill แรก
- ใช้ราคาที่ Fill จริงเป็น Anchor
- Mode change ต้องรอให้จำนวน Position ที่เหลือเป็นศูนย์ก่อน Apply Configuration และล้าง Anchor
- Step change ต้องคง Anchor เดิม
- ปฏิเสธ Configuration/Fill ที่ไม่ถูกต้อง
- `RECOVERY_ERROR` ต้องปิดกั้นการเปลี่ยน State

ผู้ใช้ยืนยันว่า Compile และรัน Test นี้ผ่านใน MetaEditor/MT5 เมื่อ 2026-10-27

## Grid Lifecycle Integration Test — รอผู้ใช้ยืนยัน

ไฟล์: `Experts/TGK/Tests/Grids/test_grid_lifecycle.mq5`

ทดสอบโดยไม่ส่งคำสั่งซื้อขาย:

- Instance ใหม่ที่ไม่มี Position เริ่มที่ `WAIT_INITIAL_ENTRY`
- บันทึก Fill จริงและ Restore Anchor/State ได้
- Mode reset ยังคงอยู่หลัง Restart และไม่ Apply จนจำนวน Position ที่ตรวจยืนยันเป็นศูนย์
- ไม่มี Snapshot แต่มี Position ให้เข้า `RECOVERY_ERROR`
- Magic Number ไม่ตรงกับ Snapshot ให้เข้า `RECOVERY_ERROR`
- Snapshot มี Commit Marker แต่ข้อมูล Mode เสียหาย ให้เข้า `RECOVERY_ERROR`

ข้อกำหนดการรัน: ใช้กราฟ Demo/Test ที่ไม่มีการส่งคำสั่งซื้อขายจาก Test EA นี้ ตัว Test ใช้ Namespace เฉพาะและพยายามลบ Snapshot ที่สร้างหลังจบการทดสอบ หาก Test ถูกหยุดกลางคันอาจมี Global Variables ค้างอยู่ภายใต้ Instance ID ที่ขึ้นต้นด้วย `L` พร้อม timestamp

## ขั้นตอนทดสอบ Multi-chart Identity

1. Compile `test_grid_identity_multichart.mq5`
2. Attach EA บนกราฟหนึ่ง
3. ตรวจ Experts Log ว่า Test Suite จบด้วย PASS
4. EA จะเปิดกราฟชั่วคราว Symbol/Timeframe เดียวกันเพื่อทดสอบ Identity แยกกัน แล้วปิดกราฟทดสอบนั้น
5. Test นี้อาจใช้ค่าใน Magic sequence ไปหนึ่งลำดับ แม้จะลบ Registry ของกราฟชั่วคราวแล้ว

## ขั้นตอนทดสอบ Restart Persistence

1. บันทึก Profile ที่มีกราฟทดสอบไว้
2. Attach `test_grid_restart_persistence.mq5` และใช้ `TestSlot` เช่น `R1`
3. รอบแรกจะบันทึก Test Fixture และพิมพ์คำแนะนำใน Experts Log
4. สลับไป Profile อื่น แล้วกลับมา Profile ที่บันทึกไว้
5. Attach EA อีกครั้งบนกราฟที่ถูก Restore โดยใช้ `TestSlot` เดิม
6. ตรวจผลการกู้คืน Instance ID, Magic Number, Snapshot และสถานะ Level
7. รอบสองจะลบข้อมูลทดสอบของ Slot นั้นหลังการตรวจเสร็จ

ข้อควรระวัง:

- อย่าใช้ TestSlot เดียวกันกับการทดสอบพร้อมกันหลายกราฟ
- หากหยุดหลังรอบแรก ข้อมูล Global Variables สำหรับทดสอบอาจยังคงอยู่ ต้องกลับมารันให้ครบหรือทำความสะอาดเฉพาะ Namespace ของ Test
- Chart ID แสดงเป็นข้อมูลวินิจฉัยเท่านั้น ไม่ใช่ Assertion เพราะ MT5 อาจนำ Chart ID เดิมกลับมาใช้ตอน Restore Profile
- การปิดกราฟเดิมแล้วเปิดกราฟใหม่ด้วยตนเองเป็นคนละกรณีกับการ Restore Profile การได้ Instance ID/Magic Number ใหม่อาจเป็นพฤติกรรมที่คาดหมาย และไม่ได้พิสูจน์การ Restore Grid เดิม

## นโยบาย Regression Test

ก่อนเริ่มพัฒนาหรือ Refactor Grid feature ให้ระบุ Regression Tests ที่เกี่ยวข้องและรันก่อนแก้โค้ด หากพฤติกรรมที่กำลังจะเปลี่ยนยังไม่มี Test รองรับ ให้ตกลงและเพิ่ม Test ก่อนหรือเป็นส่วนหนึ่งของงานตามขอบเขตที่อนุมัติ
