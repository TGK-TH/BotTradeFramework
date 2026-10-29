# ภาพรวมสถาปัตยกรรม Grid

อัปเดตล่าสุด: 2026-10-29

## ขอบเขตของเอกสาร

เอกสารนี้อธิบาย Grid components ที่มีอยู่ใน Source Code ณ วันที่อัปเดต ไม่ใช่คำอธิบาย Grid Engine ที่เสร็จสมบูรณ์แล้ว ปัจจุบันมีโครงสร้างข้อมูล ระบบ Identity ระบบ Persistence และ State Machine รอบแรกที่จัดการ Lifecycle transitions โดยยังไม่มี Order Execution และยังไม่ครอบคลุมข้อกำหนด Grid V1 ทั้งหมด

## ส่วนประกอบปัจจุบัน

```text
EA / Test EA
   |
   +--> CTGKGridIdentity
   |       +--> Hidden chart marker
   |       +--> Terminal Global Variables สำหรับ Magic registry/sequence/lock
   |
   +--> STGKGridInstanceData (ประกาศใน GridTypes.mqh)
   |
   +--> CTGKGridLifecycle
   |       +--> Coordinates State Machine + Persistence
   |       +--> Safe recovery errors (no order execution)
   |
   +--> CTGKGridPositionReconciler
   |       +--> Read-only position scan filtered by Symbol + Magic
   |       +--> Close-attempt/reconciliation policy (no close requests)
   |
   +--> CTGKGridStateMachine
   |       +--> Lifecycle transitions only (no order execution)
   |
   +--> CTGKGridPersistence
           +--> Terminal Global Variables สำหรับ Snapshot
           +--> Terminal Global Variables สำหรับสถานะของแต่ละ Level

MQL5 Test EAs
   |
   +--> CTGKTestRunner
           +--> CTGKTestAssert
```

## ไฟล์หลัก

| ไฟล์ | หน้าที่ปัจจุบัน |
|---|---|
| `Include/BotTrade/Grid/GridTypes.mqh` | ประกาศ Enum และโครงสร้างข้อมูลที่ใช้แทนสถานะของ Grid |
| `Include/BotTrade/Grid/GridIdentity.mqh` | สร้าง/กู้คืน Instance ID จากวัตถุที่ซ่อนบนกราฟ และจัดสรร Magic Number |
| `Include/BotTrade/Grid/GridPersistence.mqh` | บันทึกและกู้คืน Snapshot และสถานะราย Level ด้วย Terminal Global Variables |
| `Include/BotTrade/Grid/GridStateMachine.mqh` | จัดการ Lifecycle transitions; ไม่ส่งคำสั่งซื้อขายและต้องรับจำนวน Position ที่ตรวจยืนยันแล้วจากผู้เรียก |
| `Include/BotTrade/Grid/GridLifecycle.mqh` | ประสาน State Machine กับ Persistence สำหรับ Instance ที่มี Identity แล้ว; ไม่ส่งคำสั่งซื้อขาย |
| `Include/BotTrade/Grid/GridPositionReconciler.mqh` | กรอง/นับ Position ของ Instance และประเมินผล close attempt จากสถานะบัญชีที่ตรวจใหม่; ไม่ส่งคำสั่งซื้อขาย |
| `Include/BotTrade/Testing/TestAssert.mqh` | ฟังก์ชัน Assertion พื้นฐาน |
| `Include/BotTrade/Testing/TestRunner.mqh` | จัดกลุ่ม Test นับผล และพิมพ์ PASS/FAIL |

## ขอบเขตที่ยังไม่เสร็จ

- Grid Lifecycle Integration รอบแรกยังรอผู้ใช้ Compile/Runtime Tests; ยังไม่เชื่อมกับ EA/Order Execution จริง
- Grid Position Reconciler รอบแรกเป็นเพียง read-only/policy boundary; ยังไม่มี EA Runtime ที่ส่ง Close request แล้วประสานผลกลับเข้ากับ Lifecycle แบบครบวงจร
- ยังไม่มีการจัดการคำสั่งซื้อขายหลาย Level ของ Grid ที่สมบูรณ์
- ยังไม่มีการยืนยันจากเอกสารนี้ว่าข้อกำหนดทุกข้อของ Grid V1 ถูกนำไปใช้ในโค้ดแล้ว
- Lifecycle ที่ตกลงแล้ว: การเปิดกราฟใหม่ด้วยตนเองเป็น Grid Instance ใหม่และไม่ Adopt Position ของ Instance เดิม ส่วน Grid เดิมจะกลับมาทำงานเมื่อ Restore กราฟ/โปรไฟล์เดิมและกู้ Identity/Persistence ได้

## หลักการแยกความรับผิดชอบ

- Identity ระบุว่า Grid Instance นี้คือ Instance ใด และใช้ Magic Number ใด
- Persistence เก็บข้อมูลสถานะของ Instance ที่ระบุมาให้ แต่ไม่ได้เป็นผู้กำหนด Lifecycle ของ Instance
- Types ประกาศรูปแบบข้อมูลและ Enum โดยไม่ได้ดำเนินการซื้อขายเอง
- Test framework ตรวจเงื่อนไขและรายงานผล ไม่ได้เป็นหลักฐานแทนการทดสอบจริงใน MetaEditor/MT5
