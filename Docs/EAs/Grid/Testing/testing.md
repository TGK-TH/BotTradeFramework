# คู่มือทดสอบ Grid

อัปเดตล่าสุด: 2026-11-09

## ก่อนเริ่ม

- เปิด Repository ที่เป็น Source of Truth: `BotTradeFramework`
- Compile Test EA ใน MetaEditor แล้วรันบนกราฟตามวิธีของ Test นั้น
- อ่านผลจากแท็บ Experts
- อย่าถือว่าการตรวจโค้ดผ่านหมายถึง Compile/Runtime ผ่าน
- Unit/Regression Test EA ไม่ส่งคำสั่งซื้อขายจริง; ข้อยกเว้นคือ Demo Integration Test ที่ระบุชัดเจนว่าต้องเปิด Safety Input และคลิก START บนบัญชี Demo เท่านั้น ควรตรวจ Source Code ก่อนรันหากไฟล์มีการเปลี่ยนแปลงภายหลัง

## Unit Tests: Framework

| ไฟล์ | สิ่งที่ทดสอบ | ผลที่ผู้ใช้รายงาน |
|---|---|---|
| `Experts/TGK/Tests/Framework/test_framework.mq5` | Smoke test ของ Test framework | ผ่าน |
| `Experts/TGK/Tests/Framework/test_framework_selftest.mq5` | ตรวจว่า Runner นับ Assertion ที่ล้มเหลวและ Test ที่ไม่มี Assertion ได้ถูกต้อง | ผ่าน |

ใน Self-test จะมี Diagnostic Probe ที่ตั้งใจพิมพ์ผล FAIL เพื่อทดสอบตัวตรวจจับ ความสำเร็จที่ใช้ตัดสินคือผลของ Outer Self-test Suite ที่ต้องเป็น PASS

## Unit/Integration Tests: Grid components

| ไฟล์ | สิ่งที่ทดสอบ | ผลที่ผู้ใช้รายงาน |
|---|---|---|
| `Experts/TGK/Tests/Grids/test_grid_types.mq5` | Enum และการกำหนด/อ่านค่าฟิลด์ของโครงสร้างข้อมูล | PASS (ผู้ใช้ยืนยัน Regression 11/11 เมื่อ 2026-11-07) |
| `Experts/TGK/Tests/Grids/test_grid_persistence.mq5` | Save/Restore, mismatch, invalid enum, Level State และ Delete | PASS (ผู้ใช้ยืนยัน Regression 11/11 เมื่อ 2026-11-07) |
| `Experts/TGK/Tests/Grids/test_grid_level_engine.mq5` | Two-sided levels, Anchor Re-entry, State transitions, Candidate selection และ exact crossing | PASS (ผู้ใช้รายงาน 2026-11-04) |
| `Experts/TGK/Tests/Grids/test_grid_level_runtime_coordinator.mq5` | Candidate handoff, one unresolved request, Deferred Candidate, initial Anchor registration, explicit Position mapping, partial/full close และ close reason validation | PASS (ผู้ใช้ยืนยัน Regression 12/12 เมื่อ 2026-11-09) |
| `Experts/TGK/Tests/Grids/test_grid_entry_mapping_storage.mq5` | Append/Replay Journal, Schema/Sequence, large decimal identifier text, Instance isolation, Comment independence, incomplete tail และ malformed record; ไม่มี Trade Request | รอผู้ใช้ Compile/Run |
| `Experts/TGK/Tests/Grids/test_grid_identity.mq5` | Initialize และ Identity คงเดิมเมื่อเรียกซ้ำบนกราฟเดียว | ผ่าน |
| `Experts/TGK/Tests/Grids/test_grid_lifecycle.mq5` | Lifecycle + Persistence integration, Anchor restore, reset recovery และ safe error state | ผ่าน (ผู้ใช้รายงาน 2026-10-29) |
| `Experts/TGK/Tests/Grids/test_grid_position_reconciler.mq5` | Ownership filtering ด้วย Symbol + Magic Number, close-attempt outcomes, fresh position reconciliation และ retry policy | ผ่าน (ผู้ใช้รายงาน 2026-10-29; ยืนยันซ้ำ 2026-10-30) |
| `Experts/TGK/Tests/Grids/test_grid_runtime_orchestrator.mq5` | ประสาน Lifecycle/Position Reconciler, reset-close retry, restart ระหว่าง reset และ safe recovery | ผ่าน (ผู้ใช้รายงาน 2026-10-30) |
| `Experts/TGK/Tests/Grids/test_grid_order_execution.mq5` | Ownership filtering, CLOSE_REQUIRED gate, retcode classification, aggregate batch result และ Adapter identity guard; ไม่มี trade request | ผ่าน (ผู้ใช้รายงาน 2026-10-31) |
| `Experts/TGK/Tests/Grids/test_grid_identity_multichart.mq5` | กราฟคนละหน้าต่างต้องได้ Instance ID และ Magic Number คนละค่า | ผ่าน |
| `Experts/TGK/Tests/Grids/test_grid_restart_persistence.mq5` | Restore Identity, Snapshot และ Level State หลัง Restore กราฟ/โปรไฟล์ | ผ่านหลังปรับเงื่อนไข Chart ID |

ผลทั้งหมดข้างต้นเป็นผลที่ผู้ใช้รายงานจาก MetaEditor/MT5 ไม่ใช่ผลจากการรันโดย Assistant

## Grid Entry Mapping Storage — implementation foundation (2026-11-09)

เพิ่ม Test EA `test_grid_entry_mapping_storage.mq5` สำหรับ Append/Replay Journal โดยไม่มี Trade Request:
- Validate Symbol/Instance identity และชื่อไฟล์แยก Instance
- Append หลาย Record และตรวจ Sequence
- Round-trip Identifier ที่เกิน (2^{53}) ในรูป Decimal String
- ตรวจ Comment เป็น Opaque Payload ไม่ใช่ Mapping Key
- Ignore เฉพาะ Incomplete Tail และตัด Tail ก่อน Append ครั้งถัดไป
- Reject Complete Malformed Record

สถานะ: Source/Test ถูกเพิ่มแล้ว แต่ยังรอผู้ใช้ Compile/Run ใน MetaEditor/MT5 จึงยังไม่มีผล PASS/FAIL ที่ยืนยันได้ การทดสอบนี้ยังไม่ครอบคลุม Typed Mapping Reducer, Write/Flush Failure Injection, Entry Policy หรือ CTrade Adapter

## Grid Order Execution Adapter — Round 1 (2026-10-31)

ผู้ใช้ยืนยันว่า Compile และ Run ผ่านครบทั้ง 10 Tests หลังเพิ่ม Order Execution Policy/Adapter:

- `test_grid_order_execution.mq5` — ผ่าน
- `test_grid_runtime_orchestrator.mq5` — ผ่าน
- `test_grid_position_reconciler.mq5` — ผ่าน
- `test_grid_lifecycle.mq5` — ผ่าน
- `test_grid_state_machine.mq5` — ผ่าน
- `test_grid_types.mq5` — ผ่าน
- `test_grid_persistence.mq5` — ผ่าน
- `test_grid_identity.mq5` — ผ่าน
- `test_grid_identity_multichart.mq5` — ผ่าน
- `test_grid_restart_persistence.mq5` — ผ่าน

ผลนี้ยืนยันเฉพาะ Unit/Regression Tests ที่ไม่ส่งคำสั่งปิด Position จริง ยังไม่ได้ยืนยัน Demo integration ของ CTrade close request

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

## Grid Lifecycle Integration Test — ผ่านตามผลผู้ใช้รายงาน (2026-10-29)

ไฟล์: `Experts/TGK/Tests/Grids/test_grid_lifecycle.mq5`

ทดสอบโดยไม่ส่งคำสั่งซื้อขาย:

- Instance ใหม่ที่ไม่มี Position เริ่มที่ `WAIT_INITIAL_ENTRY`
- บันทึก Fill จริงและ Restore Anchor/State ได้
- Mode reset ยังคงอยู่หลัง Restart และไม่ Apply จนจำนวน Position ที่ตรวจยืนยันเป็นศูนย์
- ไม่มี Snapshot แต่มี Position ให้เข้า `RECOVERY_ERROR`
- Magic Number ไม่ตรงกับ Snapshot ให้เข้า `RECOVERY_ERROR`
- Snapshot มี Commit Marker แต่ข้อมูล Mode เสียหาย ให้เข้า `RECOVERY_ERROR`

ผู้ใช้รายงานเมื่อ 2026-10-29 ว่า Compile/Runtime Test นี้ผ่าน และ Regression Tests ที่เกี่ยวข้องผ่านทั้งหมดหลังการแก้ Source ใน Phase นี้

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

## Grid Runtime & Position Reconciliation Test — ผ่านตามผลผู้ใช้รายงาน (2026-10-29)

ไฟล์: `Experts/TGK/Tests/Grids/test_grid_position_reconciler.mq5`

Test EA นี้ไม่ส่งคำสั่งซื้อขาย ครอบคลุม:

- Position ต้องตรงทั้ง Symbol และ Magic Number จึงนับเป็นของ Instance นี้
- นับจาก Snapshot fixture โดยไม่ต้องเปิด Position จริง
- Close attempt ที่ Accepted ต้องรอตรวจบัญชีใหม่ และถ้ายังมี Position ในการตรวจรอบถัดไปต้องลองใหม่ได้
- Market Closed หรือ Failed ไม่ถือว่าปิดสำเร็จ
- Reconciler ที่สร้างใหม่หลัง Restart ต้องตรวจ Position ใหม่
- Count ที่ไม่ถูกต้องต้องเข้า Recovery Error แทนการตีความว่า Position เป็นศูนย์

ผู้ใช้รายงานว่า Compile/Run Test นี้และ Regression Tests ทั้ง 7 ไฟล์เดิมผ่านครบทั้งหมดใน MetaEditor/MT5 เมื่อ 2026-10-29

## Grid Runtime Orchestration Test — ผ่านตามผลผู้ใช้รายงาน (2026-10-30)

ไฟล์: `Experts/TGK/Tests/Grids/test_grid_runtime_orchestrator.mq5`

Test EA นี้ใช้ Snapshot fixture และไม่ส่งคำสั่งซื้อขาย ครอบคลุม:

- Fresh instance เริ่มที่ `WAIT_INITIAL_ENTRY` และเปลี่ยนเป็น `ACTIVE` หลังบันทึก Fill จริง
- Reset ส่งสถานะ `CLOSE_REQUIRED` เมื่อยังมี Position ของ Instance
- Close attempt ที่ Accepted ต้องรอการตรวจ Position รอบใหม่; หาก Position ยังอยู่จะกลับไป `CLOSE_REQUIRED`
- เมื่อ Position เป็นศูนย์ จึง Apply pending Mode และกลับไปรอ Initial Entry
- Restart ระหว่าง pending reset ต้อง Restore และ reconcile จาก Position snapshot ใหม่
- Close failure และ Market Closed ต้องคงความสามารถในการ Retry
- ไม่มี Snapshot แต่มี Position ต้องไม่ Adopt และต้องรายงาน `ERROR`

**ผลการทดสอบ:** ผู้ใช้รายงานเมื่อ 2026-10-30 ว่า Compile/Run `test_grid_runtime_orchestrator.mq5` และ Grid Regression Tests เดิมทั้ง 8 ไฟล์ใน MetaEditor/MT5 ผ่านทั้งหมด รวม 9 ไฟล์ จึงถือว่า Grid Runtime Orchestration Round 1 เสร็จสมบูรณ์ ผลนี้เป็นการยืนยันจากผู้ใช้ ไม่ใช่การรัน MetaEditor/MT5 โดย Assistant

## Grid Order Execution Policy Test — เพิ่มแล้ว รอผล Compile/Runtime

ไฟล์: `Experts/TGK/Tests/Grids/test_grid_order_execution.mq5`

Unit Test นี้ Compile ทั้ง Policy และ Adapter แต่ไม่ส่งคำสั่งซื้อขายจริง ทดสอบ:

- Close Batch ต้องมีเฉพาะ Ticket ที่ตรง Symbol + Magic Number
- ไม่สร้าง Batch เมื่อ Runtime status ไม่ใช่ CLOSE_REQUIRED
- ปฏิเสธ Identity ที่ไม่ถูกต้อง
- จำแนก DONE, DONE_PARTIAL และ PLACED เป็น Accepted เพื่อรอ Reconciliation
- จำแนก MARKET_CLOSED และ Failed request เป็นผลลัพธ์ที่ต้อง Retry
- รวมผล Batch ที่มีทั้ง Accepted, Market Closed และ Failed อย่างระมัดระวัง
- Batch ว่างไม่ถือเป็นการปิดสำเร็จ

ผล Compile/Runtime: ยังไม่มีการยืนยันจากผู้ใช้

## Grid Order Execution — Demo Integration Test (Implementation รอ Compile/Runtime)

ไฟล์: `Experts/TGK/Tests/Grids/test_grid_order_execution_demo.mq5`

Test EA นี้แยกจาก EA หลักและส่งคำสั่งซื้อขายจริงบน Demo เพื่อทดสอบเส้นทาง CTrade close:

- ค่าเริ่มต้น EnableDemoTest=false และต้องคลิก START บนกราฟหลังเปิด Input เป็น true
- ปฏิเสธบัญชีเงินจริง/Contest และบัญชีที่ไม่ใช่ Hedging
- ตรวจสิทธิ์ Trade และ Volume Min/Max/Step ก่อนส่งคำสั่ง
- เปิด Owned BUY 2 Positions ด้วย Instance Magic และ Foreign BUY 1 Position ด้วย Magic ที่แยกและตรวจ collision แล้ว
- บันทึก Fill Price จริงของ Owned Position แรกเป็น Anchor
- Request Mode reset แล้วใช้ Runtime + Adapter ปิดเฉพาะ Owned Positions
- ยืนยัน Foreign Position ด้วย Symbol + Magic + Ticket และแสดงปุ่ม CLEANUP FOREIGN POSITION ให้ผู้ใช้ตรวจสอบก่อน
- เมื่อผู้ใช้กด Cleanup จะตรวจ Ticket/Symbol/Magic/จำนวนซ้ำก่อนปิดด้วย PositionClose(ticket)
- Final Verification ต้องพบ Owned=0 และ Foreign=0 จึงรายงาน FINAL PASS
- หาก Test ล้มเหลว จะหยุดและรายงาน Test Magic/Ticket/จำนวนที่อาจเหลือ โดยไม่พยายามปิด Position ที่ไม่ตรงกับ Test Identity

**วิธีใช้:** ใช้บัญชี Demo แบบ Hedging บนกราฟใหม่ที่ไม่มี Production Grid EA, Compile EA, เปิด EnableDemoTest=true และคลิก START เมื่อพร้อม จากนั้นตรวจ Foreign Position ใน Trade tab ก่อนคลิก CLEANUP FOREIGN POSITION

**ข้อควรระวัง:** Test EA เปิด BUY 3 Positions ตาม TestLot และอาจมี Spread/Commission; หาก Test หยุดกลางคันให้ตรวจและจัดการ Test Positions ด้วย Symbol + Magic Number ก่อนเริ่มใหม่

ผลการทดสอบ (ผู้ใช้รายงาน 2026-11-02): Compile ผ่านและ Demo Integration ผ่านครบ โดยเปิด Owned BUY 2 + Foreign BUY 1, Adapter ปิด Owned ได้ครบและตรวจว่า Foreign Ticket/Magic เดิมยังอยู่ จากนั้นผู้ใช้กด CLEANUP เพื่อปิด Foreign Position และ EA รายงาน `TGK DEMO INTEGRATION: FINAL RESULT: PASS` เวลา 22:58:52

ผลนี้ยืนยันเส้นทาง Live Scan, ticket-specific `CTrade.PositionClose()` และ Runtime reconciliation ใน Demo Test Scenario เท่านั้น ไม่ใช่การยืนยันว่า Grid V1 ทั้งระบบเสร็จสมบูรณ์

## Grid Order Execution — Demo Integration Test (Implementation รอ Compile/Runtime)

ไฟล์: `Experts/TGK/Tests/Grids/test_grid_order_execution_demo.mq5`

Test EA นี้แยกจาก EA หลักและส่งคำสั่งซื้อขายจริงบน Demo เพื่อทดสอบเส้นทาง CTrade close:

- ค่าเริ่มต้น EnableDemoTest=false และต้องคลิก START บนกราฟหลังเปิด Input เป็น true
- ปฏิเสธบัญชีเงินจริง/Contest และบัญชีที่ไม่ใช่ Hedging
- ตรวจสิทธิ์ Trade และ Volume Min/Max/Step ก่อนส่งคำสั่ง
- เปิด Owned BUY 2 Positions ด้วย Instance Magic และ Foreign BUY 1 Position ด้วย Magic ที่แยกและตรวจ collision แล้ว
- บันทึก Fill Price จริงของ Owned Position แรกเป็น Anchor
- Request Mode reset แล้วใช้ Runtime + Adapter ปิดเฉพาะ Owned Positions
- ยืนยัน Foreign Position ด้วย Symbol + Magic + Ticket และแสดงปุ่ม CLEANUP FOREIGN POSITION ให้ผู้ใช้ตรวจสอบก่อน
- เมื่อผู้ใช้กด Cleanup จะตรวจ Ticket/Symbol/Magic/จำนวนซ้ำก่อนปิดด้วย PositionClose(ticket)
- Final Verification ต้องพบ Owned=0 และ Foreign=0 จึงรายงาน FINAL PASS
- หาก Test ล้มเหลว จะหยุดและรายงาน Test Magic/Ticket/จำนวนที่อาจเหลือ โดยไม่พยายามปิด Position ที่ไม่ตรงกับ Test Identity

**วิธีใช้:** ใช้บัญชี Demo แบบ Hedging บนกราฟใหม่ที่ไม่มี Production Grid EA, Compile EA, เปิด EnableDemoTest=true และคลิก START เมื่อพร้อม จากนั้นตรวจ Foreign Position ใน Trade tab ก่อนคลิก CLEANUP FOREIGN POSITION

**ข้อควรระวัง:** Test EA เปิด BUY 3 Positions ตาม TestLot และอาจมี Spread/Commission; หาก Test หยุดกลางคันให้ตรวจและจัดการ Test Positions ด้วย Symbol + Magic Number ก่อนเริ่มใหม่

ผลการทดสอบ (ผู้ใช้รายงาน 2026-11-02): Compile ผ่านและ Demo Integration ผ่านครบ โดยเปิด Owned BUY 2 + Foreign BUY 1, Adapter ปิด Owned ได้ครบและตรวจว่า Foreign Ticket/Magic เดิมยังอยู่ จากนั้นผู้ใช้กด CLEANUP เพื่อปิด Foreign Position และ EA รายงาน `TGK DEMO INTEGRATION: FINAL RESULT: PASS` เวลา 22:58:52

ผลนี้ยืนยันเส้นทาง Live Scan, ticket-specific `CTrade.PositionClose()` และ Runtime reconciliation ใน Demo Test Scenario เท่านั้น ไม่ใช่การยืนยันว่า Grid V1 ทั้งระบบเสร็จสมบูรณ์

## Grid Level Runtime Coordinator — Round 1 (Completed — User Verified 12/12 PASS, 2026-11-09)

เอกสาร Contract และ Test Plan: [phase-grid-level-runtime-coordinator-round-1.md](../Phases/phase-grid-level-runtime-coordinator-round-1.md)

Source: `Include/BotTrade/Grid/GridLevelRuntimeCoordinator.mqh`
Test EA: `Experts/TGK/Tests/Grids/test_grid_level_runtime_coordinator.mq5`

ขอบเขต Test สำคัญ:
- Serialized Entry Request: หนึ่ง unresolved request ต่อ Instance
- Deferred Candidate: BUY เก็บราคาต่ำสุด / SELL เก็บราคาสูงสุด และตรวจ Level State ล่าสุดก่อนนำกลับมาใช้
- Accepted/Placed ไม่เปลี่ยน Level เป็น ACTIVE; ต้องมี Reconciliation ยืนยัน Position ที่ Mapping ตรง Request
- Position mapping ต้องตรวจ Symbol + Magic + Ticket + Anchor/Level Index + Volume และปฏิเสธ mapping ซ้ำ/ไม่ถูกต้อง
- Partial Close คง ACTIVE; Full Close ต้องทราบ TP/Non-TP ก่อนเปลี่ยน State
- Coordinator ไม่มี Trade API หรือ Live Account API

**Baseline:** ผู้ใช้ยืนยันว่า Grid Regression Tests เดิมครบ 11 ไฟล์ผ่านทั้งหมดเมื่อ 2026-11-07 ก่อนเริ่ม Implementation

**ผลการทดสอบ (ผู้ใช้รายงาน 2026-11-09): PASS 12/12** — `test_grid_level_runtime_coordinator.mq5` และ Grid Regression Tests เดิมทั้ง 11 ไฟล์ Compile และ Run ผ่านทั้งหมดใน MetaEditor/MT5 ผลนี้เป็นการยืนยันจากผู้ใช้; Assistant ไม่ได้รัน MetaEditor/MT5 เอง

## Grid Level Engine — Round 1 Test Plan (ผ่านตามผลผู้ใช้รายงาน 2026-11-04)

Design Specification: [phase-grid-level-engine-design.md](../Phases/phase-grid-level-engine-design.md)

Test EA ที่เตรียมไว้: `Experts/TGK/Tests/Grids/test_grid_level_engine.mq5`

หลังจาก Design Review ผู้ใช้ยืนยันข้อกำหนดหลักแล้ว Test Plan ต้องครอบคลุม:
- Two-sided Level calculation, Anchor แยกจาก Grid Levels, `level_count` ไม่นับ Anchor และ Bounds แบบ Hard Filter
- Initial State ตาม Current Price (BUY ใช้ Ask, SELL ใช้ Bid)
- Activation และ Retrace ในทิศทางที่ถูกต้อง
- Candidate selection: BUY ราคาต่ำที่สุด, SELL ราคาสูงที่สุด, สูงสุดหนึ่ง Candidate ต่อ Price Check
- Candidate selection ที่รวมทั้ง `READY` และ `WAIT_RETURN`, รวมถึง Anchor
- Unselected `READY`/`WAIT_RETURN` ที่ถูกข้ามและอยู่ผิดด้านของราคาเปลี่ยนเป็น `WAIT_ACTIVATION`; `ACTIVE` คงเดิม
- Retry/Reconciliation และการแทน Candidate เดิมด้วย Candidate ที่ดีกว่า
- ยืนยัน Position จริงก่อนเปลี่ยนเป็น `ACTIVE`
- TP -> `WAIT_RETURN`; SL/Manual/Other close ใช้ Current Price กำหนด State
- Anchor TP/Re-entry และการแยก State ของแต่ละ Level

**ผลการทดสอบ (ผู้ใช้รายงาน 2026-11-04): PASS** — ผู้ใช้ Compile ใหม่และรัน Grid Regression Tests ครบทั้ง 11 ไฟล์ใน MetaEditor/MT5 ผ่านทั้งหมด รวม `test_grid_level_engine.mq5` ซึ่งเป็น Test ใหม่ของ Round 1 รายละเอียด Edge Contracts อยู่ใน [Implementation Round 1](../Phases/phase-grid-level-engine-implementation-round-1.md)

ผลนี้เป็นการยืนยันจากผู้ใช้ ไม่ใช่การรัน MetaEditor/MT5 โดย Assistant และยังไม่ครอบคลุม Production EA Event Handler หรือ Live Grid V1 Integration

## นโยบาย Regression Test

ก่อนเริ่มพัฒนาหรือ Refactor Grid feature ให้ระบุ Regression Tests ที่เกี่ยวข้องและรันก่อนแก้โค้ด หากพฤติกรรมที่กำลังจะเปลี่ยนยังไม่มี Test รองรับ ให้ตกลงและเพิ่ม Test ก่อนหรือเป็นส่วนหนึ่งของงานตามขอบเขตที่อนุมัติ
